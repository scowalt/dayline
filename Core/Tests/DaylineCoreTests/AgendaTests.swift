import DaylineCore
import Foundation
import Testing

struct AgendaTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()

    func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    func timed(_ id: String, _ start: Date, _ end: Date, title: String? = nil, meet: Bool = false) -> CalendarEvent {
        CalendarEvent(
            id: EventID(calendar: CalendarID(rawValue: "work"), event: id),
            title: title ?? id,
            time: .timed(start: start, end: end),
            conferenceURL: meet ? URL(string: "https://meet.google.com/abc-defg-hij") : nil
        )
    }

    func allDay(_ id: String, _ first: CivilDate, _ last: CivilDate) -> CalendarEvent {
        CalendarEvent(id: EventID(calendar: CalendarID(rawValue: "work"), event: id), title: id, time: .allDay(first: first, last: last))
    }

    func day(_ month: Int, _ day: Int) -> CivilDate {
        CivilDate(year: 2026, month: month, day: day)
    }

    func layout(_ days: [AgendaDay]) -> [String: [String]] {
        Dictionary(uniqueKeysWithValues: days.map { ($0.date.isoString, $0.allDay.map(\.id.event) + $0.timed.map(\.id.event)) })
    }

    @Test func everyDayInTheRangeIsListedEvenWhenEmpty() {
        let days = Agenda.days(events: [timed("lunch", at(2026, 11, 21, 12), at(2026, 11, 21, 13))], from: day(11, 20), through: day(11, 22), calendar: calendar)

        #expect(days.map(\.date) == [day(11, 20), day(11, 21), day(11, 22)])
        #expect(days.map(\.isEmpty) == [true, false, true])
    }

    @Test func aReversedRangeHasNoDays() {
        #expect(Agenda.days(events: [], from: day(11, 22), through: day(11, 20), calendar: calendar).isEmpty)
    }

    @Test func timedEventCrossingMidnightAppearsOnBothDays() {
        let late = timed("late", at(2026, 11, 20, 22, 30), at(2026, 11, 21, 1))
        let days = Agenda.days(events: [late], from: day(11, 20), through: day(11, 22), calendar: calendar)

        #expect(layout(days) == ["2026-11-20": ["late"], "2026-11-21": ["late"], "2026-11-22": []])
        #expect(late.time.portion(on: day(11, 20), in: calendar) == .startsThisDay(start: at(2026, 11, 20, 22, 30), end: at(2026, 11, 21, 1)))
        #expect(late.time.portion(on: day(11, 21), in: calendar) == .endsThisDay(end: at(2026, 11, 21, 1)))
    }

    @Test func eventEndingExactlyAtMidnightStaysOnItsDay() {
        let event = timed("evening", at(2026, 11, 20, 23), at(2026, 11, 21))
        let days = Agenda.days(events: [event], from: day(11, 20), through: day(11, 21), calendar: calendar)

        #expect(layout(days) == ["2026-11-20": ["evening"], "2026-11-21": []])
        #expect(event.time.portion(on: day(11, 20), in: calendar) == .within(start: at(2026, 11, 20, 23), end: at(2026, 11, 21)))
    }

    @Test func zeroLengthEventAtMidnightAppearsOnThatDay() {
        let reminder = timed("reminder", at(2026, 11, 21), at(2026, 11, 21))
        let days = Agenda.days(events: [reminder], from: day(11, 20), through: day(11, 21), calendar: calendar)

        #expect(layout(days) == ["2026-11-20": [], "2026-11-21": ["reminder"]])
    }

    @Test func timedEventSpanningSeveralDaysCoversTheMiddleDay() {
        let conference = timed("conference", at(2026, 11, 20, 9), at(2026, 11, 22, 17))
        let days = Agenda.days(events: [conference], from: day(11, 19), through: day(11, 23), calendar: calendar)

        #expect(layout(days) == ["2026-11-19": [], "2026-11-20": ["conference"], "2026-11-21": ["conference"], "2026-11-22": ["conference"], "2026-11-23": []])
        #expect(conference.time.portion(on: day(11, 21), in: calendar) == .coversThisDay)
    }

    @Test func allDaySpansAreClippedToTheRange() {
        let trip = allDay("trip", day(11, 18), day(11, 21))
        let earlier = allDay("earlier", day(11, 10), day(11, 19))
        let later = allDay("later", day(11, 23), day(11, 25))
        let days = Agenda.days(events: [trip, earlier, later], from: day(11, 20), through: day(11, 22), calendar: calendar)

        #expect(layout(days) == ["2026-11-20": ["trip"], "2026-11-21": ["trip"], "2026-11-22": []])
        #expect(trip.time.portion(on: day(11, 20), in: calendar) == .allDay(day: 3, of: 4))
        #expect(trip.time.portion(on: day(11, 21), in: calendar) == .allDay(day: 4, of: 4))
    }

    @Test func daylightSavingStartKeepsCivilDays() {
        let overnight = timed("overnight", at(2026, 3, 7, 23), at(2026, 3, 8, 4))
        let shortDay = allDay("holiday", day(3, 8), day(3, 8))
        let toMidnight = timed("late", at(2026, 3, 8, 23, 30), at(2026, 3, 9))
        let days = Agenda.days(events: [overnight, shortDay, toMidnight], from: day(3, 7), through: day(3, 9), calendar: calendar)

        #expect(days.map(\.date) == [day(3, 7), day(3, 8), day(3, 9)])
        #expect(layout(days) == ["2026-03-07": ["overnight"], "2026-03-08": ["holiday", "overnight", "late"], "2026-03-09": []])
        #expect(overnight.time.portion(on: day(3, 8), in: calendar) == .endsThisDay(end: at(2026, 3, 8, 4)))
    }

    @Test func daylightSavingEndKeepsTheLongDayWhole() {
        let early = timed("early", at(2026, 11, 1, 0, 30), at(2026, 11, 1, 3))
        let wholeDay = timed("whole", at(2026, 11, 1), at(2026, 11, 2))
        let days = Agenda.days(events: [early, wholeDay], from: day(10, 31), through: day(11, 2), calendar: calendar)

        #expect(layout(days) == ["2026-10-31": [], "2026-11-01": ["whole", "early"], "2026-11-02": []])
        #expect(wholeDay.time.portion(on: day(11, 1), in: calendar) == .coversThisDay)
        #expect(early.time.portion(on: day(11, 1), in: calendar) == .within(start: at(2026, 11, 1, 0, 30), end: at(2026, 11, 1, 3)))
    }

    @Test func timedEventsSortByStartThenEndThenTitle() {
        let nine = at(2026, 11, 20, 9)
        let events = [
            timed("c", nine, at(2026, 11, 20, 10), title: "Zebra"),
            timed("d", at(2026, 11, 20, 8), at(2026, 11, 20, 12), title: "Yak"),
            timed("b", nine, at(2026, 11, 20, 10), title: "Alpaca"),
            timed("a", nine, at(2026, 11, 20, 9, 30), title: "Moose"),
        ]
        let days = Agenda.days(events: events, from: day(11, 20), through: day(11, 20), calendar: calendar)

        #expect(days.first?.timed.map(\.title) == ["Yak", "Moose", "Alpaca", "Zebra"])
    }

    @Test func allDayEventsListBeforeTimedOnesWithLongerSpansFirst() {
        let events = [
            timed("standup", at(2026, 11, 20, 9), at(2026, 11, 20, 9, 15)),
            allDay("trash", day(11, 20), day(11, 20)),
            allDay("trip", day(11, 20), day(11, 22)),
            allDay("move", day(11, 19), day(11, 20)),
        ]
        let days = Agenda.days(events: events, from: day(11, 20), through: day(11, 20), calendar: calendar)

        #expect(layout(days) == ["2026-11-20": ["move", "trip", "trash", "standup"]])
    }

    @Test func startedCountMarksWhereNowFallsAmongTimedEvents() {
        let events = [
            timed("focus", at(2026, 11, 20, 8), at(2026, 11, 20, 9, 30)),
            timed("standup", at(2026, 11, 20, 9, 30), at(2026, 11, 20, 9, 45)),
            timed("review", at(2026, 11, 20, 11), at(2026, 11, 20, 12)),
        ]
        let today = Agenda.days(events: events, from: day(11, 20), through: day(11, 20), calendar: calendar)[0]

        #expect(today.startedCount(at: at(2026, 11, 20, 7), calendar: calendar) == 0)
        #expect(today.startedCount(at: at(2026, 11, 20, 9, 30), calendar: calendar) == 2)
        #expect(today.startedCount(at: at(2026, 11, 20, 10), calendar: calendar) == 2)
        #expect(today.startedCount(at: at(2026, 11, 20, 13), calendar: calendar) == 3)
    }

    @Test func joinOpensTenMinutesBeforeStartAndClosesAtEnd() {
        let call = timed("call", at(2026, 11, 20, 11), at(2026, 11, 20, 12), meet: true)
        let inPerson = timed("room", at(2026, 11, 20, 11), at(2026, 11, 20, 12))

        #expect(!call.isJoinable(at: at(2026, 11, 20, 10, 49), calendar: calendar))
        #expect(call.isJoinable(at: at(2026, 11, 20, 10, 50), calendar: calendar))
        #expect(call.isJoinable(at: at(2026, 11, 20, 11, 59), calendar: calendar))
        #expect(!call.isJoinable(at: at(2026, 11, 20, 12), calendar: calendar))
        #expect(!inPerson.isJoinable(at: at(2026, 11, 20, 11, 30), calendar: calendar))
    }

    @Test func eventsEndAtTheirEndTime() {
        let call = timed("call", at(2026, 11, 20, 11), at(2026, 11, 20, 12))

        #expect(!call.hasEnded(at: at(2026, 11, 20, 11, 59), calendar: calendar))
        #expect(call.hasEnded(at: at(2026, 11, 20, 12), calendar: calendar))
    }
}
