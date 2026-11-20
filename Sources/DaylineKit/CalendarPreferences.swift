import DaylineCore
import Foundation

public struct CalendarPreferences: Sendable {
    private struct Stored: Codable {
        var visibility = CalendarVisibility()
        var usesDemoData = false
    }

    private let file: URL?

    public init(file: URL? = AppGroup.containerURL?.appending(path: "Settings/preferences.json")) {
        self.file = file
    }

    public var visibility: CalendarVisibility {
        get { stored.visibility }
        nonmutating set { update { $0.visibility = newValue } }
    }

    public var usesDemoData: Bool {
        get { stored.usesDemoData }
        nonmutating set { update { $0.usesDemoData = newValue } }
    }

    public func reset() {
        update { $0.visibility = CalendarVisibility() }
    }

    private var stored: Stored {
        guard let file, let data = try? Data(contentsOf: file) else { return Stored() }
        return (try? JSONDecoder().decode(Stored.self, from: data)) ?? Stored()
    }

    private func update(_ change: (inout Stored) -> Void) {
        guard let file else { return }
        var next = stored
        change(&next)
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(next).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
