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

    public func load() throws -> Outbox {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return Outbox()
        }
        return try JSONDecoder().decode(Outbox.self, from: data)
    }

    public func moveAside(at date: Date = .now) throws -> URL {
        let destination = directory.appending(path: "outbox-unreadable-\(date.formatted(.iso8601)).json")
        try FileManager.default.moveItem(at: url, to: destination)
        return destination
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
