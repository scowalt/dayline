import Foundation

public struct HTTPRequest: Hashable, Sendable {
    public enum Method: String, Hashable, Sendable {
        case get = "GET"
        case post = "POST"
        case patch = "PATCH"
    }

    public var method: Method
    public var url: URL
    public var headers: [String: String]
    public var body: Data?

    public init(method: Method, url: URL, headers: [String: String] = [:], body: Data? = nil) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
    }

    public static func get(_ url: URL, query: [(String, String)] = []) -> HTTPRequest {
        HTTPRequest(method: .get, url: url.appendingQuery(query))
    }

    public static func form(_ url: URL, fields: [(String, String)]) -> HTTPRequest {
        HTTPRequest(
            method: .post,
            url: url,
            headers: ["Content-Type": "application/x-www-form-urlencoded"],
            body: Data(FormEncoding.encode(fields).utf8)
        )
    }

    static func json(_ method: Method, _ url: URL, body: some Encodable) -> HTTPRequest {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return HTTPRequest(method: method, url: url, headers: ["Content-Type": "application/json"], body: try! encoder.encode(body))
    }

    public func authorized(with token: AccessToken) -> HTTPRequest {
        var request = self
        request.headers["Authorization"] = "Bearer \(token.value)"
        return request
    }
}

public struct HTTPResponse: Hashable, Sendable {
    public var status: Int
    public var body: Data

    public init(status: Int, body: Data) {
        self.status = status
        self.body = body
    }

    public var isSuccess: Bool { (200..<300).contains(status) }
}

enum FormEncoding {
    private static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    static func encode(_ fields: [(String, String)]) -> String {
        fields.map { "\(escape($0.0))=\(escape($0.1))" }.joined(separator: "&")
    }

    static func escape(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved)!
    }
}

extension URL {
    func appendingQuery(_ items: [(String, String)]) -> URL {
        guard !items.isEmpty, var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return self }
        components.percentEncodedQuery = FormEncoding.encode(items)
        return components.url!
    }

    func appendingPathSegment(_ segment: String) -> URL {
        URL(string: absoluteString + "/" + FormEncoding.escape(segment))!
    }
}
