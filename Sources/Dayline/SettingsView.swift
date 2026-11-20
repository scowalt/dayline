import DaylineCore
import DaylineKit
import SwiftUI

struct SettingsView: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var isConfirmingSignOut = false

    var body: some View {
        NavigationStack {
            Form {
                if let account = model.account {
                    Section {
                        AccountRow(account: account)
                    }
                }
                if !calendars.isEmpty {
                    Section {
                        ForEach(calendars) { calendar in
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
                    } header: {
                        Text("Calendars")
                    } footer: {
                        Text("Hidden calendars are also hidden from Dayline widgets.")
                    }
                }
                Section {
                    Button("Sign Out", role: .destructive) {
                        isConfirmingSignOut = true
                    }
                    .confirmationDialog("Sign out of Google?", isPresented: $isConfirmingSignOut, titleVisibility: .visible) {
                        Button("Sign Out", role: .destructive) {
                            dismiss()
                            Task { await model.signOut() }
                        }
                    } message: {
                        Text("Dayline will remove your calendar from this iPhone and its widgets.")
                    }
                } footer: {
                    Text("Dayline \(Self.version)")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                }
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
        }
    }

    private var calendars: [CalendarInfo] {
        (model.snapshot?.calendars ?? []).sorted { lhs, rhs in
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
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var initial: String {
        (account.name ?? account.email).first.map { String($0).uppercased() } ?? "?"
    }
}
