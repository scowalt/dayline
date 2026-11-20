import DaylineCore
import Foundation

public struct DemoCalendarService: CalendarService {
    private let store: SnapshotStore?

    public init(store: SnapshotStore? = .shared) {
        self.store = store
    }

    public func restore() async -> Session? {
        let snapshot = makeSnapshot()
        return Session(account: snapshot.account, snapshot: snapshot)
    }

    public func signIn(authorize: WebAuthorizer) async throws(CalendarServiceError) -> Session {
        let snapshot = makeSnapshot()
        return Session(account: snapshot.account, snapshot: snapshot)
    }

    public func refresh() async throws(CalendarServiceError) -> Snapshot {
        makeSnapshot()
    }

    public func signOut() async {
        store?.clear()
    }

    private func makeSnapshot() -> Snapshot {
        let snapshot = Snapshot.sample(now: .now, calendar: .current)
        try? store?.save(snapshot, as: .app)
        return snapshot
    }
}
