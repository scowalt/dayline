import DaylineCore
import DaylineKit
import SwiftUI
import WidgetKit

struct SmallUpNextView: View {
    let now: Date
    let glance: DayGlance
    let colors: CalendarColors

    var body: some View {
        Group {
            if let focus = glance.focus {
                ViewThatFits(in: .vertical) {
                    focusLayout(focus, compactHeader: false, titleLines: 2, showMore: true)
                    focusLayout(focus, compactHeader: false, titleLines: 2, showMore: false)
                    focusLayout(focus, compactHeader: true, titleLines: 2, showMore: true)
                    focusLayout(focus, compactHeader: true, titleLines: 2, showMore: false)
                    focusLayout(focus, compactHeader: true, titleLines: 1, showMore: false)
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    DateHeader(date: now)
                        .padding(.bottom, 6)
                    dayIsClear
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(mainEvent.map { DeepLink.event($0.id).url } ?? DeepLink.today.url)
    }

    private var mainEvent: CalendarEvent? {
        glance.focus ?? glance.nextDay.timed.first
    }

    private func focusLayout(_ focus: CalendarEvent, compactHeader: Bool, titleLines: Int, showMore: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            DateHeader(date: now, compact: compactHeader)
                .padding(.bottom, compactHeader ? 4 : 6)
            row(focus, titleLines: titleLines)
            if showMore {
                Spacer(minLength: 4)
                moreToday
            }
        }
    }

    private func row(_ event: CalendarEvent, titleLines: Int) -> some View {
        let inProgress = glance.isInProgress(event)
        return EventRow(
            event: event,
            color: colors.color(for: event),
            detail: EventTimeText.detail(for: event, inProgress: inProgress, now: now),
            shortDetail: EventTimeText.compact(for: event, inProgress: inProgress, now: now),
            titleLines: titleLines
        )
    }

    @ViewBuilder
    private var moreToday: some View {
        let more = glance.remaining.count - 1
        if more > 0 {
            Text("+\(more) more today")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
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
                row(next, titleLines: 1)
            }
        }
    }
}

struct MediumUpNextView: View {
    let now: Date
    let glance: DayGlance
    let colors: CalendarColors

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                DateHeader(date: now, compact: true)
                    .layoutPriority(1)
                Spacer(minLength: 0)
                AllDayStrip(events: glance.allDay, colors: colors)
            }

            FittingAgenda(
                lines: AgendaLine.lines(for: glance, includeAllDay: false),
                maxEvents: 8,
                spacing: 2,
                now: now,
                colors: colors,
                rowStyle: .oneLine
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(DeepLink.today.url)
    }
}

struct AllDayStrip: View {
    let events: [CalendarEvent]
    let colors: CalendarColors

    var body: some View {
        ViewThatFits(in: .horizontal) {
            strip(showing: 2)
            strip(showing: 1)
        }
        .foregroundStyle(.secondary)
    }

    private func strip(showing count: Int) -> some View {
        HStack(spacing: 10) {
            ForEach(events.prefix(count)) { event in
                Link(destination: DeepLink.event(event.id).url) {
                    AllDayLine(event: event, color: colors.color(for: event))
                }
            }
            if events.count > count {
                Text("+\(events.count - count)")
                    .font(.caption)
                    .fixedSize()
                    .accessibilityLabel(Text("\(events.count - count) more all-day events"))
            }
        }
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
                rowStyle: .twoLine
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

enum AgendaRowStyle {
    case twoLine
    case oneLine
}

struct FittingAgenda: View {
    let lines: [AgendaLine]
    let maxEvents: Int
    let spacing: CGFloat
    let now: Date
    let colors: CalendarColors
    let rowStyle: AgendaRowStyle

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
                switch rowStyle {
                case .twoLine:
                    EventRow(
                        event: event,
                        color: colors.color(for: event),
                        detail: EventTimeText.detail(for: event, inProgress: inProgress, now: now, location: true)
                    )
                case .oneLine:
                    EventLine(
                        event: event,
                        color: colors.color(for: event),
                        time: inProgress
                            ? EventTimeText.compact(for: event, inProgress: true, now: now)
                            : EventTimeText.span(of: event, inProgress: false, now: now),
                        inProgress: inProgress
                    )
                }
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
