import DaylineCore
import DaylineKit
import BackgroundTasks
import Foundation
import Network
import Observation
import WidgetKit

@Observable
final class AppModel {
    enum Phase: Equatable {
        case launching
        case signedOut(CalendarServiceError?)
        case signingIn
        case signedIn(SignedIn)
    }

    struct SignedIn: Equatable {
        var accounts: [Account]
        var base: Snapshot?
        var outbox: Outbox
        var issues: [Account.ID: CalendarServiceError]
        var isRefreshing = false
        var isRefreshQueued = false
        var isDraining = false
        var isAddingAccount = false
        var addAccountIssue: CalendarServiceError?
        var changeIssue: ChangeIssue?

        init(_ session: Session, outbox: Outbox) {
            accounts = session.accounts
            base = session.snapshot
            self.outbox = outbox
            issues = session.issues
        }

        mutating func adopt(_ session: Session) {
            accounts = session.accounts
            base = session.snapshot
            issues = session.issues
        }

        var snapshot: Snapshot? { base?.applying(outbox) }

        var firstIssue: (account: Account, error: CalendarServiceError)? {
            accounts.lazy.compactMap { account in issues[account.id].map { (account, $0) } }.first
        }

        var issueMessage: String? {
            guard let (account, error) = firstIssue else { return nil }
            if error == .sessionExpired, accounts.count > 1 {
                return "Session ended for \(account.email)"
            }
            return error.statusMessage
        }
    }

    struct ChangeIssue: Equatable, Identifiable {
        enum Change {
            case move
            case delete
        }

        let id = UUID()
        let change: Change
        let account: Account
        let eventTitle: String
        let error: CalendarServiceError
    }

    static let drainTaskIdentifier = "com.scowalt.dayline.drain"

    private(set) var phase: Phase = .launching
    private(set) var visibility: CalendarVisibility
    private(set) var pendingLink: DeepLink?
    let isDemo: Bool
    private let service: any CalendarService
    private let preferences: CalendarPreferences
    private let outboxStore: OutboxStore?
    @ObservationIgnored private var pathMonitor: NWPathMonitor?

    init(
        service: any CalendarService,
        preferences: CalendarPreferences = CalendarPreferences(),
        outboxStore: OutboxStore? = .shared,
        isDemo: Bool = false
    ) {
        self.service = service
        self.preferences = preferences
        self.outboxStore = outboxStore
        self.isDemo = isDemo
        preferences.usesDemoData = isDemo
        visibility = preferences.visibility
    }

    convenience init(launchArguments: [String]) {
        if launchArguments.contains("-demo") {
            self.init(service: DemoCalendarService(isOffline: launchArguments.contains("-offline")), isDemo: true)
        } else {
            self.init(service: LiveCalendarService(writer: .app))
        }
    }

    private var signedIn: SignedIn? {
        guard case .signedIn(let state) = phase else { return nil }
        return state
    }

    var snapshot: Snapshot? { signedIn?.snapshot }
    var accounts: [Account] { signedIn?.accounts ?? [] }
    var issues: [Account.ID: CalendarServiceError] { signedIn?.issues ?? [:] }
    var isAddingAccount: Bool { signedIn?.isAddingAccount ?? false }
    var addAccountIssue: CalendarServiceError? { signedIn?.addAccountIssue }
    var changeIssue: ChangeIssue? { signedIn?.changeIssue }

    func event(_ id: EventID) -> CalendarEvent? {
        snapshot?.events.first { $0.id == id }
    }

    var visibleEvents: [CalendarEvent] {
        snapshot?.events(visibleWith: visibility) ?? []
    }

    func start() async {
        guard case .launching = phase else { return }
        watchNetwork()
        guard let session = await service.restore() else {
            phase = .signedOut(nil)
            return
        }
        phase = .signedIn(SignedIn(session, outbox: storedOutbox(for: session)))
        await drain()
        await refresh()
    }

    private func storedOutbox(for session: Session) -> Outbox {
        var outbox = outboxStore?.load() ?? Outbox()
        let signedIn = Set(session.accounts.map(\.id))
        for account in Set(outbox.changes.map(\.account)).subtracting(signedIn) {
            outbox.removeAll(for: account)
        }
        return outbox
    }

