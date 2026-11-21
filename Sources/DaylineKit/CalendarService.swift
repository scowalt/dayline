import DaylineCore
import Foundation

public struct Session: Hashable, Sendable {
    public var accounts: [Account]
    public var snapshot: Snapshot?
    public var issues: [Account.ID: CalendarServiceError]

    public init(accounts: [Account], snapshot: Snapshot?, issues: [Account.ID: CalendarServiceError] = [:]) {
        self.accounts = accounts
        self.snapshot = snapshot
        self.issues = issues
    }
}

public enum CalendarServiceError: Error, Hashable, Sendable {
    case cancelled
    case sessionExpired
    case offline
    case missingEditPermission
    case failed(String)
}

public typealias WebAuthorizer = @MainActor @Sendable (_ url: URL, _ callbackScheme: String) async throws -> URL

public protocol CalendarService: Sendable {
    func restore() async -> Session?
    func signIn(authorize: WebAuthorizer, loginHint: String?) async throws(CalendarServiceError) -> Session
    func refresh() async throws(CalendarServiceError) -> Session
    func signOut(_ account: Account.ID) async -> Session?
    func reschedule(_ event: EventID, of account: Account.ID, to time: EventTime, notifyGuests: Bool) async throws(CalendarServiceError)
    func delete(_ deletion: Deletion, of account: Account.ID, notifyGuests: Bool) async throws(CalendarServiceError)
}
