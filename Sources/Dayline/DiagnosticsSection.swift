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
            Text("A text report of each account's calendars, the changes still waiting to be sent to Google, and the last \(SyncLog.limit) sync log entries. It includes calendar names, email addresses and event IDs, but no event titles, notes or sign-in tokens.")
        }
    }

    private var report: String {
        Diagnostics.report(
            version: version,
            now: .now,
            timeZone: .current,
            accounts: model.accounts,
            issues: model.issues.mapValues { "\($0)" },
            snapshot: model.base,
            outbox: model.outbox,
            visibility: model.visibility,
            log: SyncLog.shared?.entries() ?? []
        )
    }
}
