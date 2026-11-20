import DaylineCore
import Foundation

public struct SnapshotStore: Sendable {
    public enum Writer: String, Sendable {
        case app
        case widget
    }

    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public static var shared: SnapshotStore? {
        AppGroup.containerURL.map { SnapshotStore(directory: $0.appending(path: "Snapshots", directoryHint: .isDirectory)) }
    }

    public func latest() -> Snapshot? {
        Writer.allCases.compactMap(stored(by:)).max { $0.fetchedAt < $1.fetchedAt }
    }

    public func save(_ snapshot: Snapshot, as writer: Writer) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshot).write(to: url(for: writer), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    public func clear() {
        for writer in Writer.allCases {
            try? FileManager.default.removeItem(at: url(for: writer))
        }
    }

    public func remove(_ account: Account.ID) {
        for writer in Writer.allCases {
            guard let snapshot = stored(by: writer) else { continue }
            let remaining = snapshot.removing(account)
            if remaining.accounts.isEmpty {
                try? FileManager.default.removeItem(at: url(for: writer))
            } else {
                try? save(remaining, as: writer)
            }
        }
    }

    private func stored(by writer: Writer) -> Snapshot? {
        guard let data = try? Data(contentsOf: url(for: writer)) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    private func url(for writer: Writer) -> URL {
        directory.appending(path: "snapshot-\(writer.rawValue).json")
    }
}

extension SnapshotStore.Writer: CaseIterable {}
