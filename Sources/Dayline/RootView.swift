import AuthenticationServices
import DaylineCore
import DaylineKit
import SwiftUI

struct RootView: View {
    let model: AppModel
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        content
            .onOpenURL { url in
                if let link = DeepLink(url: url) {
                    model.open(link)
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task { await model.refreshIfStale() }
                }
            }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .launching:
            Color.clear
        case .signedOut, .signingIn:
            SignInView(issue: signInIssue, isSigningIn: model.phase == .signingIn) {
                Task { await model.signIn(authorize: authorize) }
            }
        case .signedIn(let state):
            AgendaView(model: model, state: state)
        }
    }

    private var signInIssue: CalendarServiceError? {
        guard case .signedOut(let issue) = model.phase else { return nil }
        return issue
    }

    private func authorize(url: URL, callbackScheme: String) async throws -> URL {
        try await webAuthenticationSession.authenticate(
            using: url,
            callback: .customScheme(callbackScheme),
            preferredBrowserSession: .shared,
            additionalHeaderFields: [:]
        )
    }
}
