import AuthenticationServices
import DaylineCore
import DaylineKit
import SwiftUI

struct AgendaView: View {
    let model: AppModel
    let state: AppModel.SignedIn
    @Environment(\.calendar) private var calendar
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @AppStorage("calendarLayout") private var layout = CalendarLayout.list
    @State private var firstDay = CivilDate(.now, in: .current)
    @State private var path: [EventID] = []
    @State private var scrollTarget: CivilDate?
    @State private var isShowingSettings = false

    var body: some View {
        NavigationStack(path: $path) {
            TimelineView(.everyMinute) { context in
                content(now: context.date)
                    .navigationSubtitle(status(now: context.date))
            }
            .navigationTitle(layout == .list ? "Agenda" : "Calendar")
            .navigationBarTitleDisplayMode(layout == .list ? .automatic : .inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu("Layout", systemImage: layout.symbolName) {
                        Picker("Layout", selection: $layout) {
                            ForEach(CalendarLayout.allCases) { option in
                                Label(option.title, systemImage: option.symbolName)
                            }
                        }
                    }
                }
                if layout != .list {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Today") {
                            firstDay = CivilDate(.now, in: calendar)
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape") {
                        isShowingSettings = true
                    }
                }
            }
            .navigationDestination(for: EventID.self) { id in
                EventDetailView(model: model, id: id)
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView(model: model)
        }
        .alert(
            "Couldn't Move \(state.rescheduleIssue?.eventTitle ?? "Event")",
            isPresented: Binding(get: { state.rescheduleIssue != nil }, set: { if !$0 { model.dismissRescheduleIssue() } }),
            presenting: state.rescheduleIssue
        ) { issue in
            if issue.error == .missingEditPermission || issue.error == .sessionExpired {
                Button("Allow Changes") {
                    Task { await model.signIn(authorize: webAuthenticationSession.authorize, loginHint: issue.account.email) }
                }
                Button("Not Now", role: .cancel) {}
            } else {
                Button("OK", role: .cancel) {}
            }
        } message: { issue in
            Text(issue.error == .missingEditPermission
                ? "Sign in to \(issue.account.email) again and allow Dayline to change your events. The event is back where it was."
                : "\(issue.error.signInMessage ?? "Google didn't accept the change.") The event is back where it was.")
        }
        .task(id: model.pendingLink) {
            guard let link = model.takePendingLink() else { return }
            isShowingSettings = false
            switch link {
            case .today:
                path = []
                scrollTarget = CivilDate(.now, in: calendar)
                firstDay = CivilDate(.now, in: calendar)
            case .day(let date):
                path = []
                scrollTarget = date
                firstDay = date
            case .event(let id):
                path = [id]
            }
        }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        if let snapshot = state.snapshot, layout != .list {
            ScheduleView(model: model, snapshot: snapshot, now: now, dayCount: layout == .day ? 1 : 3, firstDay: $firstDay) { path.append($0) }
        } else if let snapshot = state.snapshot {
            let days = agendaDays(in: snapshot, now: now)
            ScrollViewReader { proxy in
                List {
                    ForEach(days) { day in
                        DaySection(day: day, snapshot: snapshot, now: now)
                            .id(day.date)
                    }
                }
                .listStyle(.plain)
                .environment(\.defaultMinListRowHeight, 0)
                .refreshable { await model.refresh() }
                .onChange(of: scrollTarget, initial: true) {
                    guard let target = scrollTarget else { return }
                    scrollTarget = nil
                    guard let shown = days.first(where: { $0.date >= target }) ?? days.last else { return }
                    withAnimation {
                        proxy.scrollTo(shown.date, anchor: .top)
                    }
                }
            }
        } else if let issue = state.firstIssue?.error, !state.isRefreshing {
            ContentUnavailableView {
                Label("Couldn't Load Your Calendar", systemImage: issue.symbolName)
            } description: {
                Text(state.issueMessage ?? "")
            } actions: {
                Button("Try Again") {
                    Task { await model.refresh() }
                }
                .buttonStyle(.bordered)
            }
        } else {
            ProgressView("Loading your calendar…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func agendaDays(in snapshot: Snapshot, now: Date) -> [AgendaDay] {
        let today = CivilDate(now, in: calendar)
        let last = CivilDate(snapshot.range.end.addingTimeInterval(-1), in: calendar)
        let days = Agenda.days(events: model.visibleEvents, from: today, through: last, calendar: calendar)
            .filter { !$0.isEmpty || $0.date == today }
        return days.isEmpty ? [AgendaDay(date: today)] : days
    }

    private func status(now: Date) -> String {
        if state.isRefreshing {
            return "Updating…"
        }
        let updated = state.snapshot.map { updatedText(fetchedAt: $0.fetchedAt, now: now) }
        return [state.issueMessage, updated].compactMap(\.self).joined(separator: " · ")
    }

    private func updatedText(fetchedAt: Date, now: Date) -> String {
        guard now.timeIntervalSince(fetchedAt) >= 60 else { return "Updated just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.calendar = calendar
        formatter.dateTimeStyle = .named
        return "Updated \(formatter.localizedString(for: fetchedAt, relativeTo: now))"
    }
}

private struct DaySection: View {
    let day: AgendaDay
    let snapshot: Snapshot
    let now: Date
    @Environment(\.calendar) private var calendar

    var body: some View {
        Section {
            ForEach(day.allDay) { event in
                NavigationLink(value: event.id) {
                    AllDayRow(event: event, color: snapshot.color(of: event), portion: event.time.portion(on: day.date, in: calendar))
                }
            }
            ForEach(rows) { row in
                switch row {
                case .event(let event):
                    NavigationLink(value: event.id) {
                        EventRow(
                            event: event,
                            color: snapshot.color(of: event),
                            portion: event.time.portion(on: day.date, in: calendar),
                            hasEnded: event.hasEnded(at: now, calendar: calendar),
                            isJoinable: event.isJoinable(at: now, calendar: calendar)
                        )
                    }
                case .now:
                    NowMarker(now: now)
                case .nothingLeft:
                    Text("No more events today")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            DayHeader(date: day.date, today: CivilDate(now, in: calendar))
        }
        .listRowSeparator(.hidden)
    }

    private var rows: [TimedRow] {
        let events = day.timed.map(TimedRow.event)
        guard day.date == CivilDate(now, in: calendar) else { return events }
        let started = day.startedCount(at: now, calendar: calendar)
        let hasRemaining = day.timed.contains { !$0.hasEnded(at: now, calendar: calendar) }
        var rows = events
        if started > 0 {
            rows.insert(.now, at: started)
        }
        if !hasRemaining {
            rows.append(.nothingLeft)
        }
        return rows
    }
}

private enum TimedRow: Identifiable {
    case event(CalendarEvent)
    case now
    case nothingLeft

    var id: String {
        switch self {
        case .event(let event): "event:\(event.id.calendar.rawValue):\(event.id.event)"
        case .now: "now"
        case .nothingLeft: "nothing-left"
        }
    }
}

private struct DayHeader: View {
    let date: CivilDate
    let today: CivilDate
    @Environment(\.calendar) private var calendar

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.headline)
                .foregroundStyle(date == today ? AnyShapeStyle(.tint) : AnyShapeStyle(Color(.label)))
            Spacer()
            if relativeName != nil {
                Text(date.start(in: calendar), format: .dateTime.weekday(.wide).month(.abbreviated).day())
                    .font(.subheadline)
                    .foregroundStyle(Color(.secondaryLabel))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var relativeName: String? {
        switch date {
        case today: "Today"
        case today.adding(days: 1, in: calendar): "Tomorrow"
        default: nil
        }
    }

    private var title: String {
        relativeName ?? date.start(in: calendar).formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }
}
