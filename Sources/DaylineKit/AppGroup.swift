import Foundation

public enum AppGroup {
    public static let identifier: String = {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.scowalt.dayline"
        let hostBundleID = Bundle.main.bundleURL.pathExtension == "appex"
            ? bundleID.split(separator: ".").dropLast().joined(separator: ".")
            : bundleID
        return "group.\(hostBundleID)"
    }()

    public static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }
}
