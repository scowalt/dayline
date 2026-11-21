import DaylineCore
import DaylineKit
import SwiftUI

enum CalendarLayout: String, CaseIterable, Identifiable {
    case list
    case day
    case threeDays

    var id: Self { self }

    var title: String {
        switch self {
        case .list: "List"
        case .day: "Day"
        case .threeDays: "3 Days"
        }
    }

    var symbolName: String {
        switch self {
        case .list: "list.bullet"
        case .day: "calendar.day.timeline.left"
        case .threeDays: "rectangle.split.3x1"
        }
    }
}

struct ScheduleView: View {
    let model: AppModel
    let snapshot: Snapshot
    let now: Date
    let dayCount: Int
    @Binding var firstDay: CivilDate
    let open: (EventID) -> Void
    @Environment(\.calendar) private var calendar

    var body: some View {
        let today = CivilDate(now, in: calendar)
        let dates = stripDates(today: today)
        let start = shownStart(in: dates)
        let days = (0..<dayCount).map { start.adding(days: $0, in: calendar) }
        let events = model.visibleEvents
        VStack(spacing: 0) {
            DayStrip(dates: dates, shown: days, today: today) { date in
                firstDay = date
            }
            ColumnHeaders(days: days, today: today, events: events, snapshot: snapshot, open: open)
            Divider()
            ScheduleGrid(days: days, events: events, snapshot: snapshot, now: now, open: open) { event, time, notifyGuests in
                Task { await model.reschedule(event, to: time, notifyGuests: notifyGuests) }
            }
        }
    }

    private func stripDates(today: CivilDate) -> [CivilDate] {
        let last = CivilDate(snapshot.range.end.addingTimeInterval(-1), in: calendar)
        var dates: [CivilDate] = []
        var date = today
        while date <= last {
            dates.append(date)
            date = date.adding(days: 1, in: calendar)
        }
        return dates.isEmpty ? [today] : dates
    }

    private func shownStart(in dates: [CivilDate]) -> CivilDate {
        let latest = dates[max(0, dates.count - dayCount)]
        return min(max(firstDay, dates[0]), latest)
    }
}

private struct DayStrip: View {
    let dates: [CivilDate]
    let shown: [CivilDate]
    let today: CivilDate
    let select: (CivilDate) -> Void
    @Environment(\.calendar) private var calendar

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    ForEach(dates, id: \.self) { date in
                        Button {
                            select(date)
                        } label: {
                            chip(date)
                        }
                        .buttonStyle(.plain)
                        .id(date)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .scrollIndicators(.hidden)
            .onChange(of: shown.first, initial: true) {
                guard let first = shown.first else { return }
                withAnimation {
                    proxy.scrollTo(first, anchor: .center)
                }
            }
        }
    }

    private func chip(_ date: CivilDate) -> some View {
        let isShown = shown.contains(date)
        let start = date.start(in: calendar)
        return VStack(spacing: 2) {
            Text(start, format: .dateTime.weekday(.narrow))
                .font(.caption2.weight(.medium))
                .foregroundStyle(isShown ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.secondary))
            Text(start, format: .dateTime.day())
                .font(.callout.weight(date == today || isShown ? .bold : .regular))
                .foregroundStyle(isShown ? AnyShapeStyle(.white) : date == today ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
        }
        .frame(width: 40, height: 46)
        .background(isShown ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 10))
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(start.formatted(.dateTime.weekday(.wide).month(.wide).day()))
        .accessibilityAddTraits(isShown ? [.isButton, .isSelected] : .isButton)
    }
}

private struct ColumnHeaders: View {
    let days: [CivilDate]
    let today: CivilDate
    let events: [CalendarEvent]
    let snapshot: Snapshot
    let open: (EventID) -> Void
    @Environment(\.calendar) private var calendar

