import DaylineCore
import Foundation
import Testing

struct OutboxTests {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    let work = Account(email: "work@example.com")
    let home = Account(email: "home@example.com")
    let workCalendar = CalendarID(rawValue: "work")
    let homeCalendar = CalendarID(rawValue: "home")

    func eventID(_ calendar: CalendarID, _ name: String) -> EventID {
        EventID(calendar: calendar, event: name)
    }

    func time(hours: Double) -> EventTime {
        .timed(start: now.addingTimeInterval(hours * 3600), end: now.addingTimeInterval((hours + 1) * 3600))
    }

    func move(_ id: EventID, hours: Double, account: Account? = nil) -> PendingChange {
        PendingChange(account: (account ?? work).id, change: .move(id, to: time(hours: hours)), notifyGuests: false, eventTitle: id.event, queuedAt: now)
    }

    func delete(_ deletion: Deletion, account: Account? = nil) -> PendingChange {
        PendingChange(account: (account ?? work).id, change: .delete(deletion), notifyGuests: true, eventTitle: "gone", queuedAt: now)
    }

    var snapshot: Snapshot {
        func calendar(_ id: CalendarID) -> CalendarInfo {
            CalendarInfo(id: id, title: id.rawValue, color: RGBColor(red: 0, green: 0, blue: 0), isPrimary: false, isSelectedInGoogle: true, access: .owner)
        }
        func event(_ calendar: CalendarID, _ name: String) -> CalendarEvent {
            CalendarEvent(id: eventID(calendar, name), title: name, time: time(hours: 0))
        }
        return Snapshot(
            accounts: [
                AccountSnapshot(account: work, calendars: [calendar(workCalendar)], events: [event(workCalendar, "standup"), event(workCalendar, "review")]),
                AccountSnapshot(account: home, calendars: [calendar(homeCalendar)], events: [event(homeCalendar, "dentist"), event(homeCalendar, "run")]),
            ],
            range: DateInterval(start: now, duration: 86_400),
            fetchedAt: now
        )
    }

    @Test func aLaterMoveOfTheSameEventReplacesTheEarlierOneAtTheEnd() {
        let standup = eventID(workCalendar, "standup")
        let review = eventID(workCalendar, "review")
        var outbox = Outbox()
        outbox.enqueue(move(standup, hours: 1))
        outbox.enqueue(move(review, hours: 2))
        outbox.enqueue(move(standup, hours: 3))

        #expect(outbox.changes.map(\.change) == [.move(review, to: time(hours: 2)), .move(standup, to: time(hours: 3))])
    }

    @Test func movesOfDifferentEventsAndDeletionsAreAllKept() {
        let standup = eventID(workCalendar, "standup")
        var outbox = Outbox()
        outbox.enqueue(move(standup, hours: 1))
        outbox.enqueue(delete(.event(standup)))
        outbox.enqueue(move(standup, hours: 2))

        #expect(outbox.changes.map(\.change) == [.delete(.event(standup)), .move(standup, to: time(hours: 2))])
    }

    @Test func removingAnAbsentChangeLeavesTheOutboxAlone() {
        var outbox = Outbox()
        let queued = move(eventID(workCalendar, "standup"), hours: 1)
        outbox.enqueue(queued)
        let before = outbox

        outbox.remove(UUID())
        #expect(outbox == before)

        outbox.remove(queued.id)
        #expect(outbox.isEmpty)
    }

    @Test func removingAnAccountDropsOnlyItsChanges() {
        var outbox = Outbox()
        outbox.enqueue(move(eventID(workCalendar, "standup"), hours: 1))
        outbox.enqueue(move(eventID(homeCalendar, "dentist"), hours: 1, account: home))
        outbox.enqueue(delete(.event(eventID(workCalendar, "review"))))
        outbox.removeAll(for: work.id)

        #expect(outbox.changes.map(\.account) == [home.id])
    }

    @Test func nextIsTheOldestChangeOfAnAccountThatIsNotBlocked() {
        var outbox = Outbox()
        let first = move(eventID(workCalendar, "standup"), hours: 1)
        let second = move(eventID(homeCalendar, "dentist"), hours: 1, account: home)
        outbox.enqueue(first)
        outbox.enqueue(second)

        #expect(outbox.next(excluding: []) == first)
        #expect(outbox.next(excluding: [work.id]) == second)
        #expect(outbox.next(excluding: [work.id, home.id]) == nil)
        #expect(Outbox().next(excluding: []) == nil)
    }

    @Test func anOutboxAppliesToEveryAccountOldestFirst() {
        let standup = eventID(workCalendar, "standup")
        let dentist = eventID(homeCalendar, "dentist")
        var outbox = Outbox()
        outbox.enqueue(move(standup, hours: 5))
        outbox.enqueue(move(dentist, hours: 6, account: home))
        outbox.enqueue(delete(.event(standup)))
        outbox.enqueue(delete(.event(eventID(homeCalendar, "run")), account: home))

        let shown = snapshot.applying(outbox)

        #expect(shown.accounts.map { $0.events.map(\.title) } == [["review"], ["dentist"]])
        #expect(shown.accounts[1].events.first?.time == time(hours: 6))
        #expect(snapshot.applying(Outbox()) == snapshot)

        let moveOnly = snapshot.applying(.move(standup, to: time(hours: 5)))
        #expect(moveOnly.events.first { $0.id == standup }?.time == time(hours: 5))
        #expect(moveOnly.applying(.delete(.event(standup))).events.map(\.title) == ["review", "dentist", "run"])
    }

    @Test func anOutboxSurvivesEncodingWithEveryDeletionCase() throws {
        let series = eventID(workCalendar, "standup")
        let day = CivilDate(year: 2026, month: 11, day: 3)
        var outbox = Outbox()
        outbox.enqueue(move(series, hours: 1))
        outbox.enqueue(delete(.event(series)))
        outbox.enqueue(delete(.series(series)))
        outbox.enqueue(delete(.following(series: series, from: .day(day))))
        outbox.enqueue(delete(.following(series: series, from: .moment(now))))
        outbox.enqueue(PendingChange(account: home.id, change: .move(eventID(homeCalendar, "dentist"), to: .allDay(first: day, last: day)), notifyGuests: true, eventTitle: "Offsite", queuedAt: now))

        let decoded = try JSONDecoder().decode(Outbox.self, from: JSONEncoder().encode(outbox))

        #expect(decoded == outbox)
        #expect(decoded.changes.count == 6)
    }
}
