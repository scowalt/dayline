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
        let snapshot = Snapshot(account: Account(email: "a@b.c"), calendars: [shown, hidden], events: events, range: DateInterval(start: now, duration: 0), fetchedAt: now)

        #expect(snapshot.events(visibleWith: CalendarVisibility()).map(\.title) == ["A"])
        #expect(snapshot.events(visibleWith: CalendarVisibility(overrides: [hidden.id: true, shown.id: false])).map(\.title) == ["B"])
    }
}
