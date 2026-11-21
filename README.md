# Dayline

A personal iPhone calendar for Google Calendar, with home-screen and lock-screen widgets. Swift 6, SwiftUI and WidgetKit, with no third-party packages.

<p>
  <img src="docs/screenshots/agenda.png" width="200" alt="Agenda with today's events, a now marker and a Join button">
  <img src="docs/screenshots/event.png" width="200" alt="Event detail with a Google Meet link, location and response">
  <img src="docs/screenshots/home-widgets.png" width="200" alt="Large and medium Up Next widgets on the home screen">
  <img src="docs/screenshots/lock-screen.png" width="200" alt="Inline, rectangular and circular widgets on the lock screen">
  <img src="docs/screenshots/settings.png" width="200" alt="Settings with two Google accounts, each with its calendars and a Sign Out button">
</p>

The screenshots use the built-in demo data.

## What it does

- Signs in with one or more Google accounts (Workspace or personal) and reads the next 14 days of events from the calendars you show. The agenda and widgets merge every account. A calendar shared with two of your accounts appears once, under the account with the most access to it, such as the account that owns it. When two accounts have the same access, the one you signed in to first gets it.
- Settings lists each account with its calendars. You can add an account or sign out of one. If Google ends one account's session, its last events stay on screen and Settings offers Sign In Again. The other accounts keep working.
- Agenda grouped by day, with all-day and multi-day events, a now marker, Meet join buttons and your response to each invitation.
- Day and 3 Days views on an hourly grid, picked from the layout menu. Swipe left or right to change days. Touch and hold an event, then drag it to another time or day to move it. Drops snap to 15 minutes. If the event has other guests, Dayline asks whether to send them an update. If Google refuses the change, the event goes back to where it was.
- Delete an event from its detail screen. For a repeating event, Dayline asks whether to delete this event, this and following events, or all events. If you organize the event and it has other guests, Dayline asks whether to send them a cancellation. If Google refuses, the event comes back.
- Per-calendar show and hide, shared with the widgets.
- Share Diagnostics in Settings exports a text report for debugging sync: each account's calendars with your access and event counts, and the last 500 requests the app and widgets sent to Google, with status codes and Google's error messages. It leaves out event details and tokens.
- Hide events by title, such as the "Personal event" blocks a calendar sync app copies in. Add a title in Settings or from an event's detail screen. Matching is exact but ignores capitalization, and the widgets hide the same events.
- An Up Next widget in small, medium and large home-screen sizes and inline, rectangular and circular lock-screen sizes. Tapping an event opens it in the app.

Dayline reads your calendars, can move an event you drag in the Day or 3 Days view, and can delete an event you choose to delete (`calendar.readonly` plus `calendar.events`). It changes only the start and end of an event you organize, or one whose organizer lets guests modify it, on a calendar you can edit. It deletes only events on a calendar you can edit. "This and following events" ends the series before the chosen event by changing its repeat rule. Calendar data stays on the phone. Each account's Google refresh token is stored in the Keychain. There is no server.

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

### TestFlight

Every push to `main`, and a scheduled run on the 1st and 15th of each month, builds Dayline, signs it for the App Store and uploads it to TestFlight. The TestFlight app on the phone installs each build as it arrives. A TestFlight build stops opening 90 days after upload, and the scheduled runs keep a fresh one there. GitHub turns off scheduled workflows in a public repository after 60 days without activity, so check the Actions tab if the repository goes quiet.

One-time setup, with an App Store Connect team API key (App Manager role) in `ASC_KEY_ID`, `ASC_ISSUER_ID` and `ASC_KEY_PATH`:

1. `scripts/appstore ids` registers the App IDs `com.scowalt.dayline` and `com.scowalt.dayline.widget` with App Groups turned on.
2. In the developer portal, configure App Groups on both App IDs to include `group.com.scowalt.dayline`. The API can't do this.
3. In App Store Connect, create the app with bundle ID `com.scowalt.dayline`, and add yourself to an internal testing group.
4. `scripts/appstore signing` creates an Apple Distribution certificate and the App Store profiles in `~/.config/dayline/signing`.
5. `scripts/appstore secrets` stores the key, certificate and profiles in the `testflight` environment, which only `main` can use.

The certificate expires after a year. `scripts/appstore renew` repeats steps 4 and 5 when the certificate is within 30 days of expiring or a profile has changed, and prints nothing otherwise. A monthly bb automation on the build machine runs it from `origin/main`.

### xtool

Each `vX.Y.Z` tag publishes an unsigned `Dayline.ipa` on the [releases page](https://github.com/scowalt/dayline/releases). Sign it and install it over USB or Wi-Fi with xtool:

```sh
xtool auth login
xtool install Dayline.ipa
```

With a free Apple ID, the install expires after 7 days. Run `xtool install` again to renew it.

With a paid Apple Developer Program membership, log in with an App Store Connect API key (App Manager role) and the install lasts a year. The API can't assign app groups, so do that once in the developer portal before the first install:

1. Register the App Group `group.com.scowalt.dayline`.
2. Run `xtool install` once. It fails, but it registers the App IDs `XTL-<prefix>.com.scowalt.dayline` and `XTL-<prefix>.com.scowalt.dayline.widget`.
3. Turn on App Groups for both App IDs and select `group.com.scowalt.dayline`.
4. Run `xtool install` again.

## Google sign-in

Dayline uses the OAuth 2.0 authorization code flow with PKCE for an iOS OAuth client, with no client secret. The client ID in `Sources/DaylineKit/GoogleClient+Dayline.swift` is public by design. A fork needs its own client: create an iOS OAuth client for its bundle ID in Google Cloud, enable the Google Calendar API, and replace the ID.

Accounts that signed in before Dayline could move events have only the read-only scope. The first time you move or delete an event in one of them, Dayline asks you to sign in to that account again and allow changes.
