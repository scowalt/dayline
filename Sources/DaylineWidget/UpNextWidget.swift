import DaylineCore
import DaylineKit
import SwiftUI
import WidgetKit

struct UpNextEntry: TimelineEntry {
    var date: Date
    var snapshot: Snapshot?
    var visibility: CalendarVisibility
}

struct UpNextProvider: TimelineProvider {
    func placeholder(in context: Context) -> UpNextEntry {
        UpNextEntry(date: .now, snapshot: .sample(now: .now, calendar: .current), visibility: CalendarVisibility())
    }

    func getSnapshot(in context: Context, completion: @escaping (UpNextEntry) -> Void) {
        completion(UpNextEntry(date: .now, snapshot: SnapshotStore.shared?.latest() ?? .sample(now: .now, calendar: .current), visibility: CalendarPreferences().visibility))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UpNextEntry>) -> Void) {
        Task {
            let snapshot = await LiveCalendarService(writer: .widget).refreshIfStale(maxAge: .seconds(15 * 60))
            let entry = UpNextEntry(date: .now, snapshot: snapshot, visibility: CalendarPreferences().visibility)
            completion(Timeline(entries: [entry], policy: .after(.now + 30 * 60)))
        }
    }
}

struct UpNextWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "UpNext", provider: UpNextProvider()) { entry in
            VStack(alignment: .leading) {
                ForEach(entry.snapshot?.events(visibleWith: entry.visibility) ?? []) { event in
                    Text(event.title).font(.caption)
                }
            }
            .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Up Next")
        .description("Your next events.")
    }
}
