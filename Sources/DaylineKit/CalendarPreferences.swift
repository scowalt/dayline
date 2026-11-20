import DaylineCore
import Foundation

public struct CalendarPreferences: Sendable {
    private let suiteName: String
    private static let visibilityKey = "calendarVisibility"

    public init(suiteName: String = AppGroup.identifier) {
        self.suiteName = suiteName
    }

    public var visibility: CalendarVisibility {
        get {
            UserDefaults(suiteName: suiteName)?.data(forKey: Self.visibilityKey)
                .flatMap { try? JSONDecoder().decode(CalendarVisibility.self, from: $0) }
                ?? CalendarVisibility()
        }
        nonmutating set {
            UserDefaults(suiteName: suiteName)?.set(try? JSONEncoder().encode(newValue), forKey: Self.visibilityKey)
        }
    }

    public func reset() {
        UserDefaults(suiteName: suiteName)?.removeObject(forKey: Self.visibilityKey)
    }
}
