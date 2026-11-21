import DaylineCore
import Foundation

public actor DemoCalendarService: CalendarService {
    private let store: SnapshotStore?
    private let isOffline: Bool
    private var signedOut: [Account.ID] = []
    private var rescheduled: [EventID: EventTime] = [:]
    private var deletions: [Deletion] = []

    public init(store: SnapshotStore? = .shared, isOffline: Bool = false) {
        self.store = store
        self.isOffline = isOffline
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

    public func send(_ pending: PendingChange) async throws(CalendarServiceError) {
        try? await Task.sleep(for: .milliseconds(400))
        if isOffline { throw .offline }
        switch pending.change {
        case .move(let event, let time):
            rescheduled[event] = time
        case .delete(let deletion):
            deletions.append(deletion)
        }
        _ = makeSession()
    }

    private func makeSession() -> Session? {
        let moved = rescheduled.reduce(Snapshot.sample(now: .now, calendar: .current)) { $0.rescheduling($1.key, to: $1.value) }
        let sample = deletions.reduce(moved) { $0.deleting($1) }
        let snapshot = signedOut.reduce(sample) { $0.removing($1) }
        guard !snapshot.accounts.isEmpty else { return nil }
        try? store?.save(snapshot, as: .app)
        return Session(accounts: snapshot.accounts.map(\.account), snapshot: snapshot)
    }
}
