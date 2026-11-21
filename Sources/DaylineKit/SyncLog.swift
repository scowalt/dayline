import DaylineCore
import Foundation

public struct SyncLog: Sendable {
    public static let limit = 500

    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public static var shared: SyncLog? {
        AppGroup.containerURL.map { SyncLog(directory: $0.appending(path: "Diagnostics", directoryHint: .isDirectory)) }
    }

    public func entries() -> [SyncLogEntry] {
        SnapshotStore.Writer.allCases.flatMap(stored(by:)).sorted { $0.at < $1.at }
    }

    public func append(_ entry: SyncLogEntry, as writer: SnapshotStore.Writer) {
        let kept = (stored(by: writer) + [entry]).suffix(Self.limit)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? JSONEncoder().encode(Array(kept)).write(to: url(for: writer), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private func stored(by writer: SnapshotStore.Writer) -> [SyncLogEntry] {
        guard let data = try? Data(contentsOf: url(for: writer)) else { return [] }
        return (try? JSONDecoder().decode([SyncLogEntry].self, from: data)) ?? []
    }

    private func url(for writer: SnapshotStore.Writer) -> URL {
        directory.appending(path: "sync-log-\(writer.rawValue).json")
    }
}
