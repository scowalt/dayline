import DaylineCore
import Foundation

struct HTTPTransport: Sendable {
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        return URLSession(configuration: configuration)
    }()

    private static let offlineCodes: Set<URLError.Code> = [
        .notConnectedToInternet,
        .networkConnectionLost,
        .timedOut,
        .cannotFindHost,
        .cannotConnectToHost,
        .dnsLookupFailed,
        .dataNotAllowed,
        .internationalRoamingOff,
        .callIsActive,
    ]

    private let userAgent: String

    init(bundle: Bundle = .main) {
        let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String
        userAgent = version.map { "Dayline/\($0)" } ?? "Dayline"
    }

    func send(_ request: HTTPRequest) async throws(CalendarServiceError) -> HTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.httpBody = request.body
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }
        urlRequest.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await Self.session.data(for: urlRequest)
            guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            return HTTPResponse(status: response.statusCode, body: data)
        } catch let error as URLError where Self.offlineCodes.contains(error.code) {
            throw .offline
        } catch let error as URLError where error.code == .cancelled {
            throw .cancelled
        } catch is CancellationError {
            throw .cancelled
        } catch {
            throw .failed(error.localizedDescription)
        }
    }
}
