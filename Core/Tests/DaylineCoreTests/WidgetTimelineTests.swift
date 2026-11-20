import DaylineCore
import Foundation
import Testing

struct WidgetTimelineTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()

    let friday = CivilDate(year: 2026, month: 11, day: 20)
    let saturday = CivilDate(year: 2026, month: 11, day: 21)
    let day: TimeInterval = 24 * 60 * 60

    func time(_ date: CivilDate, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: date.year, month: date.month, day: date.day, hour: hour, minute: minute))!
    }

    func timed(_ title: String, _ start: Date, minutes: Int, attendance: Attendance? = nil) -> CalendarEvent {
        CalendarEvent(
            id: EventID(calendar: CalendarID(rawValue: "work"), event: title),
            title: title,
            time: .timed(start: start, end: start.addingTimeInterval(TimeInterval(minutes * 60))),
            attendance: attendance
        )
    }

    func allDay(_ title: String, _ first: CivilDate, through last: CivilDate? = nil) -> CalendarEvent {
        CalendarEvent(
            id: EventID(calendar: CalendarID(rawValue: "home"), event: title),
            title: title,
            time: .allDay(first: first, last: last ?? first)
        )
    }

    @Test func overlappingEventsAreAllInProgressAndTheLatestStartedLeads() {
        let review = timed("Design review", time(friday, 11), minutes: 60)
        let sync = timed("Interview sync", time(friday, 11, 30), minutes: 30)
        let lunch = timed("Lunch", time(friday, 12, 30), minutes: 60)

        let glance = WidgetTimeline.glance(events: [lunch, sync, review], at: time(friday, 11, 45), calendar: calendar)

        #expect(glance.inProgress.map(\.title) == ["Design review", "Interview sync"])
        #expect(glance.upcoming.map(\.title) == ["Lunch"])
        #expect(glance.focus?.title == "Interview sync")
        #expect(glance.remaining.map(\.title) == ["Design review", "Interview sync", "Lunch"])
    }

    @Test func eventsStartingTogetherLeadWithTheOneEndingFirst() {
        let long = timed("Offsite", time(friday, 9), minutes: 480)
        let short = timed("Kickoff", time(friday, 9), minutes: 30)

        let glance = WidgetTimeline.glance(events: [long, short], at: time(friday, 9, 10), calendar: calendar)

        #expect(glance.inProgress.map(\.title) == ["Kickoff", "Offsite"])
        #expect(glance.focus?.title == "Kickoff")
    }

    @Test func anEventIsInProgressFromItsStartEntryUntilItsEndEntry() {
        let standup = timed("Standup", time(friday, 9, 30), minutes: 15)
        let entries = WidgetTimeline.entryDates(events: [standup], now: time(friday, 8), calendar: calendar, horizon: day)

        #expect(entries.contains(time(friday, 9, 30)))
        #expect(entries.contains(time(friday, 9, 45)))

        let atStart = WidgetTimeline.glance(events: [standup], at: time(friday, 9, 30), calendar: calendar)
        #expect(atStart.inProgress.map(\.title) == ["Standup"])
        #expect(atStart.focus?.title == "Standup")
        #expect(atStart.isInProgress(standup))

        let beforeStart = WidgetTimeline.glance(events: [standup], at: time(friday, 9, 29), calendar: calendar)
        #expect(beforeStart.inProgress.isEmpty)
        #expect(beforeStart.upcoming.map(\.title) == ["Standup"])
        #expect(!beforeStart.isInProgress(standup))
    }

    @Test func whenTheLastEventEndsTheDayIsOverAndTomorrowIsPreviewed() {
        let climbing = timed("Climbing", time(friday, 19), minutes: 120)
        let standup = timed("Standup", time(saturday, 9, 30), minutes: 15)
        let dentist = timed("Dentist", time(saturday, 15), minutes: 45)

        let glance = WidgetTimeline.glance(events: [dentist, standup, climbing], at: time(friday, 21), calendar: calendar)

        #expect(glance.date == friday)
        #expect(glance.inProgress.isEmpty)
        #expect(glance.upcoming.isEmpty)
        #expect(glance.focus == nil)
        #expect(glance.finished.map(\.title) == ["Climbing"])
        #expect(glance.nextDay.date == saturday)
        #expect(glance.nextDay.timed.map(\.title) == ["Standup", "Dentist"])
    }

    @Test func aDayWithNoTimedEventsHasNothingFinishedOrRemaining() {
        let trash = allDay("Trash night", friday)

        let glance = WidgetTimeline.glance(events: [trash], at: time(friday, 8), calendar: calendar)

        #expect(glance.remaining.isEmpty)
        #expect(glance.finished.isEmpty)
        #expect(glance.allDay.map(\.title) == ["Trash night"])
    }

    @Test func midnightStartsTheNextDayAndKeepsEventsRunningAcrossIt() {
        let lateSync = timed("Tokyo sync", time(friday, 23, 30), minutes: 60)
        let standup = timed("Standup", time(saturday, 9, 30), minutes: 15)
        let brunch = timed("Brunch", time(CivilDate(year: 2026, month: 11, day: 22), 11), minutes: 60)
        let events = [lateSync, standup, brunch]

        let entries = WidgetTimeline.entryDates(events: events, now: time(friday, 22), calendar: calendar, horizon: day)
        let midnight = time(saturday, 0)
        #expect(entries.contains(midnight))

        let beforeMidnight = WidgetTimeline.glance(events: events, at: time(friday, 23, 59), calendar: calendar)
        #expect(beforeMidnight.date == friday)
        #expect(beforeMidnight.inProgress.map(\.title) == ["Tokyo sync"])
        #expect(beforeMidnight.nextDay.timed.map(\.title) == ["Standup"])

        let afterMidnight = WidgetTimeline.glance(events: events, at: midnight, calendar: calendar)
        #expect(afterMidnight.date == saturday)
        #expect(afterMidnight.inProgress.map(\.title) == ["Tokyo sync"])
        #expect(afterMidnight.upcoming.map(\.title) == ["Standup"])
        #expect(afterMidnight.nextDay.timed.map(\.title) == ["Brunch"])
    }

    @Test func allDayEventsStayOutOfTheTimedListsAndCoverEveryDayTheySpan() {
        let trip = allDay("Trip to Portland", friday, through: saturday)
        let trash = allDay("Trash night", friday)
        let standup = timed("Standup", time(friday, 9, 30), minutes: 15)

        let glance = WidgetTimeline.glance(events: [trip, trash, standup], at: time(friday, 8), calendar: calendar)

        #expect(glance.allDay.map(\.title) == ["Trash night", "Trip to Portland"])
        #expect(glance.remaining.map(\.title) == ["Standup"])
        #expect(glance.focus?.title == "Standup")
        #expect(glance.nextDay.allDay.map(\.title) == ["Trip to Portland"])
        #expect(glance.nextDay.timed.isEmpty)
    }

    @Test func declinedEventsNeverAppear() {
        let vendor = timed("Vendor demo", time(friday, 16), minutes: 30, attendance: .declined)
        let pickup = timed("Pick up Maya", time(friday, 17, 15), minutes: 30, attendance: .accepted)
        let maybe = timed("Q1 planning", time(saturday, 14), minutes: 90, attendance: .tentative)
        let declinedTomorrow = timed("Optional lunch", time(saturday, 12), minutes: 60, attendance: .declined)
        let events = [vendor, pickup, maybe, declinedTomorrow]

        let during = WidgetTimeline.glance(events: events, at: time(friday, 16, 10), calendar: calendar)
        #expect(during.inProgress.isEmpty)
        #expect(during.upcoming.map(\.title) == ["Pick up Maya"])
        #expect(during.nextDay.timed.map(\.title) == ["Q1 planning"])

        let after = WidgetTimeline.glance(events: events, at: time(friday, 18), calendar: calendar)
        #expect(after.finished.map(\.title) == ["Pick up Maya"])

        let entries = WidgetTimeline.entryDates(events: events, now: time(friday, 15), calendar: calendar, horizon: day)
        #expect(!entries.contains(time(friday, 16)))
        #expect(!entries.contains(time(friday, 16, 30)))
        #expect(!entries.contains(time(saturday, 12)))
    }

    @Test func entryDatesAreNowEveryBoundaryInsideTheHorizonAndTheNextMidnight() {
        let now = time(friday, 10, 5)
        let events = [
            timed("Already over", time(friday, 8), minutes: 60),
            timed("Design review", time(friday, 10), minutes: 60),
            timed("Interview sync", time(friday, 11), minutes: 30),
            timed("Lunch", time(friday, 11, 30), minutes: 60),
            timed("Standup", time(saturday, 9, 30), minutes: 15),
            timed("Too far", time(saturday, 10, 30), minutes: 30),
        ]

        let entries = WidgetTimeline.entryDates(events: events, now: now, calendar: calendar, horizon: day)

        #expect(entries == [
            now,
            time(friday, 11),
            time(friday, 11, 30),
            time(friday, 12, 30),
            time(saturday, 0),
            time(saturday, 9, 30),
            time(saturday, 9, 45),
        ])
    }

    @Test func entryDatesTreatAllDayBoundariesAsMidnights() {
        let trip = allDay("Trip", friday, through: saturday)

        let entries = WidgetTimeline.entryDates(events: [trip], now: time(friday, 9), calendar: calendar, horizon: 2 * day)

        #expect(entries == [time(friday, 9), time(saturday, 0), time(CivilDate(year: 2026, month: 11, day: 22), 0)])
    }

    @Test func theTwentyFiveHourFallBackDayKeepsLateEventsOnToday() {
        let fallBack = CivilDate(year: 2026, month: 11, day: 1)
        let monday = CivilDate(year: 2026, month: 11, day: 2)
        let lateShow = timed("Late show", time(fallBack, 23, 30), minutes: 30)
        let holiday = allDay("Day off", fallBack)
        let morning = time(fallBack, 8)

        let glance = WidgetTimeline.glance(events: [lateShow, holiday], at: morning, calendar: calendar)
        #expect(glance.upcoming.map(\.title) == ["Late show"])
        #expect(glance.nextDay.timed.isEmpty)

        let lateNight = WidgetTimeline.glance(events: [lateShow, holiday], at: time(fallBack, 23, 45), calendar: calendar)
        #expect(lateNight.date == fallBack)
        #expect(lateNight.allDay.map(\.title) == ["Day off"])
        #expect(lateNight.inProgress.map(\.title) == ["Late show"])

        let entries = WidgetTimeline.entryDates(events: [lateShow, holiday], now: time(fallBack, 6), calendar: calendar, horizon: day)
        #expect(time(monday, 0).timeIntervalSince(time(fallBack, 0)) == 25 * 60 * 60)
        #expect(entries == [time(fallBack, 6), time(fallBack, 23, 30), time(monday, 0)])
    }

    @Test func theTwentyThreeHourSpringForwardDayHandsEarlyEventsToTomorrow() {
        let springForward = CivilDate(year: 2026, month: 3, day: 8)
        let monday = CivilDate(year: 2026, month: 3, day: 9)
        let earlyCall = timed("Early call", time(monday, 0, 30), minutes: 15)
        let dinner = timed("Dinner", time(springForward, 18), minutes: 90)

        let glance = WidgetTimeline.glance(events: [earlyCall, dinner], at: time(springForward, 12), calendar: calendar)
        #expect(glance.upcoming.map(\.title) == ["Dinner"])
        #expect(glance.nextDay.date == monday)
        #expect(glance.nextDay.timed.map(\.title) == ["Early call"])

        let entries = WidgetTimeline.entryDates(events: [earlyCall, dinner], now: time(springForward, 0), calendar: calendar, horizon: day)
        #expect(time(monday, 0).timeIntervalSince(time(springForward, 0)) == 23 * 60 * 60)
        #expect(entries == [time(springForward, 0), time(springForward, 18), time(springForward, 19, 30), time(monday, 0), time(monday, 0, 30), time(monday, 0, 45)])
    }
}
