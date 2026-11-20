import Foundation

public struct GoogleClient: Hashable, Sendable {
    private static let domain = ".apps.googleusercontent.com"

    public let id: String
    private let prefix: Substring

    public init?(id: String) {
        guard id.hasSuffix(Self.domain) else { return nil }
        let prefix = id.dropLast(Self.domain.count)
        guard !prefix.isEmpty, prefix.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) else { return nil }
        self.id = id
        self.prefix = prefix
    }

    public var callbackScheme: String {
        "com.googleusercontent.apps.\(prefix)"
    }

    public var redirectURI: String {
        "\(callbackScheme):/oauthredirect"
    }
}
