import Foundation

public struct Page<Item: Sendable>: Sendable {
    public var items: [Item]
    public var nextPageToken: String?
}

public enum GoogleCalendarAPI {
    public static let windowDays = 14
    public static let untitledEvent = "(No title)"

    private static let base = URL(string: "https://www.googleapis.com/calendar/v3")!
    private static let civil: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    public static func window(containing now: Date, in calendar: Calendar) -> DateInterval {
        let today = CivilDate(now, in: calendar)
        return DateInterval(start: today.start(in: calendar), end: today.adding(days: windowDays, in: calendar).start(in: calendar))
    }

    public static func calendarListRequest(pageToken: String?) -> HTTPRequest {
        .get(base.appendingPathSegment("users").appendingPathSegment("me").appendingPathSegment("calendarList"), query: [
            ("maxResults", "250"),
        ] + pageQuery(pageToken))
    }

    public static func eventsRequest(calendar: CalendarID, window: DateInterval, pageToken: String?) -> HTTPRequest {
        .get(base.appendingPathSegment("calendars").appendingPathSegment(calendar.rawValue).appendingPathSegment("events"), query: [
            ("singleEvents", "true"),
            ("orderBy", "startTime"),
            ("timeMin", window.start.formatted(.iso8601)),
            ("timeMax", window.end.formatted(.iso8601)),
            ("maxResults", "2500"),
        ] + pageQuery(pageToken))
    }

    public static func calendarListPage(from response: HTTPResponse) throws(GoogleError) -> Page<CalendarInfo> {
        let body = try decode(CalendarListBody.self, from: response)
        let calendars = (body.items ?? []).filter { $0.deleted != true }.map { entry in
            CalendarInfo(
                id: CalendarID(rawValue: entry.id),
                title: entry.summaryOverride ?? entry.summary ?? entry.id,
                color: GoogleColors.calendar(colorID: entry.colorId, background: entry.backgroundColor),
                isPrimary: entry.primary == true,
                isSelectedInGoogle: entry.selected == true,
                canEditEvents: entry.accessRole == "owner" || entry.accessRole == "writer"
            )
        }
        return Page(items: calendars, nextPageToken: body.nextPageToken)
    }

    public static func rescheduleRequest(_ event: EventID, to time: EventTime, notifyGuests: Bool) -> HTTPRequest {
        let url = base.appendingPathSegment("calendars").appendingPathSegment(event.calendar.rawValue)
            .appendingPathSegment("events").appendingPathSegment(event.event)
            .appendingQuery([("sendUpdates", notifyGuests ? "all" : "none")])
        let body: RescheduleBody = switch time {
        case .timed(let start, let end):
            RescheduleBody(start: .init(dateTime: start.formatted(.iso8601)), end: .init(dateTime: end.formatted(.iso8601)))
        case .allDay(let first, let last):
            RescheduleBody(start: .init(date: first.isoString), end: .init(date: last.adding(days: 1, in: civil).isoString))
        }
        return .json(.patch, url, body: body)
    }

    public static func rescheduleResult(from response: HTTPResponse) throws(GoogleError) {
        guard response.isSuccess else { throw GoogleError(apiResponse: response) }
    }

    public static func eventsPage(from response: HTTPResponse, calendar: CalendarInfo) throws(GoogleError) -> Page<CalendarEvent> {
        let body = try decode(EventsBody.self, from: response)
        let events = (body.items ?? []).compactMap { event(from: $0, calendar: calendar) }
        return Page(items: events, nextPageToken: body.nextPageToken)
    }

    private static func pageQuery(_ pageToken: String?) -> [(String, String)] {
        pageToken.map { [("pageToken", $0)] } ?? []
    }

    private static func decode<Body: Decodable>(_ type: Body.Type, from response: HTTPResponse) throws(GoogleError) -> Body {
        guard response.isSuccess else { throw GoogleError(apiResponse: response) }
        return try GoogleJSON.decode(type, from: response.body)
    }

