import DaylineCore
import Foundation
import Testing

struct GoogleCalendarAPITests {
    let primary = CalendarID(rawValue: "alex.rivera@example.com")
    let newYork: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }()

    @Test func windowRunsFromLocalMidnightForFourteenDaysAcrossDaylightSaving() {
        let window = GoogleCalendarAPI.window(containing: utc(2026, 11, 1, 14, 0), in: newYork)
        #expect(window.start == utc(2026, 11, 1, 4, 0))
        #expect(window.end == utc(2026, 11, 15, 5, 0))
    }

    @Test func calendarListRequestPagesThroughTheUsersCalendars() {
        let first = GoogleCalendarAPI.calendarListRequest(pageToken: nil)
        #expect(first.method == .get)
        #expect(first.url.absoluteString == "https://www.googleapis.com/calendar/v3/users/me/calendarList?maxResults=250")

        let next = GoogleCalendarAPI.calendarListRequest(pageToken: "p2+/==")
        #expect(next.url.absoluteString == "https://www.googleapis.com/calendar/v3/users/me/calendarList?maxResults=250&pageToken=p2%2B%2F%3D%3D")
    }

    @Test func eventsRequestExpandsRecurrencesWithinTheWindow() throws {
        let window = DateInterval(start: utc(2026, 11, 20, 5, 0), end: utc(2026, 12, 4, 5, 0))
        let request = GoogleCalendarAPI.eventsRequest(
            calendar: CalendarID(rawValue: "en.usa#holiday@group.v.calendar.google.com"),
            window: window,
            pageToken: "p3+/=="
        )
        let components = try #require(URLComponents(url: request.url, resolvingAgainstBaseURL: false))

        #expect(request.method == .get)
        #expect(components.host == "www.googleapis.com")
        #expect(components.percentEncodedPath == "/calendar/v3/calendars/en.usa%23holiday%40group.v.calendar.google.com/events")
        #expect(components.path == "/calendar/v3/calendars/en.usa#holiday@group.v.calendar.google.com/events")
        #expect(Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") }) == [
            "singleEvents": "true",
            "orderBy": "startTime",
            "timeMin": "2026-11-20T05:00:00Z",
            "timeMax": "2026-12-04T05:00:00Z",
            "maxResults": "2500",
            "pageToken": "p3+/==",
        ])
        #expect(components.percentEncodedQuery?.contains("+") == false)
    }

    @Test func calendarListDecodesTitlesSelectionAndGoogleUIColors() throws {
        let first = try GoogleCalendarAPI.calendarListPage(from: GoogleFixtures.response(GoogleFixtures.calendarListFirstPage))
        #expect(first.nextPageToken == "calendars-p2")
        #expect(first.items == [
            CalendarInfo(id: primary, title: "alex.rivera@example.com", color: RGBColor(hex: "#4285F4")!, isPrimary: true, isSelectedInGoogle: true),
            CalendarInfo(id: CalendarID(rawValue: "c_8f1b2a90d3e44c1e@group.calendar.google.com"), title: "Team", color: RGBColor(hex: "#0B8043")!, isPrimary: false, isSelectedInGoogle: true),
            CalendarInfo(id: CalendarID(rawValue: "en.usa#holiday@group.v.calendar.google.com"), title: "Holidays in United States", color: RGBColor(hex: "#b1365f")!, isPrimary: false, isSelectedInGoogle: false),
        ])

        let last = try GoogleCalendarAPI.calendarListPage(from: GoogleFixtures.response(GoogleFixtures.calendarListLastPage))
        #expect(last.nextPageToken == nil)
        #expect(last.items == [
            CalendarInfo(id: CalendarID(rawValue: "addressbook#contacts@group.v.calendar.google.com"), title: "Birthdays", color: RGBColor(hex: "#33B679")!, isPrimary: false, isSelectedInGoogle: false),
        ])
    }

    @Test func timedEventsKeepTheirInstantsAttendanceAndConference() throws {
        let page = try GoogleCalendarAPI.eventsPage(from: GoogleFixtures.response(GoogleFixtures.eventsFirstPage), calendar: primary)
        #expect(page.nextPageToken == "events-p2")
        let events = Dictionary(uniqueKeysWithValues: page.items.map { ($0.id.event, $0) })
        #expect(events.count == 5)

        #expect(events["5qk8c1v3f0d2t9n6e4m7b1a0s8"] == CalendarEvent(
            id: EventID(calendar: primary, event: "5qk8c1v3f0d2t9n6e4m7b1a0s8"),
            title: "Design review: onboarding",
            time: .timed(start: utc(2026, 11, 20, 16, 0), end: utc(2026, 11, 20, 17, 0)),
            location: "Room 4B",
            notes: "Agenda:\n\n• Flows\n• Copy\nSpec: Onboarding spec (https://docs.example.com/d/123?a=1&b=2)\nTom & Jerry attend <both> — see https://example.com/x",
            conferenceURL: URL(string: "https://meet.google.com/kmn-opqr-stu"),
            webURL: URL(string: "https://www.google.com/calendar/event?eid=NXFrOGMxdjNmMGQydDluNmU0bTdiMWEwczggYWxleC5yaXZlcmFAZXhhbXBsZS5jb20"),
            color: RGBColor(hex: "#D50000"),
            attendance: .accepted,
            attendeeCount: 3
        ))

        let zoom = try #require(events["zoomsync01"])
        #expect(zoom.time == .timed(start: utc(2026, 11, 20, 15, 30), end: utc(2026, 11, 20, 16, 0)))
        #expect(zoom.conferenceURL == URL(string: "https://us02web.zoom.us/j/81234567890?pwd=abc"))
        #expect(zoom.attendance == .tentative)
        #expect(zoom.color == nil)
        #expect(zoom.notes == "Join Zoom Meeting\nhttps://us02web.zoom.us/j/81234567890?pwd=abc\n\nMeeting ID: 812 3456 7890\n\nOne tap mobile <tel:+16465588656,,81234567890#>")

        let tokyo = try #require(events["legacyhangout"])
        #expect(tokyo.title == "Weekly sync")
        #expect(tokyo.time == .timed(start: utc(2026, 11, 20, 14, 30), end: utc(2026, 11, 20, 15, 30)))
        #expect(tokyo.conferenceURL == URL(string: "https://meet.google.com/abc-defg-hij"))
        #expect(tokyo.attendance == .needsAction)
        #expect(tokyo.attendeeCount == 3)

        let busy = try #require(events["busyblock"])
        #expect(busy.title == GoogleCalendarAPI.untitledEvent)
        #expect(busy.attendance == .declined)
        #expect(busy.conferenceURL == nil)

        #expect(events["blanktitle"] == CalendarEvent(
            id: EventID(calendar: primary, event: "blanktitle"),
            title: "(No title)",
            time: .timed(start: utc(2026, 11, 22, 15, 0), end: utc(2026, 11, 22, 15, 0))
        ))
    }

    @Test func allDayEndDatesBecomeInclusiveAndCancelledOrWorkingLocationEventsDisappear() throws {
        let page = try GoogleCalendarAPI.eventsPage(from: GoogleFixtures.response(GoogleFixtures.eventsLastPage), calendar: primary)
        #expect(page.nextPageToken == nil)
        let events = Dictionary(uniqueKeysWithValues: page.items.map { ($0.id.event, $0) })

        #expect(Set(events.keys) == ["trashnight_20261120", "portlandtrip", "redeye", "ooo"])
        #expect(events["trashnight_20261120"]?.time == .allDay(first: CivilDate(year: 2026, month: 11, day: 20), last: CivilDate(year: 2026, month: 11, day: 20)))
        #expect(events["trashnight_20261120"]?.color == RGBColor(hex: "#F6BF26"))
        #expect(events["portlandtrip"]?.time == .allDay(first: CivilDate(year: 2026, month: 11, day: 30), last: CivilDate(year: 2026, month: 12, day: 2)))
        #expect(events["redeye"]?.time == .timed(start: utc(2026, 12, 3, 6, 15), end: utc(2026, 12, 3, 11, 40)))
        #expect(events["ooo"]?.time == .timed(start: utc(2026, 11, 27, 5, 0), end: utc(2026, 11, 28, 5, 0)))
    }

    @Test func apiErrorsDistinguishExpiredAccessFromOtherFailures() {
        #expect(throws: GoogleError.unauthorized) {
            try GoogleCalendarAPI.calendarListPage(from: GoogleFixtures.response(GoogleFixtures.unauthenticated, status: 401))
        }
        #expect(throws: GoogleError.server(status: 403, message: "Rate Limit Exceeded")) {
            try GoogleCalendarAPI.eventsPage(from: GoogleFixtures.response(GoogleFixtures.rateLimited, status: 403), calendar: primary)
        }
        #expect(throws: GoogleError.malformedResponse) {
            try GoogleCalendarAPI.eventsPage(from: GoogleFixtures.response(#"{"items": {"id": 1}}"#), calendar: primary)
        }
    }

    private func utc(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
}
