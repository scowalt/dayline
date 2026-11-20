import DaylineCore
import DaylineKit
import SwiftUI
import WidgetKit

struct SmallUpNextView: View {
    let now: Date
    let glance: DayGlance
    let colors: CalendarColors

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DateHeader(date: now)
                .padding(.bottom, 6)
            if let focus = glance.focus {
                EventRow(
                    event: focus,
                    color: colors.color(for: focus),
                    detail: EventTimeText.detail(for: focus, inProgress: glance.isInProgress(focus), now: now),
                    titleLines: 2
                )
                Spacer(minLength: 4)
                let more = glance.remaining.count - 1
                if more > 0 {
                    Text("+\(more) more today")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            } else {
                dayIsClear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(mainEvent.map { DeepLink.event($0.id).url } ?? DeepLink.today.url)
    }

    private var mainEvent: CalendarEvent? {
        glance.focus ?? glance.nextDay.timed.first
    }

    @ViewBuilder
    private var dayIsClear: some View {
        if glance.finished.isEmpty, let allDay = glance.allDay.first {
            AllDayLine(event: allDay, color: colors.color(for: allDay))
        } else {
            ViewThatFits(in: .horizontal) {
                Text(glance.clearDayMessage)
                Text(glance.shortClearDayMessage)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        Spacer(minLength: 6)
        if let next = glance.nextDay.timed.first {
            VStack(alignment: .leading, spacing: 3) {
                SectionHeading(title: "Tomorrow")
                EventRow(
                    event: next,
                    color: colors.color(for: next),
                    detail: EventTimeText.detail(for: next, inProgress: false, now: now)
                )
            }
        }
    }
}

struct MediumUpNextView: View {
    let now: Date
    let glance: DayGlance
    let colors: CalendarColors

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                DateHeader(date: now)
                Spacer(minLength: 0)
                ForEach(glance.allDay.prefix(2)) { event in
                    AllDayLine(event: event, color: colors.color(for: event))
                }
                if glance.allDay.count > 2 {
                    Text("+\(glance.allDay.count - 2) all-day")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 96, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .topLeading)

            FittingAgenda(
                lines: AgendaLine.lines(for: glance, includeAllDay: false),
                maxEvents: 4,
                spacing: 6,
                now: now,
                colors: colors,
                showsLocation: false
            )
        }
        .widgetURL(DeepLink.today.url)
    }
}

struct LargeUpNextView: View {
    let now: Date
    let glance: DayGlance
    let colors: CalendarColors

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(now, format: .dateTime.weekday(.wide))
                    .foregroundStyle(.red)
                    .widgetAccentable()
                Text(now, format: .dateTime.month(.wide).day())
                    .foregroundStyle(.secondary)
            }
            .font(.headline)
            .lineLimit(1)
            .accessibilityElement(children: .combine)

            FittingAgenda(
                lines: AgendaLine.lines(for: glance, includeAllDay: true),
                maxEvents: .max,
                spacing: 8,
                now: now,
                colors: colors,
                showsLocation: true
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(DeepLink.today.url)
    }
}

enum AgendaLine {
    case event(CalendarEvent, inProgress: Bool)
    case allDay(CalendarEvent)
    case heading(LocalizedStringKey)
    case note(LocalizedStringKey)

    static func lines(for glance: DayGlance, includeAllDay: Bool) -> [AgendaLine] {
        var lines = includeAllDay ? glance.allDay.map(AgendaLine.allDay) : []
        lines += glance.remaining.map { .event($0, inProgress: glance.isInProgress($0)) }
        if glance.remaining.isEmpty {
            lines.append(.note(glance.clearDayMessage))
        }
        let tomorrow = (includeAllDay ? glance.nextDay.allDay.map(AgendaLine.allDay) : [])
            + glance.nextDay.timed.map { .event($0, inProgress: false) }
        if !tomorrow.isEmpty {
            lines.append(.heading("Tomorrow"))
            lines += tomorrow
        }
        return lines
    }

    var isEvent: Bool {
        if case .event = self { true } else { false }
    }

    var isHeading: Bool {
        if case .heading = self { true } else { false }
    }
}

struct FittingAgenda: View {
    let lines: [AgendaLine]
    let maxEvents: Int
    let spacing: CGFloat
    let now: Date
    let colors: CalendarColors
    let showsLocation: Bool

    var body: some View {
        let candidates = candidates
        ViewThatFits(in: .vertical) {
            ForEach(candidates.indices, id: \.self) { index in
                stack(candidates[index])
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var candidates: [[AgendaLine]] {
        var events = 0
        let capped = lines.prefix { line in
            if line.isEvent { events += 1 }
            return events <= maxEvents
        }
        return capped.indices.reversed()
            .map { Array(capped[...$0]) }
            .filter { $0.last?.isHeading == false }
    }

    private func stack(_ shown: [AgendaLine]) -> some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(Array(shown.enumerated()), id: \.offset) { index, line in
                row(line)
                    .padding(.top, line.isHeading && index > 0 ? 4 : 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func row(_ line: AgendaLine) -> some View {
        switch line {
        case .event(let event, let inProgress):
            Link(destination: DeepLink.event(event.id).url) {
                EventRow(
                    event: event,
                    color: colors.color(for: event),
                    detail: EventTimeText.detail(for: event, inProgress: inProgress, now: now, location: showsLocation)
                )
            }
        case .allDay(let event):
            Link(destination: DeepLink.event(event.id).url) {
                AllDayLine(event: event, color: colors.color(for: event))
            }
        case .heading(let title):
            SectionHeading(title: title)
        case .note(let message):
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
