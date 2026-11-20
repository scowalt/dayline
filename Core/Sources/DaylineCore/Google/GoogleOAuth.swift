import Foundation

public struct PKCE: Hashable, Sendable {
    public let verifier: String
    public let challenge: String

    public init(verifier: String, challenge: String) {
        self.verifier = verifier
        self.challenge = challenge
    }
}

public struct AccessToken: Hashable, Sendable {
    public static let refreshMargin: TimeInterval = 60

    public let value: String
    public let expiresAt: Date

    public init(value: String, expiresAt: Date) {
        self.value = value
        self.expiresAt = expiresAt
    }

    public func isFresh(at now: Date) -> Bool {
        expiresAt.timeIntervalSince(now) > Self.refreshMargin
    }
}

public struct RefreshToken: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct GoogleCredential: Hashable, Codable, Sendable {
    public var refreshToken: RefreshToken
    public var account: Account

    public init(refreshToken: RefreshToken, account: Account) {
        self.refreshToken = refreshToken
        self.account = account
    }
}

public struct SignInGrant: Hashable, Sendable {
    public var credential: GoogleCredential
    public var accessToken: AccessToken
}

public enum GoogleOAuth {
    public static let calendarScope = "https://www.googleapis.com/auth/calendar.readonly"
    public static let scopes = ["openid", "email", "profile", calendarScope]

    static let authorizationEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!
    static let revokeEndpoint = URL(string: "https://oauth2.googleapis.com/revoke")!

    public static func authorizationURL(client: GoogleClient, pkce: PKCE, state: String, loginHint: String? = nil) -> URL {
        var query = [
            ("client_id", client.id),
            ("redirect_uri", client.redirectURI),
            ("response_type", "code"),
            ("scope", scopes.joined(separator: " ")),
            ("code_challenge", pkce.challenge),
            ("code_challenge_method", "S256"),
            ("state", state),
        ]
        if let loginHint {
            query.append(("login_hint", loginHint))
        }
        return authorizationEndpoint.appendingQuery(query)
    }

    public static func authorizationCode(from callback: URL, expectedState: String) throws(GoogleError) -> String {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value
        }
        guard value("state") == expectedState else { throw .stateMismatch }
        if let error = value("error") {
            throw error == "access_denied" ? .accessDenied : .authorizationFailed(error)
        }
        guard let code = value("code"), !code.isEmpty else { throw .malformedResponse }
        return code
    }

    public static func codeExchangeRequest(client: GoogleClient, code: String, pkce: PKCE) -> HTTPRequest {
        .form(tokenEndpoint, fields: [
            ("grant_type", "authorization_code"),
            ("code", code),
            ("client_id", client.id),
            ("redirect_uri", client.redirectURI),
            ("code_verifier", pkce.verifier),
        ])
    }

    public static func refreshRequest(client: GoogleClient, refreshToken: RefreshToken) -> HTTPRequest {
        .form(tokenEndpoint, fields: [
            ("grant_type", "refresh_token"),
            ("refresh_token", refreshToken.rawValue),
            ("client_id", client.id),
        ])
    }

    public static func revokeRequest(_ token: RefreshToken) -> HTTPRequest {
        .form(revokeEndpoint, fields: [("token", token.rawValue)])
    }

    public static func signInGrant(from response: HTTPResponse, receivedAt: Date) throws(GoogleError) -> SignInGrant {
        let body = try tokenBody(from: response)
        guard body.scope?.split(separator: " ").contains(Substring(calendarScope)) == true else { throw .missingCalendarScope }
        guard let refreshToken = body.refreshToken else { throw .missingRefreshToken }
        guard let claims = body.idToken.flatMap(IDTokenClaims.init(jwt:)), let email = claims.email else { throw .malformedResponse }
        return SignInGrant(
            credential: GoogleCredential(refreshToken: RefreshToken(rawValue: refreshToken), account: Account(email: email, name: claims.name)),
            accessToken: body.accessToken(receivedAt: receivedAt)
        )
    }

    public static func accessToken(from response: HTTPResponse, receivedAt: Date) throws(GoogleError) -> AccessToken {
        try tokenBody(from: response).accessToken(receivedAt: receivedAt)
    }

    private static func tokenBody(from response: HTTPResponse) throws(GoogleError) -> TokenBody {
        guard response.isSuccess else { throw GoogleError(oauthResponse: response) }
        return try GoogleJSON.decode(TokenBody.self, from: response.body)
    }
}

private struct TokenBody: Decodable {
    var accessToken: String
    var expiresIn: Double
    var refreshToken: String?
    var scope: String?
    var idToken: String?

    func accessToken(receivedAt: Date) -> AccessToken {
        AccessToken(value: accessToken, expiresAt: receivedAt.addingTimeInterval(expiresIn))
    }
}

private struct IDTokenClaims: Decodable {
    var email: String?
    var name: String?

    init?(jwt: String) {
        let parts = jwt.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, let payload = Data(base64URLEncoded: parts[1]),
              let claims = try? GoogleJSON.decode(IDTokenClaims.self, from: payload)
        else { return nil }
        self = claims
    }
}
