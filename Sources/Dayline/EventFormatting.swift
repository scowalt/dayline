import DaylineCore
import Foundation

extension DayPortion {
    var timeText: String {
        switch self {
        case .allDay(let day, let count):
            count > 1 ? "Day \(day) of \(count)" : "All day"
        case .within(let start, let end):
            start == end ? start.timeText : "\(start.timeText) – \(end.timeText)"
        case .startsThisDay(let start, let end):
            "\(start.timeText) – \(end.timeText)"
        case .endsThisDay(let end):
            "Until \(end.timeText)"
        case .coversThisDay:
            "All day"
        }
    }
}

extension Date {
    var timeText: String {
        formatted(date: .omitted, time: .shortened)
    }
}

extension Attendance {
    var awaitsDecision: Bool {
        self == .tentative || self == .needsAction
    }

    var badge: String? {
        switch self {
        case .tentative: "Maybe"
        case .needsAction: "Reply needed"
        case .accepted, .declined: nil
        }
    }

    var label: String {
        switch self {
        case .accepted: "Going"
        case .tentative: "Maybe"
        case .declined: "Declined"
        case .needsAction: "Reply needed"
        }
    }

    var symbolName: String {
        switch self {
        case .accepted: "checkmark.circle.fill"
        case .tentative: "questionmark.circle.fill"
        case .declined: "xmark.circle.fill"
        case .needsAction: "circle.dashed"
        }
    }
}
