import DaylineCore
import Foundation

public struct OutboxStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public static var shared: OutboxStore? {
        AppGroup.containerURL.map { OutboxStore(directory: $0.appending(path: "Outbox", directoryHint: .isDirectory)) }
    }

    public func load() -> Outbox {
        guard let data = try? Data(contentsOf: url) else { return Outbox() }
        return (try? JSONDecoder().decode(Outbox.self, from: data)) ?? Outbox()
    }

    public func save(_ outbox: Outbox) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(outbox).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    public func clear() {
        try? FileManager.default.removeItem(at: url)
    }

    private var url: URL {
        directory.appending(path: "outbox.json")
    }
}
