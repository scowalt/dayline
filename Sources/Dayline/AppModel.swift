import DaylineCore
import DaylineKit
import Foundation
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
        var snapshot: Snapshot?
        var issues: [Account.ID: CalendarServiceError]
        var isRefreshing = false
        var isRefreshQueued = false
        var isAddingAccount = false
        var addAccountIssue: CalendarServiceError?
        var changeIssue: ChangeIssue?

        init(_ session: Session) {
            accounts = session.accounts
            snapshot = session.snapshot
            issues = session.issues
        }

        mutating func adopt(_ session: Session) {
            accounts = session.accounts
            snapshot = session.snapshot
            issues = session.issues
        }

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

    private(set) var phase: Phase = .launching
    private(set) var visibility: CalendarVisibility
    private(set) var pendingLink: DeepLink?
    let isDemo: Bool
    private let service: any CalendarService
    private let preferences: CalendarPreferences

    init(service: any CalendarService, preferences: CalendarPreferences = CalendarPreferences(), isDemo: Bool = false) {
        self.service = service
        self.preferences = preferences
        self.isDemo = isDemo
        preferences.usesDemoData = isDemo
        visibility = preferences.visibility
    }

    convenience init(launchArguments: [String]) {
        if launchArguments.contains("-demo") {
            self.init(service: DemoCalendarService(), isDemo: true)
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
        guard let session = await service.restore() else {
            phase = .signedOut(nil)
            return
        }
        phase = .signedIn(SignedIn(session))
        await refresh()
    }

    func signIn(authorize: @escaping WebAuthorizer, loginHint: String? = nil) async {
        if case .signedIn = phase {
            await addAccount(authorize: authorize, loginHint: loginHint)
            return
        }
        phase = .signingIn
        do throws(CalendarServiceError) {
            let session = try await service.signIn(authorize: authorize, loginHint: loginHint)
            phase = .signedIn(SignedIn(session))
            WidgetCenter.shared.reloadAllTimelines()
            if session.snapshot == nil {
                await refresh()
            }
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
    }

    private var isRefreshQueued: Bool {
        guard case .signedIn(let state) = phase else { return false }
        return state.isRefreshQueued
    }

    func refreshIfStale(maxAge: TimeInterval = 5 * 60) async {
        guard case .signedIn(let state) = phase else { return }
        if let fetchedAt = state.snapshot?.fetchedAt, Date.now.timeIntervalSince(fetchedAt) < maxAge { return }
        await refresh()
    }

    func signOut(_ account: Account.ID) async {
        if let session = await service.signOut(account) {
            update { state in
                let issues = state.issues.filter { id, _ in session.accounts.contains { $0.id == id } }
                state.adopt(session)
                state.issues = issues
            }
        } else {
            preferences.reset()
            visibility = CalendarVisibility()
            pendingLink = nil
            phase = .signedOut(nil)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    func reschedule(_ event: CalendarEvent, to time: EventTime, notifyGuests: Bool) async {
        guard let account = snapshot?.account(owning: event.calendarID) else { return }
        update {
            $0.snapshot = $0.snapshot?.rescheduling(event.id, to: time)
            $0.changeIssue = nil
        }
        do throws(CalendarServiceError) {
            try await service.reschedule(event.id, of: account.id, to: time, notifyGuests: notifyGuests)
            update {
                $0.snapshot = $0.snapshot?.rescheduling(event.id, to: time)
                $0.isRefreshQueued = $0.isRefreshing
            }
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            update {
                if $0.snapshot?.events.first(where: { $0.id == event.id })?.time == time {
                    $0.snapshot = $0.snapshot?.rescheduling(event.id, to: event.time)
                }
                $0.changeIssue = error == .cancelled ? nil : ChangeIssue(change: .move, account: account, eventTitle: event.title, error: error)
            }
        }
    }

    func delete(_ event: CalendarEvent, scope: DeletionScope, notifyGuests: Bool) async {
        guard let account = snapshot?.account(owning: event.calendarID) else { return }
        let deletion = event.deletion(scope)
        let before = snapshot
        update {
            $0.snapshot = $0.snapshot?.deleting(deletion)
            $0.changeIssue = nil
        }
        let optimistic = snapshot
        do throws(CalendarServiceError) {
            try await service.delete(deletion, of: account.id, notifyGuests: notifyGuests)
            update {
                $0.snapshot = $0.snapshot?.deleting(deletion)
                $0.isRefreshQueued = $0.isRefreshing
            }
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            update {
                if $0.snapshot == optimistic {
                    $0.snapshot = before
                }
                $0.changeIssue = error == .cancelled ? nil : ChangeIssue(change: .delete, account: account, eventTitle: event.title, error: error)
            }
        }
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
}
