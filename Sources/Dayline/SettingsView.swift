import AuthenticationServices
import DaylineCore
import DaylineKit
import SwiftUI

struct SettingsView: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @State private var accountToSignOut: Account?

    var body: some View {
        NavigationStack {
            Form {
                ForEach(model.accounts) { account in
                    accountSection(account)
                }
                addAccountSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) {
                        dismiss()
                    }
                }
            }
            .confirmationDialog(
                "Sign out of this account?",
                isPresented: Binding(get: { accountToSignOut != nil }, set: { if !$0 { accountToSignOut = nil } }),
                titleVisibility: .visible,
                presenting: accountToSignOut
            ) { account in
                Button("Sign Out", role: .destructive) {
                    signOut(account)
                }
            } message: { account in
                Text("Dayline will remove \(account.email) from this iPhone and its widgets.")
            }
        }
    }

    private func accountSection(_ account: Account) -> some View {
        let issue = model.issues[account.id]
        return Section {
            AccountRow(account: account, issue: issue)
            if issue == .sessionExpired {
                Button("Sign In Again") {
                    Task { await model.signIn(authorize: webAuthenticationSession.authorize, loginHint: account.email) }
                }
                .disabled(model.isAddingAccount)
            }
            ForEach(calendars(of: account)) { calendar in
                Toggle(isOn: visibility(of: calendar)) {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Color(calendar.color))
                            .frame(width: 12, height: 12)
                            .accessibilityHidden(true)
                        Text(calendar.title)
                            .lineLimit(1)
                    }
                }
            }
            Button("Sign Out", role: .destructive) {
                accountToSignOut = account
            }
        } footer: {
            if account.id == model.accounts.last?.id {
                Text("Hidden calendars are also hidden from Dayline widgets.")
            }
        }
    }

    private var addAccountSection: some View {
        Section {
            Button {
                Task { await model.signIn(authorize: webAuthenticationSession.authorize) }
            } label: {
                HStack {
                    Text("Add Google Account")
                    if model.isAddingAccount {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(model.isAddingAccount)
        } footer: {
            VStack(alignment: .leading, spacing: 24) {
                if let message = model.addAccountIssue?.signInMessage, let issue = model.addAccountIssue {
                    Label(message, systemImage: issue.symbolName)
                }
                Text("Dayline \(Self.version)")
                    .frame(maxWidth: .infinity)
            }
            .padding(.bottom, 8)
        }
    }

    private func signOut(_ account: Account) {
        if model.accounts.count == 1 {
            dismiss()
        }
        Task { await model.signOut(account.id) }
    }

    private func calendars(of account: Account) -> [CalendarInfo] {
        (model.snapshot?.calendars(of: account.id) ?? []).sorted { lhs, rhs in
            if lhs.isPrimary != rhs.isPrimary { return lhs.isPrimary }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }

    private func visibility(of calendar: CalendarInfo) -> Binding<Bool> {
        Binding {
            model.visibility.isVisible(calendar)
        } set: { visible in
            model.setVisible(visible, calendar: calendar.id)
        }
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}

private struct AccountRow: View {
    let account: Account
    let issue: CalendarServiceError?

    var body: some View {
        HStack(spacing: 12) {
            Text(initial)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.tint, in: .circle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name ?? account.email)
                    .font(.headline)
                if account.name != nil {
                    Text(account.email)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let issue, let message = issue.signInMessage {
                    Label(message, systemImage: issue.symbolName)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var initial: String {
        (account.name ?? account.email).first.map { String($0).uppercased() } ?? "?"
    }
}
