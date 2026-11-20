import DaylineCore
import DaylineKit
import SwiftUI

struct EventRow: View {
    let event: CalendarEvent
    let color: Color
    let portion: DayPortion
    let hasEnded: Bool
    let isJoinable: Bool

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 12) {
                CalendarBar(color: color, isOutlined: event.attendance?.awaitsDecision == true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(event.title)
                        .font(.body.weight(.medium))
                        .strikethrough(isDeclined)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        Text(portion.timeText)
                            .foregroundStyle(.secondary)
                        if let badge = event.attendance?.badge {
                            AttendanceBadge(text: badge)
                                .accessibilityHidden(true)
                        }
                    }
                    .font(.subheadline)
                    if let location = event.location, !location.isEmpty {
                        Text(location)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(.vertical, 2)
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            .accessibilityValue(accessibilityStatus)
            Spacer(minLength: 0)
            if isJoinable, !isDeclined, let url = event.conferenceURL {
                JoinButton(url: url)
            }
        }
        .opacity(hasEnded || isDeclined ? 0.5 : 1)
    }

    private var isDeclined: Bool { event.attendance == .declined }

    private var accessibilityStatus: String {
        var parts: [String] = []
        if let attendance = event.attendance, attendance != .accepted {
            parts.append(attendance.label)
        }
        if hasEnded {
            parts.append("Ended")
        }
        return parts.joined(separator: ", ")
    }
}

struct AllDayRow: View {
    let event: CalendarEvent
    let color: Color
    let portion: DayPortion

    var body: some View {
        HStack(spacing: 12) {
            CalendarBar(color: color, isOutlined: false)
            Text(event.title)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(portion.timeText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }
}

struct NowMarker: View {
    let now: Date

    var body: some View {
        HStack(spacing: 0) {
            Circle()
                .fill(.red)
                .frame(width: 10, height: 10)
            Rectangle()
                .fill(.red)
                .frame(height: 2)
        }
        .padding(.leading, -3)
        .padding(.vertical, 2)
        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 0))
        .accessibilityElement()
        .accessibilityLabel("Now, \(now.formatted(date: .omitted, time: .shortened))")
    }
}

struct CalendarBar: View {
    let color: Color
    let isOutlined: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(isOutlined ? color.opacity(0.18) : color)
            .strokeBorder(color, lineWidth: isOutlined ? 1.5 : 0)
            .frame(width: 4)
            .frame(maxHeight: .infinity)
            .accessibilityHidden(true)
    }
}

struct JoinButton: View {
    let url: URL
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            openURL(url)
        } label: {
            Label("Join", systemImage: "video.fill")
                .labelStyle(.titleAndIcon)
                .font(.subheadline.weight(.semibold))
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .accessibilityHint("Opens the video call")
    }
}

private struct AttendanceBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.orange)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(.orange.opacity(0.15), in: .capsule)
    }
}

extension Snapshot {
    func color(of event: CalendarEvent) -> Color {
        Color(event.color ?? calendar(event.calendarID)?.color ?? RGBColor(red: 0.56, green: 0.56, blue: 0.58))
    }
}
