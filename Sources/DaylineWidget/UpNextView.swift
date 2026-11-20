import DaylineCore
import DaylineKit
import SwiftUI
import WidgetKit

struct UpNextView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UpNextEntry

    var body: some View {
        content
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .containerBackground(for: .widget) {
                if family.isAccessory {
                    Color.clear
                } else {
                    Rectangle().fill(.background)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch entry.content {
        case .signedOut:
            SignedOutView(family: family)
        case .agenda(let glance, let colors):
            switch family {
            case .systemSmall:
                SmallUpNextView(now: entry.date, glance: glance, colors: colors)
            case .systemMedium:
                MediumUpNextView(now: entry.date, glance: glance, colors: colors)
            case .accessoryRectangular:
                RectangularUpNextView(now: entry.date, glance: glance, colors: colors)
            case .accessoryInline:
                InlineUpNextView(glance: glance)
            case .accessoryCircular:
                CircularUpNextView(now: entry.date, glance: glance)
            default:
                LargeUpNextView(now: entry.date, glance: glance, colors: colors)
            }
        }
    }
}

struct SignedOutView: View {
    let family: WidgetFamily

    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                Text("Sign in to Dayline")
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: "calendar")
                        .font(.title2)
                }
                .accessibilityLabel("Sign in to Dayline")
            case .accessoryRectangular:
                ViewThatFits(in: .vertical) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Sign in to Dayline")
                            .font(.headline)
                            .widgetAccentable()
                        Text("Your next events will show up here.")
                            .font(.footnote)
                    }
                    Text("Sign in to Dayline")
                        .font(.headline)
                        .widgetAccentable()
                }
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            default:
                VStack(alignment: .leading, spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.title2)
                        .foregroundStyle(.red)
                        .widgetAccentable()
                    Spacer(minLength: 0)
                    Text("Sign in to Dayline")
                        .font(.headline)
                    Text("Your next events will show up here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .widgetURL(DeepLink.today.url)
    }
}

extension WidgetFamily {
    var isAccessory: Bool {
        switch self {
        case .accessoryCircular, .accessoryRectangular, .accessoryInline:
            true
        default:
            false
        }
    }
}
