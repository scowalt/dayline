import DaylineCore
import DaylineKit
import SwiftUI
import WidgetKit

struct DateHeader: View {
    let date: Date
    var compact = false

    var body: some View {
        Group {
            if compact {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    weekday
                    day.font(.headline)
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    weekday
                    day.font(.title.weight(.regular))
                }
            }
        }
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(date, format: .dateTime.weekday(.wide).month(.wide).day()))
    }

    private var weekday: some View {
        Text(date, format: .dateTime.weekday(.wide))
            .textCase(.uppercase)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.red)
            .widgetAccentable()
    }

    private var day: Text {
        Text(date, format: .dateTime.day())
            .monospacedDigit()
    }
}

struct CalendarBar: ViewModifier {
    @Environment(\.widgetRenderingMode) private var renderingMode
    let color: RGBColor?

    func body(content: Content) -> some View {
        content
            .padding(.leading, 9)
            .background(alignment: .leading) {
                Capsule()
                    .fill(renderingMode.calendarFill(color))
                    .frame(width: 4)
                    .widgetAccentable()
            }
    }
}

struct CalendarDot: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    let color: RGBColor?

    var body: some View {
        Circle()
            .fill(renderingMode.calendarFill(color))
            .frame(width: 7, height: 7)
            .widgetAccentable()
    }
}

extension WidgetRenderingMode {
    func calendarFill(_ color: RGBColor?) -> Color {
        guard self == .fullColor else { return .primary }
        return color.map { Color($0) } ?? .gray
    }
}

extension View {
    func calendarBar(_ color: RGBColor?) -> some View {
        modifier(CalendarBar(color: color))
    }
}

struct EventRow: View {
    let event: CalendarEvent
    let color: RGBColor?
    let detail: String
    var shortDetail: String?
    var titleLines = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(event.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(titleLines)
            ViewThatFits(in: .horizontal) {
                Text(detail)
                if let shortDetail {
                    Text(shortDetail)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .calendarBar(color)
        .accessibilityElement(children: .combine)
    }
}

struct AllDayLine: View {
    let event: CalendarEvent
    let color: RGBColor?

    var body: some View {
        HStack(spacing: 5) {
            CalendarDot(color: color)
            Text(event.title)
                .font(.caption)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("All day: \(event.title)"))
    }
}

struct SectionHeading: View {
    let title: LocalizedStringKey

    var body: some View {
        Text(title)
            .textCase(.uppercase)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }
}

enum EventTimeText {
    static func detail(for event: CalendarEvent, inProgress: Bool, now: Date, location: Bool = false) -> String {
        let time = span(of: event, inProgress: inProgress, now: now)
        guard location, let place = event.location, !place.isEmpty else { return time }
        return "\(time) · \(place)"
    }

    static func span(of event: CalendarEvent, inProgress: Bool, now: Date) -> String {
        let calendar = Calendar.current
        guard case .timed(let start, let end) = event.time else { return String(localized: "All day") }
        if inProgress {
            return String(localized: "Now · until \(until(end, now: now))")
        }
        if start == end {
            return start.formatted(date: .omitted, time: .shortened)
        }
        if calendar.isDate(start, inSameDayAs: end) {
            return (start..<end).formatted(.interval.hour().minute())
        }
        return "\(start.formatted(date: .omitted, time: .shortened)) – \(end.formatted(date: .omitted, time: .shortened))"
    }

    static func compact(for event: CalendarEvent, inProgress: Bool, now: Date) -> String {
        guard case .timed(let start, let end) = event.time else { return String(localized: "All day") }
        if inProgress {
            return String(localized: "Until \(until(end, now: now))")
        }
        return start.formatted(date: .omitted, time: .shortened)
    }

    private static func until(_ end: Date, now: Date) -> String {
        Calendar.current.isDate(end, inSameDayAs: now)
            ? end.formatted(date: .omitted, time: .shortened)
            : end.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    static func clock(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
    }
}

extension DayGlance {
    var clearDayMessage: LocalizedStringKey {
        if !finished.isEmpty {
            "No more events today"
        } else if !allDay.isEmpty {
            "Nothing else scheduled"
        } else {
            "Nothing scheduled"
        }
    }

    var shortClearDayMessage: LocalizedStringKey {
        finished.isEmpty ? "Nothing today" : "Done for today"
    }
}

extension CalendarEvent {
    var startDate: Date? {
        guard case .timed(let start, _) = time else { return nil }
        return start
    }
}
