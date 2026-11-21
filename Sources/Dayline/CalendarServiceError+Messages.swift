import DaylineKit

extension CalendarServiceError {
    var signInMessage: String? {
        switch self {
        case .cancelled:
            nil
        case .sessionExpired:
            "Your Google session ended. Sign in again to see your calendar."
        case .offline:
            "You're offline. Connect to the internet and try again."
        case .unavailable:
            "Google is unavailable right now. Try again later."
        case .missingEditPermission:
            "Dayline needs permission to change events in this account."
        case .failed(let message):
            message
        }
    }

    var statusMessage: String? {
        switch self {
        case .cancelled:
            nil
        case .sessionExpired:
            "Session ended"
        case .offline:
            "Offline"
        case .unavailable:
            "Google unavailable"
        case .missingEditPermission, .failed:
            "Couldn't update"
        }
    }

    var symbolName: String {
        switch self {
        case .offline:
            "wifi.slash"
        case .sessionExpired:
            "person.crop.circle.badge.clock"
        case .missingEditPermission:
            "lock"
        case .cancelled, .failed, .unavailable:
            "exclamationmark.triangle"
        }
    }
}
