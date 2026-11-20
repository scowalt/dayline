import DaylineKit

extension CalendarServiceError {
    var signInMessage: String? {
        switch self {
        case .cancelled:
            nil
        case .notConfigured:
            "Google sign-in isn't set up in this build of Dayline yet."
        case .sessionExpired:
            "Your Google session ended. Sign in again to see your calendar."
        case .offline:
            "You're offline. Connect to the internet and try again."
        case .failed:
            "Google sign-in didn't finish. Please try again."
        }
    }

    var statusMessage: String? {
        switch self {
        case .cancelled:
            nil
        case .notConfigured:
            "Sign-in isn't set up"
        case .sessionExpired:
            "Session ended"
        case .offline:
            "Offline"
        case .failed:
            "Couldn't update"
        }
    }

    var symbolName: String {
        switch self {
        case .offline:
            "wifi.slash"
        case .sessionExpired:
            "person.crop.circle.badge.clock"
        case .cancelled, .notConfigured, .failed:
            "exclamationmark.triangle"
        }
    }
}
