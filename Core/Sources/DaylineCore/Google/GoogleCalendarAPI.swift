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
                access: entry.accessRole.flatMap(CalendarAccess.init(rawValue:)) ?? .freeBusyReader
            )
        }
        return Page(items: calendars, nextPageToken: body.nextPageToken)
    }

    public static func rescheduleRequest(_ event: EventID, to time: EventTime, notifyGuests: Bool) -> HTTPRequest {
        let url = eventURL(event).appendingQuery(sendUpdates(notifyGuests))
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

    public static func deleteRequest(_ event: EventID, notifyGuests: Bool) -> HTTPRequest {
        HTTPRequest(method: .delete, url: eventURL(event).appendingQuery(sendUpdates(notifyGuests)))
    }

    public static func eventRequest(_ event: EventID) -> HTTPRequest {
        .get(eventURL(event))
    }

    public static func followingDeletionRequest(series: EventID, from start: OccurrenceStart, master response: HTTPResponse, notifyGuests: Bool) throws(GoogleError) -> HTTPRequest {
        let master = try decode(SeriesBody.self, from: response)
        guard let firstStart = occurrenceStart(master.start), let recurrence = master.recurrence else { throw .malformedResponse }
        guard firstStart < start else { return deleteRequest(series, notifyGuests: notifyGuests) }
        let url = eventURL(series).appendingQuery(sendUpdates(notifyGuests))
        return .json(.patch, url, body: TruncateBody(recurrence: recurrence.map { ending($0, until: until(before: start)) }))
    }

    public static func deletionResult(from response: HTTPResponse) throws(GoogleError) {
        guard response.isSuccess || response.status == 410 else { throw GoogleError(apiResponse: response) }
    }

    private static func eventURL(_ event: EventID) -> URL {
        base.appendingPathSegment("calendars").appendingPathSegment(event.calendar.rawValue)
            .appendingPathSegment("events").appendingPathSegment(event.event)
    }

    private static func sendUpdates(_ notifyGuests: Bool) -> [(String, String)] {
        [("sendUpdates", notifyGuests ? "all" : "none")]
    }

    private static func until(before start: OccurrenceStart) -> String {
        switch start {
        case .day(let day):
            return day.adding(days: -1, in: civil).isoString.replacing("-", with: "")
        case .moment(let date):
            let parts = civil.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date.addingTimeInterval(-1))
            return String(format: "%04d%02d%02dT%02d%02d%02dZ", parts.year!, parts.month!, parts.day!, parts.hour!, parts.minute!, parts.second!)
        }
    }

    private static func ending(_ line: String, until: String) -> String {
        guard line.uppercased().hasPrefix("RRULE:") else { return line }
        let parts = line.dropFirst("RRULE:".count).split(separator: ";").filter { part in
            let name = part.prefix { $0 != "=" }.uppercased()
            return name != "UNTIL" && name != "COUNT"
        }
        return "RRULE:" + (parts.map(String.init) + ["UNTIL=\(until)"]).joined(separator: ";")
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
        guard item.status != "cancelled", item.eventType != "workingLocation", let time = time(start: item.start, end: item.end, eventType: item.eventType) else { return nil }
        let attendees = item.attendees ?? []
        let videoEntry = item.conferenceData?.entryPoints?.first { $0.entryPointType == "video" }?.uri
        let isFixedType = fixedEventTypes.contains(item.eventType ?? "default")
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
                && !isFixedType,
            occurrence: occurrence(series: item.recurringEventId, originalStart: item.originalStartTime, calendar: calendar.id),
            isOrganizer: item.organizer?.isSelf == true,
            canDelete: calendar.canEditEvents && !isFixedType
        )
    }

    private static func occurrence(series: String?, originalStart: EventsBody.Time?, calendar: CalendarID) -> Occurrence? {
        guard let series, let start = occurrenceStart(originalStart) else { return nil }
        return Occurrence(series: EventID(calendar: calendar, event: series), originalStart: start)
    }

    private static func occurrenceStart(_ time: EventsBody.Time?) -> OccurrenceStart? {
        if let dateTime = time?.dateTime.flatMap(parseDate) {
            return .moment(dateTime)
        }
        return time?.date.flatMap(CivilDate.init(isoString:)).map(OccurrenceStart.day)
    }

    private static func googleAllDayOutOfOffice(start: EventsBody.Time?, end: EventsBody.Time?) -> EventTime? {
        guard let first = start?.dateTime.flatMap(midnightDate), let end = end?.dateTime.flatMap(midnightDate), end > first else { return nil }
        return .allDay(first: first, last: end.adding(days: -1, in: civil))
    }

    private static func midnightDate(_ dateTime: String) -> CivilDate? {
        let parts = dateTime.split(separator: "T", maxSplits: 1)
        guard parts.count == 2, parts[1].hasPrefix("00:00:00") else { return nil }
        return CivilDate(isoString: String(parts[0]))
    }

    private static func time(start: EventsBody.Time?, end: EventsBody.Time?, eventType: String?) -> EventTime? {
        if eventType == "outOfOffice", let days = googleAllDayOutOfOffice(start: start, end: end) {
            return days
        }
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
        var recurringEventId: String?
        var originalStartTime: Time?
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

private struct SeriesBody: Decodable {
    var start: EventsBody.Time?
    var recurrence: [String]?
}

private struct TruncateBody: Encodable {
    var recurrence: [String]
}

private struct RescheduleBody: Encodable {
    struct Time: Encodable {
        var date: String?
        var dateTime: String?
    }

    var start: Time
    var end: Time
}
