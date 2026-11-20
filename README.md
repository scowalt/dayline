# Dayline

A personal iPhone calendar for Google Calendar, with home-screen and lock-screen widgets. Swift 6, SwiftUI and WidgetKit, with no third-party packages.

<p>
  <img src="docs/screenshots/agenda.png" width="200" alt="Agenda with today's events, a now marker and a Join button">
  <img src="docs/screenshots/event.png" width="200" alt="Event detail with a Google Meet link, location and response">
  <img src="docs/screenshots/home-widgets.png" width="200" alt="Large and medium Up Next widgets on the home screen">
  <img src="docs/screenshots/lock-screen.png" width="200" alt="Inline, rectangular and circular widgets on the lock screen">
</p>

The screenshots use the built-in demo data.

## What it does

- Signs in with a Google account (Workspace or personal) and reads the next 14 days of events from the calendars you show.
- Agenda grouped by day, with all-day and multi-day events, a now marker, Meet join buttons and your response to each invitation.
- Per-calendar show and hide, shared with the widgets.
- An Up Next widget in small, medium and large home-screen sizes and inline, rectangular and circular lock-screen sizes. Tapping an event opens it in the app.

Dayline only reads your calendar (`calendar.readonly`). Calendar data stays on the phone. The Google refresh token is stored in the Keychain. There is no server.

## Layout

| Path | Contents |
| --- | --- |
| `Core/` | `DaylineCore`: the model, Google OAuth and Calendar request building and decoding, agenda grouping and widget timelines. Builds and tests on Linux and macOS. |
| `Sources/DaylineKit/` | Networking, Keychain, the shared snapshot store and preferences, used by the app and the widget. |
| `Sources/Dayline/` | The app. |
| `Sources/DaylineWidget/` | The widget extension. |
| `Support/` | Info.plist and entitlement files. |

## Build and test

Dayline builds with [xtool](https://github.com/xtool-org/xtool) on Linux or macOS.

```sh
swift test --package-path Core
xtool dev build --triple arm64-apple-ios-simulator
```

`scripts/sim` builds locally and runs the app in an iOS simulator on a Mac over SSH. Set `DAYLINE_SIM_HOST` to the Mac's SSH host, or to an empty string to use the simulator on this machine.

```sh
scripts/sim run -demo
scripts/sim screenshot agenda.png
```

The `-demo` launch argument signs in to sample data instead of Google.

## Install on an iPhone

Each `vX.Y.Z` tag publishes an unsigned `Dayline.ipa` on the [releases page](https://github.com/scowalt/dayline/releases). Sign it and install it over USB or Wi-Fi with xtool:

```sh
xtool auth login
xtool install Dayline.ipa
```

With a free Apple ID, the install expires after 7 days. Run `xtool install` again to renew it.

## Google sign-in

Dayline uses the OAuth 2.0 authorization code flow with PKCE for an iOS OAuth client, with no client secret. The client ID in `Sources/DaylineKit/GoogleClient+Dayline.swift` is public by design. A fork needs its own client: create an iOS OAuth client for its bundle ID in Google Cloud, enable the Google Calendar API, and replace the ID.
