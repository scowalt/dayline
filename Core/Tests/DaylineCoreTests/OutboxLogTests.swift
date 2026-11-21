import DaylineCore
import Foundation
import Testing

struct OutboxLogTests {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    let standup = EventID(calendar: CalendarID(rawValue: "work"), event: "standup")

    func pending(_ change: Change, queuedAt: Date? = nil) -> PendingChange {
        PendingChange(account: "me@work.example", change: change, notifyGuests: false, eventTitle: "Secret project", queuedAt: queuedAt ?? now)
    }

    var move: Change {
        .move(standup, to: .timed(start: now, end: now))
    }

    @Test func eachKindOfChangeHasItsOwnLabel() {
        let start = OccurrenceStart.moment(now)

        #expect(move.label == "move")
        #expect(Change.delete(.event(standup)).label == "delete event")
        #expect(Change.delete(.series(standup)).label == "delete series")
        #expect(Change.delete(.following(series: standup, from: start)).label == "delete this and following")
        #expect(Change.delete(.following(series: standup, from: start)).eventID == standup)
    }

    @Test func aQueuedLineNamesTheKindAndEventButNotTheTitle() {
        let message = OutboxLog.queued(pending(.delete(.series(standup))), replacing: [])

        #expect(message == "delete series work/standup: queued")
    }

    @Test func aQueuedMoveSaysWhichEarlierMoveItReplaced() {
        let earlier = pending(move, queuedAt: now.addingTimeInterval(-60))
        var outbox = Outbox()
        outbox.enqueue(earlier)
        let replaced = outbox.enqueue(pending(move))

        #expect(replaced == [earlier])
        #expect(OutboxLog.queued(pending(move), replacing: replaced) == "move work/standup: queued, replacing 1 earlier queued move (queued 2026-09-21T14:12:20Z)")
    }

    @Test func aSentLineShowsHowLongTheChangeWaited() {
        let message = OutboxLog.result(of: pending(move, queuedAt: now.addingTimeInterval(-3_700)), outcome: SendOutcome<TestFailure>.sent, error: nil, stillQueued: true, now: now)

        #expect(message == "move work/standup: sent after waiting 1 h 1 min")
    }

    @Test func aRetryLineShowsTheError() {
        let message = OutboxLog.result(of: pending(move), outcome: SendOutcome<TestFailure>.retryLater, error: "offline", stillQueued: true, now: now)

        #expect(message == "move work/standup: kept for retry: offline")
    }

    @Test func aBlockedAccountIsHeldUntilSignIn() {
        let message = OutboxLog.result(of: pending(move), outcome: SendOutcome<TestFailure>.accountBlocked, error: "sessionExpired", stillQueued: true, now: now)

        #expect(message == "move work/standup: held until sign-in: sessionExpired")
    }

    @Test func aRefusedChangeIsDroppedWithGoogleTheError() {
        let message = OutboxLog.result(of: pending(.delete(.event(standup))), outcome: SendOutcome.rejected(TestFailure()), error: "failed(\"Google error 404: Not Found\")", stillQueued: true, now: now)

        #expect(message == "delete event work/standup: dropped, Google refused it: failed(\"Google error 404: Not Found\")")
    }

    @Test func aFinishedSendForAReplacedChangeSaysWhichOutcomeWasIgnored() {
        let message = OutboxLog.result(of: pending(move), outcome: SendOutcome<TestFailure>.retryLater, error: "offline", stillQueued: false, now: now)

        #expect(message == "move work/standup: send finished after the change was replaced or removed, ignored outcome: kept for retry: offline")
    }

    @Test func removingAnAccountsChangesReturnsThemForTheLog() {
        var outbox = Outbox()
        let mine = pending(move)
        outbox.enqueue(mine)

        #expect(outbox.removeAll(for: "someone@else.example").isEmpty)
        #expect(outbox.removeAll(for: "me@work.example") == [mine])
        #expect(OutboxLog.removedOnSignOut([mine]) == "removed 1 queued changes because the account signed out: move work/standup")
    }

    @Test func storageFailuresAndBackgroundRunsHaveTheirOwnLines() {
        #expect(OutboxLog.saveFailed(count: 2, error: "disk full") == "error: could not save 2 queued changes (disk full), they are kept in memory only")
        #expect(OutboxLog.unreadable(error: "bad json", movedTo: "outbox-unreadable-x.json") == "error: the queued changes file is unreadable (bad json), moved it to outbox-unreadable-x.json and started with an empty queue")
        #expect(OutboxLog.unreadable(error: "bad json", movedTo: nil) == "error: the queued changes file is unreadable (bad json), could not move it aside and started with an empty queue")
        #expect(OutboxLog.backgroundFinished(sent: 2, queued: 1) == "background drain finished: 2 sent, 1 still queued")
    }
}

private struct TestFailure: Error {}
