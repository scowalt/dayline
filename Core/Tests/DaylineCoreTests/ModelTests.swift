import DaylineCore
import Foundation
import Testing

struct ModelTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }()

    @Test func civilDateCrossesMonthAndDaylightSavingBoundaries() {
        let date = CivilDate(year: 2026, month: 10, day: 31)
        #expect(date.adding(days: 1, in: calendar) == CivilDate(year: 2026, month: 11, day: 1))
        #expect(date.adding(days: 2, in: calendar) == CivilDate(year: 2026, month: 11, day: 2))
        #expect(CivilDate(year: 2026, month: 11, day: 1) < CivilDate(year: 2026, month: 11, day: 2))
    }

    @Test func hexColorsParseWithOrWithoutHash() {
        #expect(RGBColor(hex: "#ff0000") == RGBColor(red: 1, green: 0, blue: 0))
        #expect(RGBColor(hex: "00ff00") == RGBColor(red: 0, green: 1, blue: 0))
        #expect(RGBColor(hex: "#fff") == nil)
    }

    @Test func visibilityOverridesGoogleSelection() {
        let shown = CalendarInfo(id: CalendarID(rawValue: "a"), title: "A", color: RGBColor(red: 0, green: 0, blue: 0), isPrimary: true, isSelectedInGoogle: true)
        let hidden = CalendarInfo(id: CalendarID(rawValue: "b"), title: "B", color: RGBColor(red: 0, green: 0, blue: 0), isPrimary: false, isSelectedInGoogle: false)
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let events = [shown, hidden].map {
            CalendarEvent(id: EventID(calendar: $0.id, event: "e"), title: $0.title, time: .timed(start: now, end: now))
        }
        let snapshot = Snapshot(
            accounts: [AccountSnapshot(account: Account(email: "a@b.c"), calendars: [shown, hidden], events: events)],
            range: DateInterval(start: now, duration: 0),
            fetchedAt: now
        )

        #expect(snapshot.events(visibleWith: CalendarVisibility()).map(\.title) == ["A"])
        #expect(snapshot.events(visibleWith: CalendarVisibility(overrides: [hidden.id: true, shown.id: false])).map(\.title) == ["B"])
    }

    @Test func hiddenTitlesRemoveMatchingEventsIgnoringCaseAndSpacing() {
        let work = CalendarInfo(id: CalendarID(rawValue: "a"), title: "Work", color: RGBColor(red: 0, green: 0, blue: 0), isPrimary: true, isSelectedInGoogle: true)
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let events = ["Personal event", "PERSONAL EVENT ", "Personal event with Sam", "Standup"].enumerated().map { index, title in
            CalendarEvent(id: EventID(calendar: work.id, event: "\(index)"), title: title, time: .timed(start: now, end: now))
        }
        let snapshot = Snapshot(
            accounts: [AccountSnapshot(account: Account(email: "a@b.c"), calendars: [work], events: events)],
            range: DateInterval(start: now, duration: 0),
            fetchedAt: now
        )

        var visibility = CalendarVisibility()
        visibility.hide(title: "  personal Event")
        #expect(visibility.hiddenTitles == ["personal Event"])
        #expect(snapshot.events(visibleWith: visibility).map(\.title) == ["Personal event with Sam", "Standup"])

        visibility.show(title: "Personal event")
        #expect(visibility.hiddenTitles.isEmpty)
        #expect(snapshot.events(visibleWith: visibility).count == 4)
    }

    @Test func hidingATitleTwiceOrBlankKeepsOneEntry() {
        var visibility = CalendarVisibility()
        visibility.hide(title: "Personal event")
        visibility.hide(title: "personal event")
        visibility.hide(title: "   ")
        #expect(visibility.hiddenTitles == ["Personal event"])
    }

    @Test func visibilitySavedBeforeHiddenTitlesStillDecodes() throws {
        let saved = Data(#"{"overrides":["a",false]}"#.utf8)
        let visibility = try JSONDecoder().decode(CalendarVisibility.self, from: saved)
        #expect(visibility == CalendarVisibility(overrides: [CalendarID(rawValue: "a"): false]))

        var hiding = visibility
        hiding.hide(title: "Personal event")
        let roundTripped = try JSONDecoder().decode(CalendarVisibility.self, from: JSONEncoder().encode(hiding))
        #expect(roundTripped == hiding)
    }
}

