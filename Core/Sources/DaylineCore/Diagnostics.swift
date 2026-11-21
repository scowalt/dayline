import Foundation

public struct SyncLogEntry: Hashable, Codable, Sendable {
    public var at: Date
    public var source: String
    public var account: String?
    public var message: String

    public init(at: Date, source: String, account: String?, message: String) {
        self.at = at
        self.source = source
        self.account = account
        self.message = message
    }
}

public enum Diagnostics {
    public static func line(for request: HTTPRequest, response: HTTPResponse, elapsed: Duration) -> String {
        var line = "\(request.method.rawValue) \(request.url.path(percentEncoded: false)) → \(response.status) \(milliseconds(elapsed))"
        if !response.isSuccess, let message = errorMessage(in: response.body) {
            line += ": \(message)"
        }
        return line
    }

    public static func line(for request: HTTPRequest, failure: String, elapsed: Duration) -> String {
        "\(request.method.rawValue) \(request.url.path(percentEncoded: false)) failed \(milliseconds(elapsed)): \(failure)"
    }

    public static func report(
        version: String,
        now: Date,
        timeZone: TimeZone,
        accounts: [Account],
        issues: [Account.ID: String],
        snapshot: Snapshot?,
        outbox: Outbox,
        visibility: CalendarVisibility,
        log: [SyncLogEntry]
    ) -> String {
        var lines = [
            "Dayline \(version) diagnostics",
            "Generated \(now.formatted(.iso8601)) in \(timeZone.identifier)",
        ]
        if let snapshot {
            lines.append("Snapshot fetched \(snapshot.fetchedAt.formatted(.iso8601)), covering \(snapshot.range.start.formatted(.iso8601)) to \(snapshot.range.end.formatted(.iso8601))")
        } else {
            lines.append("No snapshot")
        }
        for (index, account) in accounts.enumerated() {
            lines.append("")
            lines.append("Account \(index + 1): \(account.email)")
            lines.append("  Issue: \(issues[account.id] ?? "none")")
            guard let snapshot, let stored = snapshot.accounts.first(where: { $0.account.id == account.id }) else {
                lines.append("  Not in snapshot")
                continue
            }
            lines.append("  \(stored.calendars.count) calendars, \(stored.events.count) events")
            for calendar in stored.calendars {
                lines.append("  - \(describe(calendar, of: stored, in: snapshot, visibility: visibility))")
            }
        }
        if !visibility.hiddenTitles.isEmpty {
            let hidden = snapshot?.events.filter { visibility.hides(title: $0.title) }.count ?? 0
            lines.append("")
            lines.append("\(visibility.hiddenTitles.count) hidden titles match \(hidden) events")
        }
        lines.append("")
        if outbox.isEmpty {
            lines.append("Queued changes: none")
        } else {
            lines.append("Queued changes: \(outbox.changes.count)")
            for pending in outbox.changes {
                let age = OutboxLog.age(now.timeIntervalSince(pending.queuedAt))
                lines.append("  - \(pending.change.subject), account \(pending.account), queued \(pending.queuedAt.formatted(.iso8601)) (\(age) ago), notify guests \(pending.notifyGuests ? "yes" : "no")")
            }
        }
        lines.append("")
        lines.append("Sync log, oldest first")
        for entry in log.sorted(by: { $0.at < $1.at }) {
            lines.append("\(entry.at.formatted(.iso8601)) \(entry.source) \(entry.account ?? "-") \(entry.message)")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func describe(_ calendar: CalendarInfo, of account: AccountSnapshot, in snapshot: Snapshot, visibility: CalendarVisibility) -> String {
        let events = account.events.filter { $0.calendarID == calendar.id }
        let untitled = events.filter { $0.title == GoogleCalendarAPI.untitledEvent }.count
        let owner = snapshot.account(owning: calendar.id)
        var flags = [calendar.access.rawValue]
        if calendar.isPrimary { flags.append("primary") }
        flags.append(calendar.isSelectedInGoogle ? "selected in Google" : "not selected in Google")
        if let override = visibility.overrides[calendar.id] {
            flags.append(override ? "shown in Dayline" : "hidden in Dayline")
        }
        if let owner, owner.id != account.account.id {
            flags.append("listed under \(owner.email)")
        }
        return "\(calendar.title) <\(calendar.id.rawValue)> [\(flags.joined(separator: ", "))]: \(events.count) events, \(untitled) untitled"
    }

    private static func milliseconds(_ duration: Duration) -> String {
        let (seconds, attoseconds) = duration.components
        return "in \(seconds * 1000 + attoseconds / 1_000_000_000_000_000) ms"
    }

    private static func errorMessage(in body: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return String(data: body.prefix(200), encoding: .utf8).flatMap { $0.isEmpty ? nil : $0 }
        }
        if let error = json["error"] as? [String: Any] {
            let reasons = (error["errors"] as? [[String: Any]])?.compactMap { $0["reason"] as? String } ?? []
            let message = error["message"] as? String ?? "no message"
            return reasons.isEmpty ? message : "\(message) (\(reasons.joined(separator: ", ")))"
        }
        if let error = json["error"] as? String {
            return [error, json["error_description"] as? String].compactMap { $0 }.joined(separator: ": ")
        }
        return nil
    }
}
