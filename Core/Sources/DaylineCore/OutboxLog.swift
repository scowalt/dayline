import Foundation

extension Change {
    public var label: String {
        switch self {
        case .move: "move"
        case .delete(.event): "delete event"
        case .delete(.series): "delete series"
        case .delete(.following): "delete this and following"
        }
    }

    public var eventID: EventID {
        switch self {
        case .move(let id, _), .delete(.event(let id)), .delete(.series(let id)), .delete(.following(let id, _)):
            id
        }
    }

    var subject: String {
        "\(label) \(eventID.calendar.rawValue)/\(eventID.event)"
    }
}

public enum OutboxLog {
    public static let backgroundStarted = "background drain started"

    public static func queued(_ pending: PendingChange, replacing replaced: [PendingChange]) -> String {
        var message = "\(pending.change.subject): queued"
        if !replaced.isEmpty {
            let times = replaced.map { $0.queuedAt.formatted(.iso8601) }.joined(separator: ", ")
            message += ", replacing \(replaced.count == 1 ? "1 earlier queued move" : "\(replaced.count) earlier queued moves") (queued \(times))"
        }
        return message
    }

    public static func result<Failure: Error>(
        of pending: PendingChange,
        outcome: SendOutcome<Failure>,
        error: String?,
        stillQueued: Bool,
        now: Date
    ) -> String {
        let phrase = phrase(for: outcome, error: error, waited: now.timeIntervalSince(pending.queuedAt))
        if stillQueued {
            return "\(pending.change.subject): \(phrase)"
        }
        return "\(pending.change.subject): send finished after the change was replaced or removed, ignored outcome: \(phrase)"
    }

    public static func removedOnSignOut(_ removed: [PendingChange]) -> String {
        "removed \(removed.count) queued changes because the account signed out: \(removed.map(\.change.subject).joined(separator: ", "))"
    }

    public static func unreadable(error: String, movedTo: String?) -> String {
        let fate = movedTo.map { "moved it to \($0)" } ?? "could not move it aside"
        return "error: the queued changes file is unreadable (\(error)), \(fate) and started with an empty queue"
    }

    public static func saveFailed(count: Int, error: String) -> String {
        "error: could not save \(count) queued changes (\(error)), they are kept in memory only"
    }

    public static func backgroundFinished(sent: Int, queued: Int) -> String {
        "background drain finished: \(sent) sent, \(queued) still queued"
    }

    static func age(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval))
        switch seconds {
        case ..<60: return "\(seconds) s"
        case ..<3600: return "\(seconds / 60) min"
        case ..<86_400: return "\(seconds / 3600) h \(seconds % 3600 / 60) min"
        default: return "\(seconds / 86_400) d \(seconds % 86_400 / 3600) h"
        }
    }

    private static func phrase<Failure: Error>(for outcome: SendOutcome<Failure>, error: String?, waited: TimeInterval) -> String {
        let reason = error.map { ": \($0)" } ?? ""
        return switch outcome {
        case .sent: "sent after waiting \(age(waited))"
        case .retryLater: "kept for retry\(reason)"
        case .accountBlocked: "held until sign-in\(reason)"
        case .rejected: "dropped, Google refused it\(reason)"
        }
    }
}
