import DaylineCore
import DaylineKit
import SwiftUI
import WidgetKit

struct RectangularUpNextView: View {
    let now: Date
    let glance: DayGlance
    let colors: CalendarColors

    var body: some View {
        Group {
            if let focus = glance.focus {
                card(focus, detail: EventTimeText.span(of: focus, inProgress: glance.isInProgress(focus), now: now))
            } else if let next = glance.nextDay.timed.first, let start = next.startDate {
                card(next, detail: String(localized: "Tomorrow at \(start.formatted(date: .omitted, time: .shortened))"))
            } else {
                Text(glance.clearDayMessage)
                    .font(.headline)
                    .lineLimit(2)
                    .widgetAccentable()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL((glance.focus ?? glance.nextDay.timed.first).map { DeepLink.event($0.id).url } ?? DeepLink.today.url)
    }

    private func card(_ event: CalendarEvent, detail: String) -> some View {
        ViewThatFits(in: .vertical) {
            if let location = event.location, !location.isEmpty {
                lines(event, detail: detail, titleFont: .headline, titleLines: 2, location: location)
            }
            lines(event, detail: detail, titleFont: .headline, titleLines: 2, location: nil)
            lines(event, detail: detail, titleFont: .subheadline.weight(.semibold), titleLines: 2, location: nil)
            lines(event, detail: detail, titleFont: .headline, titleLines: 1, location: nil)
        }
    }

    private func lines(_ event: CalendarEvent, detail: String, titleFont: Font, titleLines: Int, location: String?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(event.title)
                .font(titleFont)
                .lineLimit(titleLines)
                .widgetAccentable()
            Text(detail)
                .font(.footnote)
                .lineLimit(1)
            if let location {
                Text(location)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .calendarBar(colors.color(for: event))
        .accessibilityElement(children: .combine)
    }
}

struct InlineUpNextView: View {
    let glance: DayGlance

    var body: some View {
        Group {
            if let focus = glance.focus, let start = focus.startDate {
                if glance.isInProgress(focus) {
                    Text("Now · \(focus.title)")
                } else {
                    Text("\(EventTimeText.clock(start)) \(focus.title)")
                }
            } else if let next = glance.nextDay.timed.first, let start = next.startDate {
                Text("\(start.formatted(.dateTime.weekday(.abbreviated))) \(EventTimeText.clock(start)) \(next.title)")
            } else {
                Text(glance.clearDayMessage)
            }
        }
        .widgetURL((glance.focus ?? glance.nextDay.timed.first).map { DeepLink.event($0.id).url } ?? DeepLink.today.url)
    }
}

struct CircularUpNextView: View {
    let now: Date
    let glance: DayGlance

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                label
                    .font(.caption2.weight(.semibold))
                    .widgetAccentable()
                value
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
            }
            .lineLimit(1)
            .padding(6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .widgetURL(next.map { DeepLink.event($0.event.id).url } ?? DeepLink.today.url)
    }

    private var next: (event: CalendarEvent, start: Date, isToday: Bool)? {
        if let event = glance.upcoming.first, let start = event.startDate {
            return (event, start, true)
        }
        if let event = glance.nextDay.timed.first, let start = event.startDate {
            return (event, start, false)
        }
        return nil
    }

    @ViewBuilder
    private var label: some View {
        if let next, next.isToday {
            Image(systemName: "calendar")
        } else {
            Text((next?.start ?? now).formatted(.dateTime.weekday(.abbreviated)).uppercased())
        }
    }

    @ViewBuilder
    private var value: some View {
        if let next {
            Text(EventTimeText.clock(next.start))
        } else {
            Text(now, format: .dateTime.day())
        }
    }

    private var accessibilityText: Text {
        guard let next else { return Text(glance.clearDayMessage) }
        return Text("Next: \(next.event.title), \(next.start.formatted(.dateTime.weekday(.wide).hour().minute()))")
    }
}
