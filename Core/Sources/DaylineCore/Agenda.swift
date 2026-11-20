import Foundation

public struct AgendaDay: Identifiable, Hashable, Sendable {
    public let date: CivilDate
    public var allDay: [CalendarEvent]
    public var timed: [CalendarEvent]

    public init(date: CivilDate, allDay: [CalendarEvent] = [], timed: [CalendarEvent] = []) {
        self.date = date
        self.allDay = allDay
        self.timed = timed
    }

    public var id: CivilDate { date }

    public var isEmpty: Bool { allDay.isEmpty && timed.isEmpty }

    public func startedCount(at now: Date, calendar: Calendar) -> Int {
        timed.prefix { $0.time.interval(in: calendar).start <= now }.count
    }
}

public enum Agenda {
    public static func days(events: [CalendarEvent], from first: CivilDate, through last: CivilDate, calendar: Calendar) -> [AgendaDay] {
        guard first <= last else { return [] }
        var allDay: [CivilDate: [CalendarEvent]] = [:]
        var timed: [CivilDate: [CalendarEvent]] = [:]
        for event in events {
            let covered = event.time.days(in: calendar)
            for date in dates(from: max(covered.lowerBound, first), through: min(covered.upperBound, last), calendar: calendar) {
                if event.time.isAllDay {
                    allDay[date, default: []].append(event)
                } else {
                    timed[date, default: []].append(event)
                }
            }
        }
        return dates(from: first, through: last, calendar: calendar).map { date in
            AgendaDay(
                date: date,
                allDay: (allDay[date] ?? []).sorted { allDayOrder($0, $1, calendar: calendar) },
                timed: (timed[date] ?? []).sorted { timedOrder($0, $1, calendar: calendar) }
            )
        }
    }

    private static func dates(from first: CivilDate, through last: CivilDate, calendar: Calendar) -> [CivilDate] {
        var dates: [CivilDate] = []
        var date = first
        while date <= last {
            dates.append(date)
            date = date.adding(days: 1, in: calendar)
        }
        return dates
    }

    private static func timedOrder(_ lhs: CalendarEvent, _ rhs: CalendarEvent, calendar: Calendar) -> Bool {
        let left = lhs.time.interval(in: calendar)
        let right = rhs.time.interval(in: calendar)
        if left.start != right.start { return left.start < right.start }
        if left.end != right.end { return left.end < right.end }
        return titleOrder(lhs, rhs)
    }

    private static func allDayOrder(_ lhs: CalendarEvent, _ rhs: CalendarEvent, calendar: Calendar) -> Bool {
        let left = lhs.time.days(in: calendar)
        let right = rhs.time.days(in: calendar)
        if left.lowerBound != right.lowerBound { return left.lowerBound < right.lowerBound }
        if left.upperBound != right.upperBound { return left.upperBound > right.upperBound }
        return titleOrder(lhs, rhs)
    }

    private static func titleOrder(_ lhs: CalendarEvent, _ rhs: CalendarEvent) -> Bool {
        let order = lhs.title.localizedStandardCompare(rhs.title)
        if order != .orderedSame { return order == .orderedAscending }
        return (lhs.id.calendar.rawValue, lhs.id.event) < (rhs.id.calendar.rawValue, rhs.id.event)
    }
}

public enum DayPortion: Hashable, Sendable {
    case allDay(day: Int, of: Int)
    case within(start: Date, end: Date)
    case startsThisDay(start: Date, end: Date)
    case endsThisDay(end: Date)
    case coversThisDay
}

extension EventTime {
    public func days(in calendar: Calendar) -> ClosedRange<CivilDate> {
        switch self {
        case .allDay(let first, let last):
            return first...max(first, last)
        case .timed(let start, let end):
            let first = CivilDate(start, in: calendar)
            let endDay = CivilDate(end, in: calendar)
            let endsAtMidnight = end > start && endDay.start(in: calendar) == end
            return first...max(first, endsAtMidnight ? endDay.adding(days: -1, in: calendar) : endDay)
        }
    }

    public func portion(on day: CivilDate, in calendar: Calendar) -> DayPortion {
        switch self {
        case .allDay:
            let covered = days(in: calendar)
            let count = calendar.days(from: covered.lowerBound, to: covered.upperBound) + 1
            let index = calendar.days(from: covered.lowerBound, to: day) + 1
            return .allDay(day: min(max(index, 1), count), of: count)
        case .timed(let start, let end):
            let dayStart = day.start(in: calendar)
            let dayEnd = day.adding(days: 1, in: calendar).start(in: calendar)
            if start <= dayStart && end >= dayEnd { return .coversThisDay }
            if start < dayStart { return .endsThisDay(end: end) }
            if end > dayEnd { return .startsThisDay(start: start, end: end) }
            return .within(start: start, end: max(start, end))
        }
    }
}

extension CalendarEvent {
    public static let joinLeadTime: TimeInterval = 10 * 60

    public func isJoinable(at now: Date, calendar: Calendar) -> Bool {
        guard conferenceURL != nil else { return false }
        let interval = time.interval(in: calendar)
        return now >= interval.start.addingTimeInterval(-Self.joinLeadTime) && now < interval.end
    }

    public func hasEnded(at now: Date, calendar: Calendar) -> Bool {
        time.interval(in: calendar).end <= now
    }
}

extension Calendar {
    fileprivate func days(from first: CivilDate, to last: CivilDate) -> Int {
        dateComponents([.day], from: first.start(in: self), to: last.start(in: self)).day ?? 0
    }
}
