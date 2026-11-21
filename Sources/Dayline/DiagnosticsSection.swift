import DaylineCore
import DaylineKit
import SwiftUI

struct DiagnosticsSection: View {
    let model: AppModel
    let version: String

    var body: some View {
        Section {
            ShareLink(item: report, subject: Text("Dayline diagnostics")) {
                Label("Share Diagnostics", systemImage: "stethoscope")
            }
        } footer: {
            Text("A text report of each account's calendars and the last \(SyncLog.limit) sync requests. It includes calendar names and email addresses, but no event details or sign-in tokens.")
        }
    }

    private var report: String {
        Diagnostics.report(
            version: version,
            now: .now,
            timeZone: .current,
            accounts: model.accounts,
            issues: model.issues.mapValues { "\($0)" },
            snapshot: model.snapshot,
            visibility: model.visibility,
            log: SyncLog.shared?.entries() ?? []
        )
    }
}
