import DaylineKit
import SwiftUI

struct SignInView: View {
    let issue: CalendarServiceError?
    let isSigningIn: Bool
    let signIn: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: "calendar.day.timeline.left")
                    .font(.system(size: 64))
                    .foregroundStyle(.tint)
                    .symbolRenderingMode(.hierarchical)
                    .padding(.bottom, 8)
                    .accessibilityHidden(true)
                Text("Dayline")
                    .font(.largeTitle.bold())
                Text("Your Google Calendar, at a glance.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
            VStack(spacing: 16) {
                if let message = issue?.signInMessage, let issue {
                    Label(message, systemImage: issue.symbolName)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .labelStyle(StackedLabelStyle())
                        .transition(.opacity)
                }
                Button(action: signIn) {
                    HStack(spacing: 8) {
                        if isSigningIn {
                            ProgressView()
                        }
                        Text(isSigningIn ? "Signing In…" : "Sign in with Google")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.extraLarge)
                .disabled(isSigningIn)
                Text("Dayline only reads your calendars. It never changes them.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
        .frame(maxWidth: 480)
        .animation(.default, value: issue)
    }
}

private struct StackedLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 6) {
            configuration.icon.font(.title3)
            configuration.title
        }
    }
}
