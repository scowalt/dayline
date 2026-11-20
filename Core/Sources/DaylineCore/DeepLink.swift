import Foundation

public enum DeepLink: Hashable, Sendable {
    case today
    case day(CivilDate)
    case event(EventID)

    public static let scheme = "dayline"

    public var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        switch self {
        case .today:
            components.host = "today"
        case .day(let date):
            components.host = "day"
            components.queryItems = [URLQueryItem(name: "date", value: date.isoString)]
        case .event(let id):
            components.host = "event"
            components.queryItems = [
                URLQueryItem(name: "calendar", value: id.calendar.rawValue),
                URLQueryItem(name: "id", value: id.event),
            ]
        }
        return components.url!
    }

    public init?(url: URL) {
        guard url.scheme == Self.scheme, let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let query = Dictionary((components.queryItems ?? []).compactMap { item in item.value.map { (item.name, $0) } }, uniquingKeysWith: { first, _ in first })
        switch components.host {
        case "today":
            self = .today
        case "day":
            guard let date = query["date"].flatMap(CivilDate.init(isoString:)) else { return nil }
            self = .day(date)
        case "event":
            guard let calendar = query["calendar"], let event = query["id"] else { return nil }
            self = .event(EventID(calendar: CalendarID(rawValue: calendar), event: event))
        default:
            return nil
        }
    }
}

extension CivilDate {
    public var isoString: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public init?(isoString: String) {
        let parts = isoString.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month), (1...31).contains(day)
        else { return nil }
        self.init(year: year, month: month, day: day)
    }
}
