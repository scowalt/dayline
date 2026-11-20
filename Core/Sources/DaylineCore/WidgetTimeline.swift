import Foundation

public struct DayGlance: Hashable, Sendable {
    public struct Day: Hashable, Sendable {
        public let date: CivilDate
        public let allDay: [CalendarEvent]
        public let timed: [CalendarEvent]
    }

    public let date: CivilDate
    public let inProgress: [CalendarEvent]
    public let upcoming: [CalendarEvent]
    public let finished: [CalendarEvent]
    public let allDay: [CalendarEvent]
    public let nextDay: Day

    public var focus: CalendarEvent? {
        let latestStarted = inProgress.compactMap(TimedEvent.init).max { lhs, rhs in
            (lhs.start, rhs.end) < (rhs.start, lhs.end)
        }
        return latestStarted?.event ?? upcoming.first
    }

    public var remaining: [CalendarEvent] {
        inProgress + upcoming
    }

    public func isInProgress(_ event: CalendarEvent) -> Bool {
        inProgress.contains { $0.id == event.id }
    }
}

public enum WidgetTimeline {
    public static func entryDates(events: [CalendarEvent], now: Date, calendar: Calendar, horizon: TimeInterval) -> [Date] {
        let horizonEnd = now.addingTimeInterval(horizon)
        let boundaries = attended(events).flatMap { event in
            let interval = event.time.interval(in: calendar)
            return [interval.start, interval.end]
        }
        let nextMidnight = CivilDate(now, in: calendar).adding(days: 1, in: calendar).start(in: calendar)
        let inside = boundaries.filter { $0 > now && $0 <= horizonEnd }
        return Set([now, nextMidnight] + inside).sorted()
    }

    public static func glance(events: [CalendarEvent], at now: Date, calendar: Calendar) -> DayGlance {
        let today = CivilDate(now, in: calendar)
        let tomorrow = today.adding(days: 1, in: calendar)
        let todayStart = today.start(in: calendar)
        let tomorrowStart = tomorrow.start(in: calendar)
        let dayAfterStart = tomorrow.adding(days: 1, in: calendar).start(in: calendar)

        let shown = attended(events)
        let timed = shown.compactMap(TimedEvent.init).sorted { $0.chronologicalKey < $1.chronologicalKey }
        let todayTimed = timed.filter { $0.start < tomorrowStart && ($0.start >= todayStart || $0.end > todayStart) }

        return DayGlance(
            date: today,
            inProgress: todayTimed.filter { $0.start <= now && now < $0.end }.map(\.event),
            upcoming: todayTimed.filter { $0.start > now }.map(\.event),
            finished: todayTimed.filter { $0.end <= now }.map(\.event),
            allDay: allDay(shown, covering: today),
            nextDay: DayGlance.Day(
                date: tomorrow,
                allDay: allDay(shown, covering: tomorrow),
                timed: timed.filter { $0.start >= tomorrowStart && $0.start < dayAfterStart }.map(\.event)
            )
        )
    }

    private static func attended(_ events: [CalendarEvent]) -> [CalendarEvent] {
        events.filter { $0.attendance != .declined }
    }

    private static func allDay(_ events: [CalendarEvent], covering date: CivilDate) -> [CalendarEvent] {
        events
            .compactMap { event -> (first: CivilDate, event: CalendarEvent)? in
                guard case .allDay(let first, let last) = event.time, first <= date, date <= last else { return nil }
                return (first, event)
            }
            .sorted { ($0.first, $0.event.title) < ($1.first, $1.event.title) }
            .map(\.event)
    }
}

private struct TimedEvent {
    let event: CalendarEvent
    let start: Date
    let end: Date

    init?(_ event: CalendarEvent) {
        guard case .timed(let start, let end) = event.time else { return nil }
        self.event = event
        self.start = start
        self.end = max(start, end)
    }

    var chronologicalKey: (Date, Date, String, String, String) {
        (start, end, event.title, event.calendarID.rawValue, event.id.event)
    }
}
