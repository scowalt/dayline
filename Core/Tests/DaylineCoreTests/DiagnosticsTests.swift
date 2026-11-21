import DaylineCore
import Foundation
import Testing

struct DiagnosticsTests {
    let now = Date(timeIntervalSince1970: 1_795_190_400)
    let holidays = HTTPRequest.get(URL(string: "https://www.googleapis.com/calendar/v3/calendars/en.usa%23holiday%40group.v.calendar.google.com/events")!)
    let token = HTTPRequest.form(URL(string: "https://oauth2.googleapis.com/token")!, fields: [("grant_type", "refresh_token")])

    @Test func aFailedAPIRequestNamesTheCalendarStatusAndGoogleReason() {
        let line = Diagnostics.line(for: holidays, response: GoogleFixtures.response(GoogleFixtures.rateLimited, status: 403), elapsed: .milliseconds(231))

        #expect(line == "GET /calendar/v3/calendars/en.usa#holiday@group.v.calendar.google.com/events → 403 in 231 ms: Rate Limit Exceeded (rateLimitExceeded)")
    }

    @Test func aFailedTokenRefreshShowsGooglesOAuthError() {
        let line = Diagnostics.line(for: token, response: GoogleFixtures.response(GoogleFixtures.invalidGrant, status: 400), elapsed: .milliseconds(80))

        #expect(line == "POST /token → 400 in 80 ms: invalid_grant: Token has been expired or revoked.")
    }

    @Test func aSuccessfulTokenRefreshLeavesTheTokenOut() {
        let line = Diagnostics.line(for: token, response: GoogleFixtures.response(GoogleFixtures.refreshed), elapsed: .milliseconds(80))

        #expect(line == "POST /token → 200 in 80 ms")
    }

    @Test func aRequestThatNeverGotAResponseShowsTheError() {
        #expect(Diagnostics.line(for: holidays, failure: "offline", elapsed: .seconds(20)) == "GET /calendar/v3/calendars/en.usa#holiday@group.v.calendar.google.com/events failed in 20000 ms: offline")
    }

    @Test func theReportListsEachAccountsCalendarsWithAccessAndOwnerButNoEventTitles() {
        let work = Account(email: "me@work.example")
        let personal = Account(email: "me@gmail.com")
        let color = RGBColor(red: 0, green: 0, blue: 0)
        let workCalendar = CalendarInfo(id: CalendarID(rawValue: work.email), title: work.email, color: color, isPrimary: true, isSelectedInGoogle: true, access: .owner)
        let personalCopy = CalendarInfo(id: CalendarID(rawValue: personal.email), title: personal.email, color: color, isPrimary: false, isSelectedInGoogle: false, access: .freeBusyReader)
        let personalCalendar = CalendarInfo(id: CalendarID(rawValue: personal.email), title: personal.email, color: color, isPrimary: true, isSelectedInGoogle: true, access: .owner)
        let snapshot = Snapshot(
            accounts: [
                AccountSnapshot(account: work, calendars: [workCalendar, personalCopy], events: [
                    CalendarEvent(id: EventID(calendar: workCalendar.id, event: "1"), title: "Secret project", time: .timed(start: now, end: now)),
                    CalendarEvent(id: EventID(calendar: personalCopy.id, event: "2"), title: GoogleCalendarAPI.untitledEvent, time: .timed(start: now, end: now)),
                ]),
                AccountSnapshot(account: personal, calendars: [personalCalendar], events: []),
            ],
            range: DateInterval(start: now, duration: 86400),
            fetchedAt: now
        )
        let log = [
            SyncLogEntry(at: now.addingTimeInterval(2), source: "widget", account: personal.email, message: "second"),
            SyncLogEntry(at: now.addingTimeInterval(1), source: "app", account: nil, message: "first"),
        ]

        let report = Diagnostics.report(
            version: "1.0 (7)",
            now: now,
            timeZone: TimeZone(identifier: "America/Los_Angeles")!,
            accounts: [work, personal],
            issues: [personal.email: "failed(\"Google error 404: Not Found\")"],
            snapshot: snapshot,
            outbox: Outbox(),
            visibility: CalendarVisibility(overrides: [personalCalendar.id: true], hiddenTitles: ["Secret project"]),
            log: log
        )

        #expect(report == """
            Dayline 1.0 (7) diagnostics
            Generated 2026-11-20T16:00:00Z in America/Los_Angeles
            Snapshot fetched 2026-11-20T16:00:00Z, covering 2026-11-20T16:00:00Z to 2026-11-21T16:00:00Z

            Account 1: me@work.example
              Issue: none
              2 calendars, 2 events
              - me@work.example <me@work.example> [owner, primary, selected in Google]: 1 events, 0 untitled
              - me@gmail.com <me@gmail.com> [freeBusyReader, not selected in Google, shown in Dayline, listed under me@gmail.com]: 1 events, 1 untitled

            Account 2: me@gmail.com
              Issue: failed("Google error 404: Not Found")
              1 calendars, 0 events
              - me@gmail.com <me@gmail.com> [owner, primary, selected in Google, shown in Dayline]: 0 events, 0 untitled

            1 hidden titles match 1 events

            Queued changes: none

            Sync log, oldest first
            2026-11-20T16:00:01Z app - first
            2026-11-20T16:00:02Z widget me@gmail.com second

            """)
    }

    @Test func theReportListsQueuedChangesWithAgeAndGuestNoticeButNoTitles() {
        let account = Account(email: "me@work.example")
        let calendar = CalendarID(rawValue: "me@work.example")
        let standup = EventID(calendar: calendar, event: "standup")
        var outbox = Outbox()
        outbox.enqueue(PendingChange(account: account.id, change: .move(standup, to: .timed(start: now, end: now)), notifyGuests: false, eventTitle: "Secret project", queuedAt: now.addingTimeInterval(-90)))
        outbox.enqueue(PendingChange(account: account.id, change: .delete(.series(standup)), notifyGuests: true, eventTitle: "Secret project", queuedAt: now.addingTimeInterval(-7_500)))

        let report = Diagnostics.report(
            version: "1.0 (7)",
            now: now,
            timeZone: TimeZone(identifier: "GMT")!,
            accounts: [],
            issues: [:],
            snapshot: nil,
            outbox: outbox,
            visibility: CalendarVisibility(),
            log: []
        )

        #expect(report == """
            Dayline 1.0 (7) diagnostics
            Generated 2026-11-20T16:00:00Z in GMT
            No snapshot

            Queued changes: 2
              - move me@work.example/standup, account me@work.example, queued 2026-11-20T15:58:30Z (1 min ago), notify guests no
              - delete series me@work.example/standup, account me@work.example, queued 2026-11-20T13:55:00Z (2 h 5 min ago), notify guests yes

            Sync log, oldest first

            """)
    }
}
