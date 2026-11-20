import Foundation

public struct CalendarID: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct EventID: Hashable, Codable, Sendable {
    public let calendar: CalendarID
    public let event: String

    public init(calendar: CalendarID, event: String) {
        self.calendar = calendar
        self.event = event
    }
}

public struct RGBColor: Hashable, Codable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public init?(hex: String) {
        let digits = hex.hasPrefix("#") ? hex.dropFirst() : Substring(hex)
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

public struct CivilDate: Hashable, Comparable, Codable, Sendable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public init(_ date: Date, in calendar: Calendar) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year!, month: parts.month!, day: parts.day!)
    }

    public func start(in calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    public func adding(days: Int, in calendar: Calendar) -> CivilDate {
        CivilDate(calendar.date(byAdding: .day, value: days, to: start(in: calendar))!, in: calendar)
    }

    public static func < (lhs: CivilDate, rhs: CivilDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

public enum EventTime: Hashable, Codable, Sendable {
    case allDay(first: CivilDate, last: CivilDate)
    case timed(start: Date, end: Date)

    public var isAllDay: Bool {
        if case .allDay = self { true } else { false }
    }

    public func interval(in calendar: Calendar) -> DateInterval {
        switch self {
        case .allDay(let first, let last):
            DateInterval(start: first.start(in: calendar), end: last.adding(days: 1, in: calendar).start(in: calendar))
        case .timed(let start, let end):
            DateInterval(start: start, end: max(start, end))
        }
    }
}

public enum Attendance: String, Hashable, Codable, Sendable {
    case accepted
    case tentative
    case declined
    case needsAction
}

public struct CalendarInfo: Identifiable, Hashable, Codable, Sendable {
    public let id: CalendarID
    public var title: String
    public var color: RGBColor
    public var isPrimary: Bool
    public var isSelectedInGoogle: Bool

    public init(id: CalendarID, title: String, color: RGBColor, isPrimary: Bool, isSelectedInGoogle: Bool) {
        self.id = id
        self.title = title
        self.color = color
        self.isPrimary = isPrimary
        self.isSelectedInGoogle = isSelectedInGoogle
    }
}

public struct CalendarEvent: Identifiable, Hashable, Codable, Sendable {
    public let id: EventID
    public var title: String
    public var time: EventTime
    public var location: String?
    public var notes: String?
    public var conferenceURL: URL?
    public var webURL: URL?
    public var color: RGBColor?
    public var attendance: Attendance?
    public var attendeeCount: Int

    public init(
        id: EventID,
        title: String,
        time: EventTime,
        location: String? = nil,
        notes: String? = nil,
        conferenceURL: URL? = nil,
        webURL: URL? = nil,
        color: RGBColor? = nil,
        attendance: Attendance? = nil,
        attendeeCount: Int = 0
    ) {
        self.id = id
        self.title = title
        self.time = time
        self.location = location
        self.notes = notes
        self.conferenceURL = conferenceURL
        self.webURL = webURL
        self.color = color
        self.attendance = attendance
        self.attendeeCount = attendeeCount
    }

    public var calendarID: CalendarID { id.calendar }
}

public struct Account: Hashable, Codable, Sendable {
    public var email: String
    public var name: String?

    public init(email: String, name: String? = nil) {
        self.email = email
        self.name = name
    }
}

extension Account: Identifiable {
    public var id: String { email }
}

public struct AccountSnapshot: Hashable, Codable, Sendable {
    public var account: Account
    public var calendars: [CalendarInfo]
    public var events: [CalendarEvent]

    public init(account: Account, calendars: [CalendarInfo], events: [CalendarEvent]) {
        self.account = account
        self.calendars = calendars
        self.events = events
    }
}

public struct Snapshot: Hashable, Codable, Sendable {
    public var accounts: [AccountSnapshot]
    public var range: DateInterval
    public var fetchedAt: Date

    public init(accounts: [AccountSnapshot], range: DateInterval, fetchedAt: Date) {
        self.accounts = accounts
        self.range = range
        self.fetchedAt = fetchedAt
    }

    public var calendars: [CalendarInfo] {
        owned.flatMap(\.calendars)
    }

    public var events: [CalendarEvent] {
        owned.flatMap { entry in
            let ids = Set(entry.calendars.map(\.id))
            return entry.account.events.filter { ids.contains($0.calendarID) }
        }
    }

    public func calendars(of account: Account.ID) -> [CalendarInfo] {
        owned.first { $0.account.account.id == account }?.calendars ?? []
    }

    public func calendar(_ id: CalendarID) -> CalendarInfo? {
        calendars.first { $0.id == id }
    }

    public func events(visibleWith visibility: CalendarVisibility) -> [CalendarEvent] {
        let visible = Set(calendars.filter(visibility.isVisible).map(\.id))
        return events.filter { visible.contains($0.calendarID) && !visibility.hides(title: $0.title) }
    }

    public func removing(_ account: Account.ID) -> Snapshot {
        Snapshot(accounts: accounts.filter { $0.account.id != account }, range: range, fetchedAt: fetchedAt)
    }

    private var owned: [(account: AccountSnapshot, calendars: [CalendarInfo])] {
        var claimed = Set<CalendarID>()
        return accounts.map { account in
            (account, account.calendars.filter { claimed.insert($0.id).inserted })
        }
    }
}

public struct CalendarVisibility: Hashable, Codable, Sendable {
    public var overrides: [CalendarID: Bool]
    public private(set) var hiddenTitles: [String]

    public init(overrides: [CalendarID: Bool] = [:], hiddenTitles: [String] = []) {
        self.overrides = overrides
        self.hiddenTitles = []
        hiddenTitles.forEach { hide(title: $0) }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            overrides: try container.decodeIfPresent([CalendarID: Bool].self, forKey: .overrides) ?? [:],
            hiddenTitles: try container.decodeIfPresent([String].self, forKey: .hiddenTitles) ?? []
        )
    }

    public func isVisible(_ calendar: CalendarInfo) -> Bool {
        overrides[calendar.id] ?? calendar.isSelectedInGoogle
    }

    public func hides(title: String) -> Bool {
        let key = Self.matchKey(title)
        return hiddenTitles.contains { Self.matchKey($0) == key }
    }

    public mutating func hide(title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !hides(title: trimmed) else { return }
        hiddenTitles.append(trimmed)
    }

    public mutating func show(title: String) {
        let key = Self.matchKey(title)
        hiddenTitles.removeAll { Self.matchKey($0) == key }
    }

    private static func matchKey(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }
}