struct MultiAccountSnapshotTests {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    let first = Account(email: "first@example.com")
    let second = Account(email: "second@example.com")
    let third = Account(email: "third@example.com")

    func calendar(_ id: String, title: String? = nil) -> CalendarInfo {
        CalendarInfo(id: CalendarID(rawValue: id), title: title ?? id, color: RGBColor(red: 0, green: 0, blue: 0), isPrimary: false, isSelectedInGoogle: true)
    }

    func event(_ calendar: CalendarInfo, _ id: String, title: String) -> CalendarEvent {
        CalendarEvent(id: EventID(calendar: calendar.id, event: id), title: title, time: .timed(start: now, end: now))
    }

    func snapshot(_ accounts: [AccountSnapshot]) -> Snapshot {
        Snapshot(accounts: accounts, range: DateInterval(start: now, duration: 60), fetchedAt: now)
    }

    var sharedSnapshot: Snapshot {
        let own = calendar("own")
        let shared = calendar("shared", title: "from first")
        let sharedCopy = calendar("shared", title: "from second")
        let other = calendar("other")
        return snapshot([
            AccountSnapshot(
                account: first,
                calendars: [own, shared],
                events: [event(own, "1", title: "own"), event(shared, "2", title: "shared by first")]
            ),
            AccountSnapshot(
                account: second,
                calendars: [sharedCopy, other],
                events: [event(sharedCopy, "2", title: "shared by second"), event(other, "3", title: "other")]
            ),
        ])
    }

    @Test func aSharedCalendarAndItsEventsComeFromTheFirstAccount() {
        let merged = sharedSnapshot

        #expect(merged.calendars.map(\.id.rawValue) == ["own", "shared", "other"])
        #expect(merged.calendar(CalendarID(rawValue: "shared"))?.title == "from first")
        #expect(merged.events.map(\.title) == ["own", "shared by first", "other"])
    }

    @Test func anAccountDoesNotListACalendarAnotherAccountOwns() {
        let merged = sharedSnapshot

        #expect(merged.calendars(of: first.id).map(\.id.rawValue) == ["own", "shared"])
        #expect(merged.calendars(of: second.id).map(\.id.rawValue) == ["other"])
        #expect(merged.calendars(of: third.id).isEmpty)
    }

    @Test func removingTheOwnerHandsTheSharedCalendarToTheNextAccount() {
        let remaining = sharedSnapshot.removing(first.id)

        #expect(remaining.accounts.map(\.account) == [second])
        #expect(remaining.calendar(CalendarID(rawValue: "shared"))?.title == "from second")
        #expect(remaining.events.map(\.title) == ["shared by second", "other"])
        #expect(remaining.fetchedAt == sharedSnapshot.fetchedAt)
    }

    @Test func visibilityAppliesAcrossAccounts() {
        let hidden = CalendarVisibility(overrides: [CalendarID(rawValue: "shared"): false])

        #expect(sharedSnapshot.events(visibleWith: hidden).map(\.title) == ["own", "other"])
    }

    @Test func theSampleSharesTheFamilyCalendarAcrossTwoAccounts() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let sample = Snapshot.sample(now: now, calendar: calendar)
        let family = CalendarID(rawValue: "family@group.calendar.google.com")

        #expect(sample.accounts.count == 2)
        #expect(sample.accounts.filter { $0.calendars.contains { $0.id == family } }.count == 2)
        #expect(sample.calendars.filter { $0.id == family }.count == 1)
        #expect(Set(sample.events.map(\.id)).count == sample.events.count)
    }

    @Test func onlyAccountsRangeAndFetchTimeAreEncoded() throws {
        let data = try JSONEncoder().encode(sharedSnapshot)
        let keys = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any]).keys

        #expect(Set(keys) == ["accounts", "range", "fetchedAt"])
        #expect(try JSONDecoder().decode(Snapshot.self, from: data) == sharedSnapshot)
    }
}