    private static let fixedEventTypes: Set<String> = ["birthday", "fromGmail"]

    private static func event(from item: EventsBody.Item, calendar: CalendarInfo) -> CalendarEvent? {
        guard item.status != "cancelled", item.eventType != "workingLocation", let time = time(start: item.start, end: item.end) else { return nil }
        let attendees = item.attendees ?? []
        let videoEntry = item.conferenceData?.entryPoints?.first { $0.entryPointType == "video" }?.uri
        return CalendarEvent(
            id: EventID(calendar: calendar.id, event: item.id),
            title: item.summary.flatMap(nonBlank) ?? untitledEvent,
            time: time,
            location: item.location.flatMap(nonBlank),
            notes: item.description.flatMap(EventDescription.plainText),
            conferenceURL: (videoEntry ?? item.hangoutLink).flatMap(URL.init(string:)),
            webURL: item.htmlLink.flatMap(URL.init(string:)),
            color: GoogleColors.event(colorID: item.colorId),
            attendance: attendees.first { $0.isSelf == true }?.responseStatus.flatMap(Attendance.init(rawValue:)),
            attendeeCount: attendees.filter { $0.resource != true }.count,
            canReschedule: calendar.canEditEvents
                && (item.organizer?.isSelf == true || item.guestsCanModify == true)
                && item.locked != true
                && !fixedEventTypes.contains(item.eventType ?? "default")
        )
    }

    private static func time(start: EventsBody.Time?, end: EventsBody.Time?) -> EventTime? {
        if let start = start?.dateTime.flatMap(parseDate), let end = end?.dateTime.flatMap(parseDate) {
            return .timed(start: start, end: end)
        }
        guard let first = start?.date.flatMap(CivilDate.init(isoString:)) else { return nil }
        let last = end?.date.flatMap(CivilDate.init(isoString:)).map { $0.adding(days: -1, in: civil) } ?? first
        return .allDay(first: first, last: max(first, last))
    }

    private static func parseDate(_ text: String) -> Date? {
        try? Date(text, strategy: .iso8601)
    }

    private static func nonBlank(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct CalendarListBody: Decodable {
    struct Entry: Decodable {
        var id: String
        var summary: String?
        var summaryOverride: String?
        var colorId: String?
        var backgroundColor: String?
        var primary: Bool?
        var selected: Bool?
        var deleted: Bool?
        var accessRole: String?
    }

    var items: [Entry]?
    var nextPageToken: String?
}

private struct EventsBody: Decodable {
    struct Item: Decodable {
        var id: String
        var status: String?
        var eventType: String?
        var summary: String?
        var description: String?
        var location: String?
        var htmlLink: String?
        var colorId: String?
        var start: Time?
        var end: Time?
        var attendees: [Attendee]?
        var conferenceData: Conference?
        var hangoutLink: String?
        var organizer: Organizer?
        var guestsCanModify: Bool?
        var locked: Bool?
    }

    struct Organizer: Decodable {
        enum CodingKeys: String, CodingKey {
            case isSelf = "self"
        }

        var isSelf: Bool?
    }

    struct Time: Decodable {
        var date: String?
        var dateTime: String?
    }

    struct Attendee: Decodable {
        enum CodingKeys: String, CodingKey {
            case isSelf = "self"
            case resource
            case responseStatus
        }

        var isSelf: Bool?
        var resource: Bool?
        var responseStatus: String?
    }

    struct Conference: Decodable {
        var entryPoints: [EntryPoint]?
    }

    struct EntryPoint: Decodable {
        var entryPointType: String?
        var uri: String?
    }

    var items: [Item]?
    var nextPageToken: String?
}

private struct RescheduleBody: Encodable {
    struct Time: Encodable {
        var date: String?
        var dateTime: String?
    }

    var start: Time
    var end: Time
}
