import DaylineCore
import Foundation

public actor LiveCalendarService: CalendarService {
    private let writer: SnapshotStore.Writer

    public init(writer: SnapshotStore.Writer) {
        self.writer = writer
    }

    public func restore() async -> Session? {
        nil
    }

    public func signIn(authorize: WebAuthorizer) async throws(CalendarServiceError) -> Session {
        throw .notConfigured
    }

    public func refresh() async throws(CalendarServiceError) -> Snapshot {
        throw .sessionExpired
    }

    public func signOut() async {}

    public func refreshIfStale(maxAge: Duration) async -> Snapshot? {
        SnapshotStore.shared?.latest()
    }
}
