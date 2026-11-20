import DaylineCore
import Foundation

public struct Session: Hashable, Sendable {
    public var account: Account
    public var snapshot: Snapshot?

    public init(account: Account, snapshot: Snapshot?) {
        self.account = account
        self.snapshot = snapshot
    }
}

public enum CalendarServiceError: Error, Hashable, Sendable {
    case cancelled
    case sessionExpired
    case offline
    case failed(String)
}

public typealias WebAuthorizer = @MainActor @Sendable (_ url: URL, _ callbackScheme: String) async throws -> URL

public protocol CalendarService: Sendable {
    func restore() async -> Session?
    func signIn(authorize: WebAuthorizer) async throws(CalendarServiceError) -> Session
    func refresh() async throws(CalendarServiceError) -> Snapshot
    func signOut() async
}
