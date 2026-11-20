import DaylineCore
import Foundation

public actor DemoCalendarService: CalendarService {
    private let store: SnapshotStore?
    private var signedOut: [Account.ID] = []

    public init(store: SnapshotStore? = .shared) {
        self.store = store
    }

    public func restore() async -> Session? {
        makeSession()
    }

    public func signIn(authorize: WebAuthorizer, loginHint: String?) async throws(CalendarServiceError) -> Session {
        signedOut = []
        return makeSession()!
    }

    public func refresh() async throws(CalendarServiceError) -> Session {
        guard let session = makeSession() else { throw .sessionExpired }
        return session
    }

    public func signOut(_ account: Account.ID) async -> Session? {
        signedOut.append(account)
        let session = makeSession()
        if session == nil {
            store?.clear()
        }
        return session
    }

    private func makeSession() -> Session? {
        let snapshot = signedOut.reduce(Snapshot.sample(now: .now, calendar: .current)) { $0.removing($1) }
        guard !snapshot.accounts.isEmpty else { return nil }
        try? store?.save(snapshot, as: .app)
        return Session(accounts: snapshot.accounts.map(\.account), snapshot: snapshot)
    }
}
