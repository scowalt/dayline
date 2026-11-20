import DaylineCore
import Foundation
import Testing

struct GoogleOAuthTests {
    let client = GoogleClient(id: "1234567890-abc.apps.googleusercontent.com")!
    let pkce = PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk", challenge: "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    let receivedAt = Date(timeIntervalSince1970: 1_795_190_400)

    @Test func clientDerivesItsRedirectFromTheClientID() {
        #expect(client.callbackScheme == "com.googleusercontent.apps.1234567890-abc")
        #expect(client.redirectURI == "com.googleusercontent.apps.1234567890-abc:/oauthredirect")
    }

    @Test(arguments: [
        "",
        "1234567890-abc",
        ".apps.googleusercontent.com",
        "12 34.apps.googleusercontent.com",
        "1234567890-abc.apps.googleusercontent.com.example.com",
    ])
    func clientRejectsMissingOrMalformedIDs(id: String) {
        #expect(GoogleClient(id: id) == nil)
    }

    @Test func authorizationURLRequestsCalendarAccessWithPKCE() throws {
        let url = GoogleOAuth.authorizationURL(client: client, pkce: pkce, state: "s+t/a=te")
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))

        #expect(components.scheme == "https")
        #expect(components.host == "accounts.google.com")
        #expect(components.path == "/o/oauth2/v2/auth")
        #expect(query(of: url) == [
            "client_id": "1234567890-abc.apps.googleusercontent.com",
            "redirect_uri": "com.googleusercontent.apps.1234567890-abc:/oauthredirect",
            "response_type": "code",
            "scope": "openid email profile https://www.googleapis.com/auth/calendar.readonly",
            "code_challenge": "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM",
            "code_challenge_method": "S256",
            "state": "s+t/a=te",
            "prompt": "select_account",
        ])
        let encodedQuery = try #require(components.percentEncodedQuery)
        #expect(!encodedQuery.contains("+"))
        #expect(!encodedQuery.contains(" "))
    }

    @Test func authorizationURLCarriesALoginHintOnlyWhenGiven() {
        let hinted = GoogleOAuth.authorizationURL(client: client, pkce: pkce, state: "x", loginHint: "alex.rivera@example.com")
        #expect(query(of: hinted)["login_hint"] == "alex.rivera@example.com")
        #expect(query(of: GoogleOAuth.authorizationURL(client: client, pkce: pkce, state: "x"))["login_hint"] == nil)
    }

    @Test func callbackWithMatchingStateYieldsTheCode() throws {
        let callback = URL(string: "com.googleusercontent.apps.1234567890-abc:/oauthredirect?state=Zm9vYmFy&code=4/0AeanS0bQx7Yk2-Lm_testcode&scope=email%20profile%20https://www.googleapis.com/auth/calendar.readonly%20openid&authuser=0&prompt=consent")!
        #expect(try GoogleOAuth.authorizationCode(from: callback, expectedState: "Zm9vYmFy") == "4/0AeanS0bQx7Yk2-Lm_testcode")
    }

    @Test(arguments: [
        ("?state=other&code=4/0AeanS0b", GoogleError.stateMismatch),
        ("?code=4/0AeanS0b", .stateMismatch),
        ("?error=access_denied&state=other", .stateMismatch),
        ("?error=access_denied&state=Zm9vYmFy", .accessDenied),
        ("?error=admin_policy_enforced&state=Zm9vYmFy", .authorizationFailed("admin_policy_enforced")),
        ("?state=Zm9vYmFy", .malformedResponse),
    ])
    func callbackFailures(query: String, expected: GoogleError) {
        let callback = URL(string: "com.googleusercontent.apps.1234567890-abc:/oauthredirect\(query)")!
        #expect(throws: expected) {
            try GoogleOAuth.authorizationCode(from: callback, expectedState: "Zm9vYmFy")
        }
    }

    @Test func codeExchangePostsTheVerifierWithoutAClientSecret() {
        let request = GoogleOAuth.codeExchangeRequest(client: client, code: "4/0AeanS0b+x", pkce: pkce)
        #expect(request.method == .post)
        #expect(request.url.absoluteString == "https://oauth2.googleapis.com/token")
        #expect(request.headers["Content-Type"] == "application/x-www-form-urlencoded")
        #expect(form(request) == [
            "grant_type": "authorization_code",
            "code": "4/0AeanS0b+x",
            "client_id": "1234567890-abc.apps.googleusercontent.com",
            "redirect_uri": "com.googleusercontent.apps.1234567890-abc:/oauthredirect",
            "code_verifier": "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk",
        ])
        #expect(!String(decoding: request.body ?? Data(), as: UTF8.self).contains("+"))
    }

    @Test func refreshAndRevokePostTheRefreshToken() {
        let token = RefreshToken(rawValue: "1//0gTestRefreshTokenCgYIARAAGBASNwF-L9Ir")
        let refresh = GoogleOAuth.refreshRequest(client: client, refreshToken: token)
        #expect(refresh.method == .post)
        #expect(refresh.url.absoluteString == "https://oauth2.googleapis.com/token")
        #expect(form(refresh) == ["grant_type": "refresh_token", "refresh_token": token.rawValue, "client_id": client.id])

        let revoke = GoogleOAuth.revokeRequest(token)
        #expect(revoke.method == .post)
        #expect(revoke.url.absoluteString == "https://oauth2.googleapis.com/revoke")
        #expect(form(revoke) == ["token": token.rawValue])
    }

    @Test func signInGrantCarriesTheRefreshTokenAccountAndExpiry() throws {
        let grant = try GoogleOAuth.signInGrant(from: GoogleFixtures.response(GoogleFixtures.codeExchange()), receivedAt: receivedAt)
        #expect(grant.credential == GoogleCredential(
            refreshToken: RefreshToken(rawValue: "1//0gTestRefreshTokenCgYIARAAGBASNwF-L9Ir"),
            account: Account(email: "alex.rivera@example.com", name: "Álex Rivera")
        ))
        #expect(grant.accessToken == AccessToken(value: "ya29.a0AeDClZCtestaccesstoken0001", expiresAt: receivedAt.addingTimeInterval(3599)))
    }

    @Test func signInFailsWhenCalendarAccessWasNotGranted() {
        let response = GoogleFixtures.response(GoogleFixtures.codeExchange(scope: "openid https://www.googleapis.com/auth/userinfo.email https://www.googleapis.com/auth/userinfo.profile"))
        #expect(throws: GoogleError.missingCalendarScope) {
            try GoogleOAuth.signInGrant(from: response, receivedAt: receivedAt)
        }
    }

    @Test func signInFailsWithoutARefreshTokenOrAnEmail() {
        #expect(throws: GoogleError.missingRefreshToken) {
            try GoogleOAuth.signInGrant(from: GoogleFixtures.response(GoogleFixtures.codeExchange(refreshToken: false)), receivedAt: receivedAt)
        }
        #expect(throws: GoogleError.malformedResponse) {
            try GoogleOAuth.signInGrant(from: GoogleFixtures.response(GoogleFixtures.codeExchange(idToken: GoogleFixtures.idTokenWithoutEmail)), receivedAt: receivedAt)
        }
        #expect(throws: GoogleError.malformedResponse) {
            try GoogleOAuth.signInGrant(from: GoogleFixtures.response(GoogleFixtures.codeExchange(idToken: "not-a-jwt")), receivedAt: receivedAt)
        }
    }

    @Test func refreshResponseYieldsANewAccessToken() throws {
        let token = try GoogleOAuth.accessToken(from: GoogleFixtures.response(GoogleFixtures.refreshed), receivedAt: receivedAt)
        #expect(token == AccessToken(value: "ya29.a0AeDClZCrefreshedtoken0002", expiresAt: receivedAt.addingTimeInterval(3599)))
    }

    @Test func revokedRefreshTokenMeansTheSessionExpired() {
        #expect(throws: GoogleError.invalidGrant) {
            try GoogleOAuth.accessToken(from: GoogleFixtures.response(GoogleFixtures.invalidGrant, status: 400), receivedAt: receivedAt)
        }
    }

    @Test func otherTokenErrorsCarryGooglesDescription() {
        #expect(throws: GoogleError.server(status: 401, message: "The OAuth client was not found.")) {
            try GoogleOAuth.accessToken(from: GoogleFixtures.response(GoogleFixtures.invalidClient, status: 401), receivedAt: receivedAt)
        }
        #expect(throws: GoogleError.server(status: 503, message: nil)) {
            try GoogleOAuth.accessToken(from: GoogleFixtures.response("<html>Unavailable</html>", status: 503), receivedAt: receivedAt)
        }
    }

    @Test func accessTokenIsRefreshedWithinAMinuteOfExpiry() {
        let token = AccessToken(value: "t", expiresAt: receivedAt.addingTimeInterval(3599))
        #expect(token.isFresh(at: receivedAt))
        #expect(token.isFresh(at: receivedAt.addingTimeInterval(3538)))
        #expect(!token.isFresh(at: receivedAt.addingTimeInterval(3539)))
        #expect(!token.isFresh(at: receivedAt.addingTimeInterval(4000)))
    }

    @Test func bearerHeaderUsesTheAccessToken() {
        let request = HTTPRequest.get(URL(string: "https://www.googleapis.com/calendar/v3/users/me/calendarList")!)
            .authorized(with: AccessToken(value: "ya29.token", expiresAt: receivedAt))
        #expect(request.headers["Authorization"] == "Bearer ya29.token")
    }

    @Test func base64URLMatchesRFC7636AppendixB() throws {
        let verifierOctets = Data([116, 24, 223, 180, 151, 153, 224, 37, 79, 250, 96, 125, 216, 173, 187, 186, 22, 212, 37, 77, 105, 214, 191, 240, 91, 88, 5, 88, 83, 132, 141, 121])
        let challengeOctets = Data([19, 211, 30, 150, 26, 26, 216, 236, 47, 22, 177, 12, 76, 152, 46, 8, 118, 168, 120, 173, 109, 241, 68, 86, 110, 225, 137, 74, 203, 112, 249, 195])
        #expect(verifierOctets.base64URLEncodedString() == "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        #expect(challengeOctets.base64URLEncodedString() == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        #expect(Data(base64URLEncoded: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk") == verifierOctets)
    }

    private func query(of url: URL) -> [String: String] {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
    }

    private func form(_ request: HTTPRequest) -> [String: String] {
        let body = String(decoding: request.body ?? Data(), as: UTF8.self)
        let pairs = body.split(separator: "&").map { pair in
            let parts = pair.split(separator: "=", maxSplits: 1).map { String($0).removingPercentEncoding! }
            return (parts[0], parts.count > 1 ? parts[1] : "")
        }
        return Dictionary(pairs, uniquingKeysWith: { first, _ in first })
    }
}
