import Foundation

public enum AppGroup {
    public static let identifier: String = {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.scowalt.dayline"
        let hostBundleID = Bundle.main.bundleURL.pathExtension == "appex"
            ? bundleID.split(separator: ".").dropLast().joined(separator: ".")
            : bundleID
        let unprefixedHostBundleID = hostBundleID.hasPrefix("XTL-")
            ? hostBundleID.split(separator: ".").dropFirst().joined(separator: ".")
            : hostBundleID
        let candidates = ["group.\(unprefixedHostBundleID)", "group.\(hostBundleID)"]
        return candidates.first { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) != nil } ?? candidates[0]
    }()

    public static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }
}
