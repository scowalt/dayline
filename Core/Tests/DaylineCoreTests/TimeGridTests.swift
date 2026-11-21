import DaylineCore
import Foundation
import Testing

struct TimeGridTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }()

    func at(_ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    func day(_ month: Int, _ day: Int) -> CivilDate {
        CivilDate(year: 2026, month: month, day: day)
    }

    func timed(_ id: String, _ start: Date, _ end: Date) -> CalendarEvent {
        CalendarEvent(id: EventID(calendar: CalendarID(rawValue: "work"), event: id), title: id, time: .timed(start: start, end: end))
    }

    func layout(_ placements: [TimeGridPlacement]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: placements.map {
            ($0.event.id.event, "\(Int($0.startMinute))-\(Int($0.endMinute)) \($0.column + 1)/\($0.columnCount)")
        })
    }

    @Test func overlappingEventsShareTheWidthAndSeparateClustersDoNot() {
        let events = [
            timed("standup", at(11, 20, 9, 30), at(11, 20, 9, 45)),
            timed("review", at(11, 20, 11), at(11, 20, 12)),
            timed("sync", at(11, 20, 11, 30), at(11, 20, 12)),
            timed("lunch", at(11, 20, 12), at(11, 20, 13)),
            timed("after", at(11, 20, 11, 45), at(11, 20, 12, 30)),
        ]
        #expect(layout(TimeGrid.placements(of: events, on: day(11, 20), calendar: calendar)) == [
            "standup": "570-585 1/1",
            "review": "660-720 1/3",
            "sync": "690-720 2/3",
            "after": "705-750 3/3",
            "lunch": "720-780 1/3",
        ])
    }

    @Test func shortEventsReserveTheMinimumHeightSoTheyDoNotOverlapTheNextOne() {
        let events = [
            timed("reminder", at(11, 20, 10), at(11, 20, 10)),
            timed("next", at(11, 20, 10, 10), at(11, 20, 10, 40)),
        ]
        #expect(layout(TimeGrid.placements(of: events, on: day(11, 20), calendar: calendar)) == [
            "reminder": "600-600 1/2",
            "next": "610-640 2/2",
        ])
    }

    @Test func overnightEventsAreClippedToEachDayAndAllDayEventsAreLeftOut() {
        let events = [
            timed("redeye", at(12, 2, 22, 15), at(12, 3, 6, 40)),
            timed("ends-at-midnight", at(12, 2, 23), at(12, 3, 0)),
            CalendarEvent(id: EventID(calendar: CalendarID(rawValue: "work"), event: "trip"), title: "trip", time: .allDay(first: day(12, 2), last: day(12, 3))),
        ]
        #expect(layout(TimeGrid.placements(of: events, on: day(12, 2), calendar: calendar)) == [
            "redeye": "1335-1440 1/2",
            "ends-at-midnight": "1380-1440 2/2",
        ])
        #expect(layout(TimeGrid.placements(of: events, on: day(12, 3), calendar: calendar)) == [
            "redeye": "0-400 1/1",
        ])
    }

    @Test func minutesFollowTheWallClockAcrossDaylightSaving() {
        #expect(TimeGrid.minute(of: at(11, 1, 3), from: day(11, 1), calendar: calendar) == 180)
        #expect(TimeGrid.minute(of: at(10, 31, 23), from: day(11, 1), calendar: calendar) == -60)
        #expect(TimeGrid.minute(of: at(11, 2, 1, 30), from: day(11, 1), calendar: calendar) == 1530)
    }

    @Test func dropsSnapToTheQuarterHourAndRollIntoNeighbouringDays() {
        #expect(TimeGrid.snappedDate(atMinute: 607, from: day(11, 20), calendar: calendar) == at(11, 20, 10, 0))
        #expect(TimeGrid.snappedDate(atMinute: 608, from: day(11, 20), calendar: calendar) == at(11, 20, 10, 15))
        #expect(TimeGrid.snappedDate(atMinute: -50, from: day(11, 20), calendar: calendar) == at(11, 19, 23, 15))
        #expect(TimeGrid.snappedDate(atMinute: 1445, from: day(11, 20), calendar: calendar) == at(11, 21, 0, 0))
        #expect(TimeGrid.snappedDate(atMinute: 180, from: day(11, 1), calendar: calendar) == at(11, 1, 3))
    }

    @Test func movingAnEventKeepsItsLength() {
        let moved = EventTime.timed(start: at(11, 20, 11), end: at(11, 20, 12, 30)).starting(at: at(11, 21, 15, 15), in: calendar)
        #expect(moved == .timed(start: at(11, 21, 15, 15), end: at(11, 21, 16, 45)))

        let trip = EventTime.allDay(first: day(11, 30), last: day(12, 2)).starting(at: at(12, 5, 9), in: calendar)
        #expect(trip == .allDay(first: day(12, 5), last: day(12, 7)))
    }
}