    var body: some View {
        let columns = Agenda.days(events: events, from: days[0], through: days[days.count - 1], calendar: calendar)
        HStack(alignment: .top, spacing: 0) {
            Color.clear.frame(width: ScheduleGrid.gutter, height: 0)
            ForEach(columns) { column in
                VStack(alignment: .leading, spacing: 2) {
                    Text(column.date.start(in: calendar), format: .dateTime.weekday(.abbreviated).day())
                        .font(.subheadline.weight(column.date == today ? .bold : .medium))
                        .foregroundStyle(column.date == today ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        .accessibilityAddTraits(.isHeader)
                    ForEach(column.allDay) { event in
                        Button {
                            open(event.id)
                        } label: {
                            Text(event.title)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(snapshot.color(of: event).opacity(0.25), in: .rect(cornerRadius: 4))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(event.title), all day")
                    }
                }
                .padding(.horizontal, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 6)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct ScheduleGrid: View {
    static let gutter: CGFloat = 52
    static let hourHeight: CGFloat = 56
    private static let pointsPerMinute = hourHeight / 60
    private static let space = "schedule-grid"
    private static let edge: CGFloat = 56

    let days: [CivilDate]
    let events: [CalendarEvent]
    let snapshot: Snapshot
    let now: Date
    let open: (EventID) -> Void
    let commit: (CalendarEvent, EventTime, Bool) -> Void

    @Environment(\.calendar) private var calendar
    @GestureState private var drag: EventDrag?
    @State private var confirming: Move?
    @State private var width: CGFloat = 0
    @State private var position = ScrollPosition(edge: .top)
    @State private var scroll = ScrollState()
    @State private var lifts = 0
    @State private var isPlaced = false

    var body: some View {
        ScrollView {
            ZStack(alignment: .topLeading) {
                hourLines
                ForEach(Array(days.enumerated()), id: \.element) { column, day in
                    ForEach(TimeGrid.placements(of: events, on: day, calendar: calendar), id: \.event.id) { placement in
                        block(placement, column: column, day: day)
                    }
                }
                nowLine
                if let move = shownMove {
                    ghost(move)
                }
            }
            .frame(maxWidth: .infinity, minHeight: Self.hourHeight * 24, maxHeight: Self.hourHeight * 24, alignment: .topLeading)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .coordinateSpace(.named(Self.space))
        }
        .scrollPosition($position)
        .scrollDisabled(drag != nil)
        .onScrollGeometryChange(for: ScrollState.self) { geometry in
            ScrollState(offset: geometry.contentOffset.y, visible: geometry.visibleRect, maxOffset: geometry.contentSize.height - geometry.containerSize.height + geometry.contentInsets.bottom)
        } action: { _, state in
            scroll.offset = state.offset
            scroll.visible = state.visible
            scroll.maxOffset = state.maxOffset
            if !isPlaced, state.visible.height > 0 {
                isPlaced = true
                position.scrollTo(y: min(max(0, initialOffset - state.visible.height / 3), max(0, state.maxOffset)))
            }
        }
        .task(id: drag != nil) {
            await autoscroll()
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: lifts)
        .sensoryFeedback(.selection, trigger: shownMove?.time)
        .confirmationDialog(
            "Send updates to guests?",
            isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
            titleVisibility: .visible,
            presenting: confirming
        ) { move in
            Button("Send") { finish(move, notifyGuests: true) }
            Button("Don't Send") { finish(move, notifyGuests: false) }
            Button("Cancel", role: .cancel) { confirming = nil }
        } message: { move in
            Text("\(move.event.title) moves to \(move.summary(in: calendar)).")
        }
    }

    private var columnWidth: CGFloat {
        max(0, width - Self.gutter) / CGFloat(days.count)
    }

    private var initialOffset: CGFloat {
        let today = CivilDate(now, in: calendar)
        let minute = days.contains(today) ? TimeGrid.minute(of: now, from: today, calendar: calendar) : 9 * 60
        return CGFloat(minute) * Self.pointsPerMinute
    }

    private var shownMove: Move? {
        if let confirming { return confirming }
        guard let drag, let value = drag.value else { return nil }
        return move(for: drag, value: value)
    }

    private var hourLines: some View {
        ForEach(0..<25, id: \.self) { hour in
            let y = CGFloat(hour) * Self.hourHeight
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(Color(.separator))
                    .frame(height: 0.5)
                    .padding(.leading, Self.gutter)
                    .offset(y: y)
                if hour > 0 && hour < 24 {
                    Text(hourLabel(hour))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: Self.gutter - 8, alignment: .trailing)
                        .offset(y: y - 7)
                }
            }
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder private var nowLine: some View {
        let today = CivilDate(now, in: calendar)
        if let column = days.firstIndex(of: today) {
            let y = CGFloat(TimeGrid.minute(of: now, from: today, calendar: calendar)) * Self.pointsPerMinute
            HStack(spacing: 0) {
                Circle().fill(.red).frame(width: 8, height: 8)
                Rectangle().fill(.red).frame(height: 1.5)
            }
            .frame(width: columnWidth + 4)
            .offset(x: Self.gutter + CGFloat(column) * columnWidth - 4, y: y - 4)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private func block(_ placement: TimeGridPlacement, column: Int, day: CivilDate) -> some View {
        let event = placement.event
        let slot = columnWidth / CGFloat(placement.columnCount)
        let height = max(CGFloat(placement.endMinute - placement.startMinute) * Self.pointsPerMinute, 18)
        let isMoving = shownMove?.event.id == event.id
        return EventBlock(event: event, color: snapshot.color(of: event), height: height)
            .frame(width: max(0, slot - 2), height: height - 1)
            .offset(x: Self.gutter + CGFloat(column) * columnWidth + CGFloat(placement.column) * slot + 1, y: CGFloat(placement.startMinute) * Self.pointsPerMinute)
            .opacity(isMoving ? 0.35 : 1)
            .onTapGesture { open(event.id) }
            .gesture(moveGesture(event, from: day), including: event.canReschedule ? .all : .subviews)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { open(event.id) }
            .accessibilityActions {
                if event.canReschedule {
                    Button("Move 30 minutes earlier") { propose(event, by: -30, days: 0) }
                    Button("Move 30 minutes later") { propose(event, by: 30, days: 0) }
                    Button("Move to the previous day") { propose(event, by: 0, days: -1) }
                    Button("Move to the next day") { propose(event, by: 0, days: 1) }
                }
            }
    }

    private func ghost(_ move: Move) -> some View {
        let moved = CalendarEvent(id: move.event.id, title: move.event.title, time: move.time, color: move.event.color)
        let color = snapshot.color(of: move.event)
        return ForEach(Array(days.enumerated()), id: \.element) { column, day in
            if let placement = TimeGrid.placements(of: [moved], on: day, calendar: calendar).first {
                let height = max(CGFloat(placement.endMinute - placement.startMinute) * Self.pointsPerMinute, 18)
                EventBlock(event: moved, color: color, height: height, isLifted: true)
                    .frame(width: max(0, columnWidth - 2), height: height - 1)
                    .offset(x: Self.gutter + CGFloat(column) * columnWidth + 1, y: CGFloat(placement.startMinute) * Self.pointsPerMinute)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }

    private func moveGesture(_ event: CalendarEvent, from day: CivilDate) -> some Gesture {
        LongPressGesture(minimumDuration: 0.35)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space)))
            .updating($drag) { value, state, _ in
                guard case .second(true, let dragValue) = value else { return }
                state = EventDrag(event: event, origin: day, value: dragValue)
            }
            .onChanged { value in
                switch value {
                case .second(true, nil):
                    lifts += 1
                case .second(true, .some):
                    scroll.offsetAtTouch = scroll.offset
                default:
                    break
                }
            }
            .onEnded { value in
                guard case .second(true, let dragValue?) = value else { return }
                propose(move(for: EventDrag(event: event, origin: day, value: dragValue), value: dragValue))
            }
    }

    private func move(for drag: EventDrag, value: DragGesture.Value) -> Move {
        let eventTop = CGFloat(TimeGrid.minute(of: drag.event.time.interval(in: calendar).start, from: drag.origin, calendar: calendar)) * Self.pointsPerMinute
        let grab = value.startLocation.y - eventTop
        let fingerY = value.location.y + scroll.offset - scroll.offsetAtTouch
        let column = columnWidth > 0 ? Int(((value.location.x - Self.gutter) / columnWidth).rounded(.down)) : 0
        let day = days[min(max(column, 0), days.count - 1)]
        let start = TimeGrid.snappedDate(atMinute: Double((fingerY - grab) / Self.pointsPerMinute), from: day, calendar: calendar)
        return Move(event: drag.event, time: drag.event.time.starting(at: start, in: calendar))
    }

    private func propose(_ event: CalendarEvent, by minutes: Int, days: Int) {
        let start = event.time.interval(in: calendar).start
        let shifted = calendar.date(byAdding: .day, value: days, to: start)!.addingTimeInterval(TimeInterval(minutes * 60))
        propose(Move(event: event, time: event.time.starting(at: shifted, in: calendar)))
    }

    private func propose(_ move: Move) {
        guard move.time != move.event.time else { return }
        if move.event.attendeeCount > 1 {
            confirming = move
        } else {
            finish(move, notifyGuests: false)
        }
    }

    private func finish(_ move: Move, notifyGuests: Bool) {
        confirming = nil
        commit(move.event, move.time, notifyGuests)
    }

    private func autoscroll() async {
        while drag != nil, !Task.isCancelled {
            if let value = drag?.value {
                let fingerY = value.location.y + scroll.offset - scroll.offsetAtTouch
                let step: CGFloat = if fingerY < scroll.visible.minY + Self.edge {
                    -8
                } else if fingerY > scroll.visible.maxY - Self.edge {
                    8
                } else {
                    0
                }
                let target = min(max(scroll.offset + step, 0), max(0, scroll.maxOffset))
                if step != 0, target != scroll.offset {
                    position.scrollTo(y: target)
                }
            }
            try? await Task.sleep(for: .milliseconds(16))
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        calendar.date(bySettingHour: hour, minute: 0, second: 0, of: .now)!.formatted(.dateTime.hour())
    }
}

private struct ScrollState: Equatable {
    var offset: CGFloat = 0
    var visible: CGRect = .zero
    var maxOffset: CGFloat = 0
    var offsetAtTouch: CGFloat = 0
}

private struct EventDrag: Equatable {
    let event: CalendarEvent
    let origin: CivilDate
    let value: DragGesture.Value?
}

private struct Move: Equatable {
    let event: CalendarEvent
    let time: EventTime

    func summary(in calendar: Calendar) -> String {
        let start = time.interval(in: calendar).start
        return start.formatted(.dateTime.weekday(.wide).hour().minute())
    }
}

private struct EventBlock: View {
    let event: CalendarEvent
    let color: Color
    let height: CGFloat
    var isLifted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if height < 34 {
                Text("\(Text(event.title).fontWeight(.semibold))  \(Text(timeText).foregroundStyle(.secondary))")
                    .lineLimit(1)
            } else {
                Text(event.title)
                    .fontWeight(.semibold)
                    .strikethrough(event.attendance == .declined)
                    .lineLimit(max(1, Int((height - 18) / 15)))
                Text(timeText)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .font(.caption)
        .padding(.leading, 7)
        .padding(.trailing, 3)
        .padding(.vertical, height < 34 ? 1 : 3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 5)
                .fill(isLifted ? AnyShapeStyle(color) : AnyShapeStyle(color.opacity(event.attendance?.awaitsDecision == true ? 0.08 : 0.22)))
                .strokeBorder(color, lineWidth: event.attendance?.awaitsDecision == true ? 1 : 0)
        }
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: 5, bottomLeadingRadius: 5)
                .fill(color)
                .frame(width: 3)
        }
        .foregroundStyle(isLifted ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        .clipShape(.rect(cornerRadius: 5))
        .shadow(color: .black.opacity(isLifted ? 0.25 : 0), radius: 6, y: 3)
        .opacity(event.attendance == .declined ? 0.5 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(event.title)
        .accessibilityValue(timeText)
    }

    private var timeText: String {
        guard case .timed(let start, let end) = event.time else { return "All day" }
        return start == end ? start.timeText : "\(start.timeText) – \(end.timeText)"
    }
}
