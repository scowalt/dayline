import DaylineCore
import DaylineKit
import SwiftUI
import WidgetKit

struct UpNextWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "UpNext", provider: UpNextProvider()) { entry in
            UpNextView(entry: entry)
        }
        .configurationDisplayName("Up Next")
        .description("What's on now, what's next, and a look at tomorrow.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .systemLarge,
            .accessoryRectangular,
            .accessoryInline,
            .accessoryCircular,
        ])
    }
}

nonisolated struct UpNextEntry: TimelineEntry {
    enum Content: Sendable {
        case signedOut
        case agenda(DayGlance, CalendarColors)
    }

    static let horizon: TimeInterval = 24 * 60 * 60

    let date: Date
    let content: Content

    init(date: Date, snapshot: Snapshot?, visibility: CalendarVisibility, calendar: Calendar) {
        self.date = date
        guard let snapshot else {
            content = .signedOut
            return
        }
        let events = snapshot.events(visibleWith: visibility)
        content = .agenda(WidgetTimeline.glance(events: events, at: date, calendar: calendar), CalendarColors(snapshot))
    }

    static func timeline(snapshot: Snapshot?, visibility: CalendarVisibility, now: Date, calendar: Calendar) -> [UpNextEntry] {
        guard let snapshot else {
            return [UpNextEntry(date: now, snapshot: nil, visibility: visibility, calendar: calendar)]
        }
        let events = snapshot.events(visibleWith: visibility)
        return WidgetTimeline.entryDates(events: events, now: now, calendar: calendar, horizon: horizon).map { date in
            UpNextEntry(date: date, snapshot: snapshot, visibility: visibility, calendar: calendar)
        }
    }

    static func sample(at now: Date) -> UpNextEntry {
        UpNextEntry(date: now, snapshot: .sample(now: now, calendar: .current), visibility: CalendarVisibility(), calendar: .current)
    }
}

nonisolated struct CalendarColors: Hashable, Sendable {
    private let byCalendar: [CalendarID: RGBColor]

    init(_ snapshot: Snapshot) {
        byCalendar = Dictionary(snapshot.calendars.map { ($0.id, $0.color) }, uniquingKeysWith: { first, _ in first })
    }

    func color(for event: CalendarEvent) -> RGBColor? {
        event.color ?? byCalendar[event.calendarID]
    }
}

nonisolated struct UpNextProvider: TimelineProvider {
    func placeholder(in context: Context) -> UpNextEntry {
        .sample(at: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (UpNextEntry) -> Void) {
        let now = Date.now
        guard let snapshot = SnapshotStore.shared?.latest() else {
            completion(context.isPreview ? .sample(at: now) : UpNextEntry(date: now, snapshot: nil, visibility: CalendarVisibility(), calendar: .current))
            return
        }
        completion(UpNextEntry(date: now, snapshot: snapshot.applying(OutboxStore.shared?.load() ?? Outbox()), visibility: CalendarPreferences().visibility, calendar: .current))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<UpNextEntry>) -> Void) {
        Task {
            let preferences = CalendarPreferences()
            let snapshot = if preferences.usesDemoData {
                SnapshotStore.shared?.latest()
            } else {
                await LiveCalendarService(writer: .widget).refreshIfStale(maxAge: .seconds(15 * 60))
            }
            let now = Date.now
            let entries = UpNextEntry.timeline(snapshot: snapshot?.applying(OutboxStore.shared?.load() ?? Outbox()), visibility: preferences.visibility, now: now, calendar: .current)
            completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(30 * 60))))
        }
    }
}
