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

public enum OccurrenceStart: Hashable, Comparable, Codable, Sendable {
    case day(CivilDate)
    case moment(Date)
}

public struct Occurrence: Hashable, Codable, Sendable {
    public let series: EventID
    public let originalStart: OccurrenceStart

    public init(series: EventID, originalStart: OccurrenceStart) {
        self.series = series
        self.originalStart = originalStart
    }
}

public enum DeletionScope: Hashable, Sendable {
    case thisEvent
    case thisAndFollowing
    case allEvents
}

public enum Deletion: Hashable, Sendable {
    case event(EventID)
    case series(EventID)
    case following(series: EventID, from: OccurrenceStart)

    public func removes(_ event: CalendarEvent) -> Bool {
        switch self {
        case .event(let id):
            event.id == id
        case .series(let series):
            event.occurrence?.series == series
        case .following(let series, let start):
            event.occurrence.map { $0.series == series && $0.originalStart >= start } ?? false
        }
    }
}

public enum Attendance: String, Hashable, Codable, Sendable {
    case accepted
    case tentative
    case declined
    case needsAction
}

public enum CalendarAccess: String, Comparable, Codable, Sendable {
    case freeBusyReader
    case reader
    case writer
    case owner

    private var rank: Int {
        switch self {
        case .freeBusyReader: 0
        case .reader: 1
        case .writer: 2
        case .owner: 3
        }
    }

    public static func < (lhs: CalendarAccess, rhs: CalendarAccess) -> Bool {
        lhs.rank < rhs.rank
    }
}

public struct CalendarInfo: Identifiable, Hashable, Codable, Sendable {
    public let id: CalendarID
    public var title: String
    public var color: RGBColor
    public var isPrimary: Bool
    public var isSelectedInGoogle: Bool
    public var access: CalendarAccess

    public init(id: CalendarID, title: String, color: RGBColor, isPrimary: Bool, isSelectedInGoogle: Bool, access: CalendarAccess = .reader) {
        self.id = id
        self.title = title
        self.color = color
        self.isPrimary = isPrimary
        self.isSelectedInGoogle = isSelectedInGoogle
        self.access = access
    }

    public var canEditEvents: Bool { access >= .writer }
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
    public var canReschedule: Bool
    public var occurrence: Occurrence?
    public var isOrganizer: Bool
    public var canDelete: Bool

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
        attendeeCount: Int = 0,
        canReschedule: Bool = false,
        occurrence: Occurrence? = nil,
        isOrganizer: Bool = false,
        canDelete: Bool = false
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
        self.canReschedule = canReschedule
        self.occurrence = occurrence
        self.isOrganizer = isOrganizer
        self.canDelete = canDelete
    }

    public var calendarID: CalendarID { id.calendar }

    public var deletionScopes: [DeletionScope] {
        guard canDelete else { return [] }
        guard occurrence != nil else { return [.thisEvent] }
        return canReschedule ? [.thisEvent, .thisAndFollowing, .allEvents] : [.thisEvent, .allEvents]
    }

    public func deletion(_ scope: DeletionScope) -> Deletion {
        switch (scope, occurrence) {
        case (.thisEvent, _), (_, nil):
            .event(id)
        case (.thisAndFollowing, let occurrence?):
            .following(series: occurrence.series, from: occurrence.originalStart)
        case (.allEvents, let occurrence?):
            .series(occurrence.series)
        }
    }
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

    public func account(owning calendar: CalendarID) -> Account? {
        owned.first { $0.calendars.contains { $0.id == calendar } }?.account.account
    }

    public func rescheduling(_ event: EventID, to time: EventTime) -> Snapshot {
        var snapshot = self
        for index in snapshot.accounts.indices {
            for eventIndex in snapshot.accounts[index].events.indices where snapshot.accounts[index].events[eventIndex].id == event {
                snapshot.accounts[index].events[eventIndex].time = time
            }
        }
        return snapshot
    }

    public func deleting(_ deletion: Deletion) -> Snapshot {
        var snapshot = self
        for index in snapshot.accounts.indices {
            snapshot.accounts[index].events.removeAll(where: deletion.removes)
        }
        return snapshot
    }

    public func events(visibleWith visibility: CalendarVisibility) -> [CalendarEvent] {
        let visible = Set(calendars.filter(visibility.isVisible).map(\.id))
        return events.filter { visible.contains($0.calendarID) && !visibility.hides(title: $0.title) }
    }

    public func removing(_ account: Account.ID) -> Snapshot {
        Snapshot(accounts: accounts.filter { $0.account.id != account }, range: range, fetchedAt: fetchedAt)
    }

    private var owned: [(account: AccountSnapshot, calendars: [CalendarInfo])] {
        var owners: [CalendarID: (account: Int, access: CalendarAccess)] = [:]
        for (index, account) in accounts.enumerated() {
            for calendar in account.calendars where owners[calendar.id].map({ calendar.access > $0.access }) ?? true {
                owners[calendar.id] = (index, calendar.access)
            }
        }
        return accounts.enumerated().map { index, account in
            (account, account.calendars.filter { owners[$0.id]?.account == index })
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