    private func watchNetwork() {
        guard pathMonitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in await self?.drain() }
        }
        monitor.start(queue: .main)
        pathMonitor = monitor
    }

    func signIn(authorize: @escaping WebAuthorizer, loginHint: String? = nil) async {
        if case .signedIn = phase {
            await addAccount(authorize: authorize, loginHint: loginHint)
            return
        }
        phase = .signingIn
        do throws(CalendarServiceError) {
            let session = try await service.signIn(authorize: authorize, loginHint: loginHint)
            phase = .signedIn(SignedIn(session, outbox: storedOutbox(for: session)))
            WidgetCenter.shared.reloadAllTimelines()
            if session.snapshot == nil {
                await refresh()
            }
            await drain()
        } catch .cancelled {
            phase = .signedOut(nil)
        } catch {
            phase = .signedOut(error)
        }
    }

    private func addAccount(authorize: @escaping WebAuthorizer, loginHint: String?) async {
        update {
            $0.isAddingAccount = true
            $0.addAccountIssue = nil
        }
        do throws(CalendarServiceError) {
            let session = try await service.signIn(authorize: authorize, loginHint: loginHint)
            update {
                $0.adopt(session)
                $0.isAddingAccount = false
                $0.isRefreshQueued = $0.isRefreshing
            }
            WidgetCenter.shared.reloadAllTimelines()
            await drain()
        } catch {
            update {
                $0.isAddingAccount = false
                $0.addAccountIssue = error == .cancelled ? nil : error
            }
        }
    }

    func refresh() async {
        guard case .signedIn(let state) = phase else { return }
        guard !state.isRefreshing else {
            update { $0.isRefreshQueued = true }
            return
        }
        update { $0.isRefreshing = true }
        repeat {
            update { $0.isRefreshQueued = false }
            do throws(CalendarServiceError) {
                let session = try await service.refresh()
                update { $0.adopt(session) }
                WidgetCenter.shared.reloadAllTimelines()
            } catch {
                guard case .signedIn = phase else { return }
                phase = .signedOut(error)
                WidgetCenter.shared.reloadAllTimelines()
                return
            }
        } while isRefreshQueued
        update { $0.isRefreshing = false }
        await drain()
    }

    private var isRefreshQueued: Bool {
        guard case .signedIn(let state) = phase else { return false }
        return state.isRefreshQueued
    }

    func refreshIfStale(maxAge: TimeInterval = 5 * 60) async {
        guard case .signedIn(let state) = phase else { return }
        if let fetchedAt = state.base?.fetchedAt, Date.now.timeIntervalSince(fetchedAt) < maxAge {
            await drain()
            return
        }
        await refresh()
    }

    func signOut(_ account: Account.ID) async {
        updateOutbox { $0.outbox.removeAll(for: account) }
        if let session = await service.signOut(account) {
            update { state in
                let issues = state.issues.filter { id, _ in session.accounts.contains { $0.id == id } }
                state.adopt(session)
                state.issues = issues
            }
        } else {
            preferences.reset()
            outboxStore?.clear()
            visibility = CalendarVisibility()
            pendingLink = nil
            phase = .signedOut(nil)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    func reschedule(_ event: CalendarEvent, to time: EventTime, notifyGuests: Bool) async {
        await enqueue(event, change: .move(event.id, to: time), notifyGuests: notifyGuests)
    }

    func delete(_ event: CalendarEvent, scope: DeletionScope, notifyGuests: Bool) async {
        await enqueue(event, change: .delete(event.deletion(scope)), notifyGuests: notifyGuests)
    }

    private func enqueue(_ event: CalendarEvent, change: Change, notifyGuests: Bool) async {
        guard let account = snapshot?.account(owning: event.calendarID) else { return }
        let pending = PendingChange(account: account.id, change: change, notifyGuests: notifyGuests, eventTitle: event.title)
        updateOutbox {
            $0.outbox.enqueue(pending)
            $0.changeIssue = nil
        }
        await drain()
    }

    func drain() async {
        guard let state = signedIn, !state.isDraining else { return }
        update { $0.isDraining = true }
        var blocked: Set<Account.ID> = []
        while let pending = signedIn?.outbox.next(excluding: blocked) {
            let outcome: SendOutcome<CalendarServiceError>
            do throws(CalendarServiceError) {
                try await service.send(pending)
                outcome = .sent
            } catch {
                outcome = error.outcome
            }
            guard let current = signedIn else { return }
            guard current.outbox.changes.contains(where: { $0.id == pending.id }) else { continue }
            switch outcome {
            case .sent:
                updateOutbox {
                    $0.base = $0.base?.applying(pending.change)
                    $0.outbox.remove(pending.id)
                    $0.isRefreshQueued = $0.isRefreshing
                }
            case .retryLater:
                update { $0.isDraining = false }
                return
            case .accountBlocked:
                blocked.insert(pending.account)
            case .rejected(let error):
                updateOutbox {
                    $0.outbox.remove(pending.id)
                    $0.changeIssue = $0.accounts.first { $0.id == pending.account }.map {
                        ChangeIssue(change: pending.change.kind, account: $0, eventTitle: pending.eventTitle, error: error)
                    }
                }
            }
        }
        update { $0.isDraining = false }
    }

    func drainInBackground() async {
        await start()
        await drain()
        scheduleBackgroundDrain()
    }

    func scheduleBackgroundDrain() {
        guard let state = signedIn, !state.outbox.isEmpty else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.drainTaskIdentifier)
        request.earliestBeginDate = .now.addingTimeInterval(15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    func dismissChangeIssue() {
        update { $0.changeIssue = nil }
    }

    func setVisible(_ visible: Bool, calendar: CalendarID) {
        visibility.overrides[calendar] = visible
        preferences.visibility = visibility
        WidgetCenter.shared.reloadAllTimelines()
        if visible {
            Task { await refresh() }
        }
    }

    func hideEvents(titled title: String) {
        visibility.hide(title: title)
        preferences.visibility = visibility
        WidgetCenter.shared.reloadAllTimelines()
    }

    func showEvents(titled title: String) {
        visibility.show(title: title)
        preferences.visibility = visibility
        WidgetCenter.shared.reloadAllTimelines()
    }

    func open(_ link: DeepLink) {
        pendingLink = link
    }

    func takePendingLink() -> DeepLink? {
        defer { pendingLink = nil }
        return pendingLink
    }

    private func update(_ change: (inout SignedIn) -> Void) {
        guard case .signedIn(var state) = phase else { return }
        change(&state)
        phase = .signedIn(state)
    }

    private func updateOutbox(_ change: (inout SignedIn) -> Void) {
        update(change)
        if let outbox = signedIn?.outbox {
            try? outboxStore?.save(outbox)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}

extension Change {
    fileprivate var kind: AppModel.ChangeIssue.Change {
        switch self {
        case .move: .move
        case .delete: .delete
        }
    }
}
