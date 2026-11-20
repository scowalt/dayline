import AuthenticationServices
import DaylineCore
import Foundation

public actor LiveCalendarService: CalendarService {
    private let writer: SnapshotStore.Writer
    private let client = GoogleClient.dayline
    private let transport = HTTPTransport()
    private let vault = KeychainVault()
    private var accessTokens: [Account.ID: AccessToken] = [:]

    public init(writer: SnapshotStore.Writer) {
        self.writer = writer
    }

    public func restore() async -> Session? {
        let accounts = vault.read().map(\.account)
        guard !accounts.isEmpty else { return nil }
        return Session(accounts: accounts, snapshot: SnapshotStore.shared?.latest())
    }

    public func signIn(authorize: WebAuthorizer, loginHint: String?) async throws(CalendarServiceError) -> Session {
        let pkce = PKCE.random()
        let state = randomURLSafeString(byteCount: 16)
        let callback: URL
        do {
            callback = try await authorize(GoogleOAuth.authorizationURL(client: client, pkce: pkce, state: state, loginHint: loginHint), client.callbackScheme)
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            throw .cancelled
        } catch is CancellationError {
            throw .cancelled
        } catch {
            throw .failed(error.localizedDescription)
        }
        let code = try google { () throws(GoogleError) in
            try GoogleOAuth.authorizationCode(from: callback, expectedState: state)
        }
        let sentAt = Date.now
        let response = try await transport.send(GoogleOAuth.codeExchangeRequest(client: client, code: code, pkce: pkce))
        let grant = try google { () throws(GoogleError) in
            try GoogleOAuth.signInGrant(from: response, receivedAt: sentAt)
        }
        if writer == .app {
            let existing = vault.read()
            if existing.isEmpty {
                SnapshotStore.shared?.clear()
            }
            try vault.save(existing.upserting(grant.credential))
        }
        accessTokens[grant.credential.account.id] = grant.accessToken
        return try await refresh()
    }

    public func refresh() async throws(CalendarServiceError) -> Session {
        let credentials = vault.read()
        guard !credentials.isEmpty else { throw .sessionExpired }
        let now = Date.now
        let window = GoogleCalendarAPI.window(containing: now, in: .current)
        let visibility = CalendarPreferences().visibility
        let outcomes = await fetchAll(credentials, window: window, visibility: visibility)
        let carried = SnapshotStore.shared?.latest()

        var fetched: [AccountSnapshot] = []
        var kept: [AccountSnapshot] = []
        var issues: [Account.ID: CalendarServiceError] = [:]
        for (credential, outcome) in zip(credentials, outcomes) {
            let id = credential.account.id
            switch outcome {
            case .success(let account):
                fetched.append(account)
                kept.append(account)
            case .failure(let error):
                issues[id] = error
                if let earlier = carried?.accounts.first(where: { $0.account.id == id }) {
                    kept.append(earlier)
                }
            }
        }

        if writer == .app, issues.count == credentials.count, issues.values.allSatisfy({ $0 == .sessionExpired }) {
            try? vault.save([])
            SnapshotStore.shared?.clear()
            accessTokens = [:]
            throw .sessionExpired
        }

        let accounts = vault.read().map(\.account)
        let signedIn = Set(accounts.map(\.id))
        fetched.removeAll { !signedIn.contains($0.account.id) }
        kept.removeAll { !signedIn.contains($0.account.id) }
        issues = issues.filter { signedIn.contains($0.key) }
        guard !accounts.isEmpty else { throw .sessionExpired }
        guard !fetched.isEmpty else {
            let snapshot = carried.flatMap { carried in
                kept.isEmpty ? nil : Snapshot(accounts: kept, range: carried.range, fetchedAt: carried.fetchedAt)
            }
            return Session(accounts: accounts, snapshot: snapshot, issues: issues)
        }
        let snapshot = Snapshot(accounts: kept, range: window, fetchedAt: now)
        try? SnapshotStore.shared?.save(snapshot, as: writer)
        return Session(accounts: accounts, snapshot: snapshot, issues: issues)
    }

    public func signOut(_ id: Account.ID) async -> Session? {
        let credentials = vault.read()
        let removed = credentials.first { $0.account.id == id }
        let remaining = credentials.filter { $0.account.id != id }
        accessTokens[id] = nil
        if writer == .app {
            try? vault.save(remaining)
        }
        if remaining.isEmpty {
            SnapshotStore.shared?.clear()
        } else {
            SnapshotStore.shared?.remove(id)
        }
        if let removed {
            let transport = transport
            await withTaskGroup(of: Void.self) { group in
                group.addTask { _ = try? await transport.send(GoogleOAuth.revokeRequest(removed.refreshToken)) }
                group.addTask { try? await Task.sleep(for: .seconds(5)) }
                await group.next()
                group.cancelAll()
            }
        }
        guard !remaining.isEmpty else { return nil }
        return Session(accounts: remaining.map(\.account), snapshot: SnapshotStore.shared?.latest())
    }

    public func refreshIfStale(maxAge: Duration) async -> Snapshot? {
        guard !vault.read().isEmpty else { return nil }
        let stored = SnapshotStore.shared?.latest()
        if let stored, Duration.seconds(Date.now.timeIntervalSince(stored.fetchedAt)) < maxAge {
            return stored
        }
        return (try? await refresh())?.snapshot ?? stored
    }

    private func fetchAll(
        _ credentials: [GoogleCredential],
        window: DateInterval,
        visibility: CalendarVisibility
    ) async -> [Result<AccountSnapshot, CalendarServiceError>] {
        await withTaskGroup(of: (Int, Result<AccountSnapshot, CalendarServiceError>).self) { group in
            for (index, credential) in credentials.enumerated() {
                group.addTask {
                    do throws(CalendarServiceError) {
                        return (index, .success(try await self.fetchAccount(credential, window: window, visibility: visibility)))
                    } catch {
                        return (index, .failure(error))
                    }
                }
            }
            var outcomes = [Result<AccountSnapshot, CalendarServiceError>?](repeating: nil, count: credentials.count)
            for await (index, outcome) in group {
                outcomes[index] = outcome
            }
            return outcomes.compactMap { $0 }
        }
    }

    private func fetchAccount(
        _ credential: GoogleCredential,
        window: DateInterval,
        visibility: CalendarVisibility
    ) async throws(CalendarServiceError) -> AccountSnapshot {
        let calendars = try await allPages(credential: credential, request: GoogleCalendarAPI.calendarListRequest, decode: GoogleCalendarAPI.calendarListPage)
        let events = try await events(in: calendars.filter(visibility.isVisible).map(\.id), window: window, credential: credential)
        return AccountSnapshot(account: credential.account, calendars: calendars, events: events)
    }

    private func events(in calendars: [CalendarID], window: DateInterval, credential: GoogleCredential) async throws(CalendarServiceError) -> [CalendarEvent] {
        let outcome = await withTaskGroup(of: Result<[CalendarEvent], CalendarServiceError>.self) { group in
            for calendar in calendars {
                group.addTask {
                    do throws(CalendarServiceError) {
                        return .success(try await self.allPages(
                            credential: credential,
                            request: { GoogleCalendarAPI.eventsRequest(calendar: calendar, window: window, pageToken: $0) },
                            decode: { response throws(GoogleError) in try GoogleCalendarAPI.eventsPage(from: response, calendar: calendar) }
                        ))
                    } catch {
                        return .failure(error)
                    }
                }
            }
            var events: [CalendarEvent] = []
            for await result in group {
                switch result {
                case .success(let page):
                    events += page
                case .failure(let error):
                    group.cancelAll()
                    return Result<[CalendarEvent], CalendarServiceError>.failure(error)
                }
            }
            return .success(events)
        }
        return try outcome.get()
    }

    private func allPages<Item: Sendable>(
        credential: GoogleCredential,
        request: @Sendable (String?) -> HTTPRequest,
        decode: @Sendable (HTTPResponse) throws(GoogleError) -> Page<Item>
    ) async throws(CalendarServiceError) -> [Item] {
        var items: [Item] = []
        var pageToken: String?
        repeat {
            let response = try await authorizedResponse(to: request(pageToken), credential: credential)
            let page = try google { () throws(GoogleError) in try decode(response) }
            items += page.items
            pageToken = page.nextPageToken
        } while pageToken != nil
        return items
    }

    private func authorizedResponse(to request: HTTPRequest, credential: GoogleCredential) async throws(CalendarServiceError) -> HTTPResponse {
        let token = try await validAccessToken(credential: credential)
        let response = try await transport.send(request.authorized(with: token))
        guard response.status == 401 else { return response }
        let renewed = try await validAccessToken(rejecting: token, credential: credential)
        return try await transport.send(request.authorized(with: renewed))
    }

    private func validAccessToken(rejecting rejected: AccessToken? = nil, credential: GoogleCredential) async throws(CalendarServiceError) -> AccessToken {
        let id = credential.account.id
        if let cached = accessTokens[id], cached != rejected, cached.isFresh(at: .now) {
            return cached
        }
        let sentAt = Date.now
        let response = try await transport.send(GoogleOAuth.refreshRequest(client: client, refreshToken: credential.refreshToken))
        do throws(GoogleError) {
            let token = try GoogleOAuth.accessToken(from: response, receivedAt: sentAt)
            accessTokens[id] = token
            return token
        } catch {
            if error == .invalidGrant {
                accessTokens[id] = nil
            }
            throw CalendarServiceError(error)
        }
    }

    private func google<Value>(_ body: () throws(GoogleError) -> Value) throws(CalendarServiceError) -> Value {
        do {
            return try body()
        } catch {
            throw CalendarServiceError(error)
        }
    }
}

extension CalendarServiceError {
    init(_ error: GoogleError) {
        switch error {
        case .accessDenied:
            self = .cancelled
        case .invalidGrant:
            self = .sessionExpired
        case .stateMismatch, .authorizationFailed, .missingRefreshToken, .missingCalendarScope, .unauthorized, .server, .malformedResponse:
            self = .failed(error.message)
        }
    }
}

extension [GoogleCredential] {
    fileprivate func upserting(_ credential: GoogleCredential) -> [GoogleCredential] {
        guard let index = firstIndex(where: { $0.account.id == credential.account.id }) else { return self + [credential] }
        var updated = self
        updated[index] = credential
        return updated
    }
}
