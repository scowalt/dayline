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
        var account: Account
        var snapshot: Snapshot?
        var isRefreshing = false
        var issue: CalendarServiceError?
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
        visibility = preferences.visibility
    }

    convenience init(launchArguments: [String]) {
        if launchArguments.contains("-demo") {
            self.init(service: DemoCalendarService(), isDemo: true)
        } else {
            self.init(service: LiveCalendarService(writer: .app))
        }
    }

    var snapshot: Snapshot? {
        guard case .signedIn(let state) = phase else { return nil }
        return state.snapshot
    }

    var account: Account? {
        guard case .signedIn(let state) = phase else { return nil }
        return state.account
    }

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
        phase = .signedIn(SignedIn(account: session.account, snapshot: session.snapshot))
        await refresh()
    }

    func signIn(authorize: @escaping WebAuthorizer) async {
        phase = .signingIn
        do throws(CalendarServiceError) {
            let session = try await service.signIn(authorize: authorize)
            phase = .signedIn(SignedIn(account: session.account, snapshot: session.snapshot))
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

    func refresh() async {
        guard case .signedIn(let state) = phase, !state.isRefreshing else { return }
        update { $0.isRefreshing = true }
        do throws(CalendarServiceError) {
            let snapshot = try await service.refresh()
            update {
                $0.account = snapshot.account
                $0.snapshot = snapshot
                $0.issue = nil
            }
            WidgetCenter.shared.reloadAllTimelines()
        } catch .sessionExpired {
            phase = .signedOut(.sessionExpired)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            update { $0.issue = error }
        }
        update { $0.isRefreshing = false }
    }

    func refreshIfStale(maxAge: TimeInterval = 5 * 60) async {
        guard case .signedIn(let state) = phase else { return }
        if let fetchedAt = state.snapshot?.fetchedAt, Date.now.timeIntervalSince(fetchedAt) < maxAge { return }
        await refresh()
    }

    func signOut() async {
        await service.signOut()
        preferences.reset()
        visibility = CalendarVisibility()
        pendingLink = nil
        phase = .signedOut(nil)
        WidgetCenter.shared.reloadAllTimelines()
    }

    func setVisible(_ visible: Bool, calendar: CalendarID) {
        visibility.overrides[calendar] = visible
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
