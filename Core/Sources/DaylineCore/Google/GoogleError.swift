import Foundation

public enum GoogleError: Error, Hashable, Sendable {
    case accessDenied
    case stateMismatch
    case authorizationFailed(String)
    case invalidGrant
    case missingRefreshToken
    case missingCalendarScope
    case unauthorized
    case insufficientScope
    case server(status: Int, message: String?)
    case malformedResponse

    public var message: String {
        switch self {
        case .accessDenied:
            "Google sign-in was declined."
        case .stateMismatch:
            "Sign-in was interrupted. Try again."
        case .authorizationFailed(let code):
            "Google sign-in failed (\(code))."
        case .invalidGrant:
            "Your Google session has expired. Sign in again."
        case .missingRefreshToken:
            "Google did not grant offline access. Try signing in again."
        case .missingCalendarScope:
            "Dayline needs permission to see your calendars. Sign in again and allow calendar access."
        case .unauthorized:
            "Google rejected Dayline's credentials. Sign in again."
        case .insufficientScope:
            "Dayline needs permission to change events in this Google account."
        case .server(let status, let message?):
            "Google error \(status): \(message)"
        case .server(let status, nil):
            "Google error \(status)."
        case .malformedResponse:
            "Google sent a response Dayline could not read."
        }
    }

    init(oauthResponse response: HTTPResponse) {
        let body = try? GoogleJSON.decode(OAuthErrorBody.self, from: response.body)
        if body?.error == "invalid_grant" {
            self = .invalidGrant
        } else {
            self = .server(status: response.status, message: body?.errorDescription ?? body?.error)
        }
    }

    init(apiResponse response: HTTPResponse) {
        let body = try? GoogleJSON.decode(APIErrorBody.self, from: response.body)
        if response.status == 401 {
            self = .unauthorized
        } else if response.status == 403, body?.error.errors?.contains(where: { $0.reason == "insufficientPermissions" }) == true {
            self = .insufficientScope
        } else {
            self = .server(status: response.status, message: body?.error.message)
        }
    }
}

enum GoogleJSON {
    static func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws(GoogleError) -> Value {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw .malformedResponse
        }
    }
}

private struct OAuthErrorBody: Decodable {
    var error: String
    var errorDescription: String?
}

private struct APIErrorBody: Decodable {
    struct Detail: Decodable {
        var message: String?
        var errors: [Reason]?
    }

    struct Reason: Decodable {
        var reason: String?
    }

    var error: Detail
}
