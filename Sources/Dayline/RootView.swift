import AuthenticationServices
import DaylineCore
import DaylineKit
import SwiftUI

struct RootView: View {
    let model: AppModel
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession

    var body: some View {
        switch model.phase {
        case .launching, .signingIn:
            ProgressView()
        case .signedOut(let issue):
            VStack(spacing: 16) {
                Text("Dayline").font(.largeTitle.bold())
                if let issue {
                    Text(String(describing: issue)).foregroundStyle(.secondary)
                }
                Button("Sign in with Google") {
                    Task { await model.signIn(authorize: authorize) }
                }
                .buttonStyle(.borderedProminent)
            }
        case .signedIn(let state):
            NavigationStack {
                List(model.visibleEvents) { event in
                    Text(event.title)
                }
                .refreshable { await model.refresh() }
                .navigationTitle(state.account.email)
            }
        }
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
