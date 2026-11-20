import AuthenticationServices
import DaylineCore
import Foundation

public actor LiveCalendarService: CalendarService {
    private let writer: SnapshotStore.Writer
    private let client = GoogleClient.dayline
    private let transport = HTTPTransport()
    private let vault = KeychainVault()
    private var accessToken: AccessToken?

    public init(writer: SnapshotStore.Writer) {
        self.writer = writer
    }

    public func restore() async -> Session? {
        guard let credential = vault.read() else { return nil }
        return Session(account: credential.account, snapshot: SnapshotStore.shared?.latest())
    }

    public func signIn(authorize: WebAuthorizer) async throws(CalendarServiceError) -> Session {
        guard let client else { throw .notConfigured }
        let pkce = PKCE.random()
        let state = randomURLSafeString(byteCount: 16)
        let callback: URL
        do {
            callback = try await authorize(GoogleOAuth.authorizationURL(client: client, pkce: pkce, state: state), client.callbackScheme)
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
            try vault.save(grant.credential)
        }
        accessToken = grant.accessToken
        SnapshotStore.shared?.clear()
        let snapshot = try? await fetchSnapshot(for: grant.credential, client: client)
        return Session(account: grant.credential.account, snapshot: snapshot)
    }

    public func refresh() async throws(CalendarServiceError) -> Snapshot {
        guard let client else { throw .notConfigured }
        guard let credential = vault.read() else { throw .sessionExpired }
        return try await fetchSnapshot(for: credential, client: client)
    }

    public func signOut() async {
        let credential = vault.read()
        accessToken = nil
        if writer == .app {
            vault.delete()
        }
        SnapshotStore.shared?.clear()
        guard let credential else { return }
        let transport = transport
        await withTaskGroup(of: Void.self) { group in
            group.addTask { _ = try? await transport.send(GoogleOAuth.revokeRequest(credential.refreshToken)) }
            group.addTask { try? await Task.sleep(for: .seconds(5)) }
            await group.next()
            group.cancelAll()
        }
    }

    public func refreshIfStale(maxAge: Duration) async -> Snapshot? {
        guard let credential = vault.read() else { return nil }
        let stored = SnapshotStore.shared?.latest()
        if let stored, Duration.seconds(Date.now.timeIntervalSince(stored.fetchedAt)) < maxAge {
            return stored
        }
        guard let client else { return stored }
        do {
            return try await fetchSnapshot(for: credential, client: client)
        } catch {
            return stored
        }
    }

    private func fetchSnapshot(for credential: GoogleCredential, client: GoogleClient) async throws(CalendarServiceError) -> Snapshot {
        let now = Date.now
        let window = GoogleCalendarAPI.window(containing: now, in: .current)
        let calendars = try await allPages(credential: credential, client: client, request: GoogleCalendarAPI.calendarListRequest, decode: GoogleCalendarAPI.calendarListPage)
        let visibility = CalendarPreferences().visibility
        let events = try await events(in: calendars.filter(visibility.isVisible).map(\.id), window: window, credential: credential, client: client)
        let snapshot = Snapshot(account: credential.account, calendars: calendars, events: events, range: window, fetchedAt: now)
        try? SnapshotStore.shared?.save(snapshot, as: writer)
        return snapshot
    }

    private func events(in calendars: [CalendarID], window: DateInterval, credential: GoogleCredential, client: GoogleClient) async throws(CalendarServiceError) -> [CalendarEvent] {
        let outcome = await withTaskGroup(of: Result<[CalendarEvent], CalendarServiceError>.self) { group in
            for calendar in calendars {
                group.addTask {
                    do throws(CalendarServiceError) {
                        return .success(try await self.allPages(
                            credential: credential,
                            client: client,
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
        client: GoogleClient,
        request: @Sendable (String?) -> HTTPRequest,
        decode: @Sendable (HTTPResponse) throws(GoogleError) -> Page<Item>
    ) async throws(CalendarServiceError) -> [Item] {
        var items: [Item] = []
        var pageToken: String?
        repeat {
            let response = try await authorizedResponse(to: request(pageToken), credential: credential, client: client)
            let page = try google { () throws(GoogleError) in try decode(response) }
            items += page.items
            pageToken = page.nextPageToken
        } while pageToken != nil
        return items
    }

    private func authorizedResponse(to request: HTTPRequest, credential: GoogleCredential, client: GoogleClient) async throws(CalendarServiceError) -> HTTPResponse {
        let token = try await validAccessToken(credential: credential, client: client)
        let response = try await transport.send(request.authorized(with: token))
        guard response.status == 401 else { return response }
        let renewed = try await validAccessToken(rejecting: token, credential: credential, client: client)
        return try await transport.send(request.authorized(with: renewed))
    }

    private func validAccessToken(rejecting rejected: AccessToken? = nil, credential: GoogleCredential, client: GoogleClient) async throws(CalendarServiceError) -> AccessToken {
        if let accessToken, accessToken != rejected, accessToken.isFresh(at: .now) {
            return accessToken
        }
        let sentAt = Date.now
        let response = try await transport.send(GoogleOAuth.refreshRequest(client: client, refreshToken: credential.refreshToken))
        do throws(GoogleError) {
            let token = try GoogleOAuth.accessToken(from: response, receivedAt: sentAt)
            accessToken = token
            return token
        } catch {
            if error == .invalidGrant {
                accessToken = nil
                if writer == .app {
                    vault.delete()
                }
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
