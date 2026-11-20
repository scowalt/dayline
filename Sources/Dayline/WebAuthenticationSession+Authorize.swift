import AuthenticationServices
import SwiftUI

extension WebAuthenticationSession {
    func authorize(url: URL, callbackScheme: String) async throws -> URL {
        try await authenticate(
            using: url,
            callback: .customScheme(callbackScheme),
            preferredBrowserSession: .shared,
            additionalHeaderFields: [:]
        )
    }
}
