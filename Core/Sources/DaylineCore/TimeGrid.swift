import Foundation

public struct TimeGridPlacement: Hashable, Sendable {
    public let event: CalendarEvent
    public let startMinute: Double
    public let endMinute: Double
    public let column: Int
    public let columnCount: Int
}

public enum TimeGrid {
    public static let minutesPerDay = 24 * 60
    public static let snapMinutes = 15

    public static func placements(of events: [CalendarEvent], on day: CivilDate, calendar: Calendar, minimumMinutes: Double = 15) -> [TimeGridPlacement] {
        let spans = events
            .compactMap { event -> (event: CalendarEvent, start: Double, end: Double)? in
                guard case .timed(let start, let end) = event.time, event.time.days(in: calendar).contains(day) else { return nil }
                let first = max(0, minute(of: start, from: day, calendar: calendar))
                let last = min(Double(minutesPerDay), minute(of: end, from: day, calendar: calendar))
                return (event, first, max(last, first))
            }
            .sorted { lhs, rhs in
                if lhs.start != rhs.start { return lhs.start < rhs.start }
                if lhs.end != rhs.end { return lhs.end > rhs.end }
                return (lhs.event.id.calendar.rawValue, lhs.event.id.event) < (rhs.event.id.calendar.rawValue, rhs.event.id.event)
            }

        var placements: [TimeGridPlacement] = []
        var cluster: [(span: (event: CalendarEvent, start: Double, end: Double), column: Int)] = []
        var columnEnds: [Double] = []
        var clusterEnd = -Double.infinity

        func closeCluster() {
            placements += cluster.map { entry in
                TimeGridPlacement(event: entry.span.event, startMinute: entry.span.start, endMinute: entry.span.end, column: entry.column, columnCount: columnEnds.count)
            }
            cluster = []
            columnEnds = []
        }

        for span in spans {
            let shownEnd = max(span.end, span.start + minimumMinutes)
            if span.start >= clusterEnd {
                closeCluster()
            }
            let column = columnEnds.firstIndex { $0 <= span.start } ?? columnEnds.count
            if column == columnEnds.count {
                columnEnds.append(shownEnd)
            } else {
                columnEnds[column] = shownEnd
            }
            cluster.append((span, column))
            clusterEnd = max(clusterEnd, shownEnd)
        }
        closeCluster()
        return placements
    }

    public static func minute(of date: Date, from day: CivilDate, calendar: Calendar) -> Double {
        let dayOffset = calendar.dateComponents([.day], from: day.start(in: calendar), to: CivilDate(date, in: calendar).start(in: calendar)).day ?? 0
        let clock = calendar.dateComponents([.hour, .minute, .second], from: date)
        return Double(dayOffset * minutesPerDay + (clock.hour ?? 0) * 60 + (clock.minute ?? 0)) + Double(clock.second ?? 0) / 60
    }

    public static func snappedDate(atMinute minute: Double, from day: CivilDate, calendar: Calendar) -> Date {
        let snapped = Int((minute / Double(snapMinutes)).rounded()) * snapMinutes
        let dayOffset = Int((Double(snapped) / Double(minutesPerDay)).rounded(.down))
        let clock = snapped - dayOffset * minutesPerDay
        let target = day.adding(days: dayOffset, in: calendar)
        return calendar.date(from: DateComponents(year: target.year, month: target.month, day: target.day, hour: clock / 60, minute: clock % 60))!
    }
}

extension EventTime {
    public func starting(at start: Date, in calendar: Calendar) -> EventTime {
        switch self {
        case .timed(let oldStart, let oldEnd):
            return .timed(start: start, end: start.addingTimeInterval(max(0, oldEnd.timeIntervalSince(oldStart))))
        case .allDay(let first, let last):
            let span = calendar.dateComponents([.day], from: first.start(in: calendar), to: last.start(in: calendar)).day ?? 0
            let newFirst = CivilDate(start, in: calendar)
            return .allDay(first: newFirst, last: newFirst.adding(days: span, in: calendar))
        }
    }
}
