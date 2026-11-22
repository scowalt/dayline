import DaylineCore
import DaylineKit
import SwiftUI

struct EventDetailView: View {
    let model: AppModel
    let id: EventID
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let snapshot = model.snapshot, let event = model.event(id) {
                EventDetails(event: event, calendarInfo: snapshot.calendar(event.calendarID), color: snapshot.color(of: event)) {
                    model.hideEvents(titled: event.title)
                    dismiss()
                } delete: { scope, notifyGuests in
                    dismiss()
                    Task { await model.delete(event, scope: scope, notifyGuests: notifyGuests) }
                }
            } else {
                ContentUnavailableView(
                    "Event Not Found",
                    systemImage: "calendar.badge.exclamationmark",
                    description: Text("It may have moved or been deleted in Google Calendar.")
                )
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct EventDetails: View {
    let event: CalendarEvent
    let calendarInfo: CalendarInfo?
    let color: Color
    let hideTitle: () -> Void
    let delete: (DeletionScope, Bool) -> Void
    @Environment(\.calendar) private var calendar
    @Environment(\.openURL) private var openURL
    @State private var isChoosingScope = false
    @State private var cancellationScope: DeletionScope?

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(event.title)
                        .font(.title2.bold())
                        .strikethrough(event.attendance == .declined)
                        .textSelection(.enabled)
                    if let calendarInfo {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(color)
                                .frame(width: 10, height: 10)
                                .accessibilityHidden(true)
                            Text(calendarInfo.title)
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Calendar: \(calendarInfo.title)")
                    }
                }
                .padding(.vertical, 4)
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(when.date)
                        Text(when.time)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "calendar")
                }
                .accessibilityElement(children: .combine)
            }
            if let url = event.conferenceURL {
                Section {
                    Button {
                        openURL(url)
                    } label: {
                        Label(Self.joinTitle(for: url), systemImage: "video.fill")
                            .labelStyle(.titleAndIcon)
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                } footer: {
                    Text(Self.displayAddress(of: url))
                        .frame(maxWidth: .infinity)
                }
            }
            if let location = event.location, !location.isEmpty {
                Section {
                    Button {
                        openURL(Self.mapsURL(for: location))
                    } label: {
                        Label(location, systemImage: "mappin.and.ellipse")
                    }
                    .accessibilityHint("Opens in Maps")
                }
            }
            if event.attendance != nil || event.attendeeCount > 0 {
                Section {
                    if let attendance = event.attendance {
                        LabeledContent("Your response") {
                            HStack(spacing: 6) {
                                Image(systemName: attendance.symbolName)
                                    .accessibilityHidden(true)
                                Text(attendance.label)
                            }
                            .foregroundStyle(attendance.tint)
                        }
                    }
                    if event.attendeeCount > 0 {
                        LabeledContent("Guests", value: event.attendeeCount.formatted())
                    }
                }
            }
            if let notes = event.notes, !notes.isEmpty {
                Section("Notes") {
                    Text(notes)
                        .textSelection(.enabled)
                }
            }
            if let webURL = event.webURL {
                Section {
                    Link(destination: webURL) {
                        Label("Open in Google Calendar", systemImage: "arrow.up.forward.app")
                    }
                }
            }
            if !event.deletionScopes.isEmpty {
                Section {
                    Button("Delete Event", systemImage: "trash", role: .destructive) {
                        isChoosingScope = true
                    }
                    .confirmationDialog("Delete “\(event.title)”?", isPresented: $isChoosingScope, titleVisibility: .visible) {
                        ForEach(event.deletionScopes, id: \.self) { scope in
                            Button(event.occurrence == nil ? "Delete Event" : scope.title, role: .destructive) {
                                choose(scope)
                            }
                        }
                    } message: {
                        Text(event.occurrence == nil ? "It's also removed from Google Calendar." : "This is a repeating event.")
                    }
                    .confirmationDialog(
                        "Send cancellation to guests?",
                        isPresented: Binding(get: { cancellationScope != nil }, set: { if !$0 { cancellationScope = nil } }),
                        titleVisibility: .visible,
                        presenting: cancellationScope
                    ) { scope in
                        Button("Send") { delete(scope, true) }
                        Button("Don't Send") { delete(scope, false) }
                        Button("Cancel", role: .cancel) {}
                    } message: { _ in
                        Text("“\(event.title)” is cancelled for everyone invited.")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu("More", systemImage: "ellipsis") {
                    Button(action: hideTitle) {
                        Label("Hide Events Titled “\(event.title)”", systemImage: "eye.slash")
                        Text("Show them again in Settings.")
                    }
                }
            }
        }
    }

    private func choose(_ scope: DeletionScope) {
        if event.isOrganizer, event.attendeeCount > 1 {
            cancellationScope = scope
        } else {
            delete(scope, false)
        }
    }

    private var when: (date: String, time: String) {
        let days = event.time.days(in: calendar)
        let first = days.lowerBound.start(in: calendar)
        let last = days.upperBound.start(in: calendar)
        let dateRange = days.lowerBound == days.upperBound
            ? first.formatted(.dateTime.weekday(.wide).month(.wide).day())
            : "\(first.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) – \(last.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))"
        switch event.time {
        case .allDay:
            let count = (calendar.dateComponents([.day], from: first, to: last).day ?? 0) + 1
            return (dateRange, count > 1 ? "All day · \(count) days" : "All day")
        case .timed(let start, let end):
            guard end > start else { return (dateRange, start.timeText) }
            let length = Duration.seconds(end.timeIntervalSince(start))
                .formatted(.units(allowed: [.days, .hours, .minutes], width: .abbreviated))
            return (dateRange, "\(start.timeText) – \(end.timeText) · \(length)")
        }
    }

    private static func joinTitle(for url: URL) -> String {
        url.host() == "meet.google.com" ? "Join Google Meet" : "Join Video Call"
    }

    private static func displayAddress(of url: URL) -> String {
        (url.host() ?? "") + url.path()
    }

    private static func mapsURL(for location: String) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "maps.apple.com"
        components.path = "/"
        components.queryItems = [URLQueryItem(name: "q", value: location)]
        return components.url!
    }
}

extension DeletionScope {
    fileprivate var title: String {
        switch self {
        case .thisEvent: "This Event"
        case .thisAndFollowing: "This and Following Events"
        case .allEvents: "All Events"
        }
    }
}

extension Attendance {
    fileprivate var tint: Color {
        switch self {
        case .accepted: .green
        case .tentative: .orange
        case .declined: .red
        case .needsAction: .secondary
        }
    }
}
