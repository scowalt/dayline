import Foundation

public enum Change: Hashable, Codable, Sendable {
    case move(EventID, to: EventTime)
    case delete(Deletion)
}

public struct PendingChange: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let account: Account.ID
    public let change: Change
    public let notifyGuests: Bool
    public let eventTitle: String
    public let queuedAt: Date

    public init(id: UUID = UUID(), account: Account.ID, change: Change, notifyGuests: Bool, eventTitle: String, queuedAt: Date = .now) {
        self.id = id
        self.account = account
        self.change = change
        self.notifyGuests = notifyGuests
        self.eventTitle = eventTitle
        self.queuedAt = queuedAt
    }
}

public struct Outbox: Hashable, Codable, Sendable {
    public private(set) var changes: [PendingChange]

    public init() {
        changes = []
    }

    public var isEmpty: Bool { changes.isEmpty }

    @discardableResult
    public mutating func enqueue(_ pending: PendingChange) -> [PendingChange] {
        var replaced: [PendingChange] = []
        if case .move(let event, _) = pending.change {
            let isEarlierMove = { (existing: PendingChange) in
                if case .move(event, _) = existing.change { true } else { false }
            }
            replaced = changes.filter(isEarlierMove)
            changes.removeAll(where: isEarlierMove)
        }
        changes.append(pending)
        return replaced
    }

    public mutating func remove(_ id: PendingChange.ID) {
        changes.removeAll { $0.id == id }
    }

    @discardableResult
    public mutating func removeAll(for account: Account.ID) -> [PendingChange] {
        let removed = changes.filter { $0.account == account }
        changes.removeAll { $0.account == account }
        return removed
    }

    public func next(excluding blocked: Set<Account.ID>) -> PendingChange? {
        changes.first { !blocked.contains($0.account) }
    }
}

public enum SendOutcome<Failure: Error>: Sendable {
    case sent
    case retryLater
    case accountBlocked
    case rejected(Failure)
}

extension Snapshot {
    public func applying(_ change: Change) -> Snapshot {
        switch change {
        case .move(let event, let time):
            rescheduling(event, to: time)
        case .delete(let deletion):
            deleting(deletion)
        }
    }

    public func applying(_ outbox: Outbox) -> Snapshot {
        outbox.changes.reduce(self) { $0.applying($1.change) }
    }
}
