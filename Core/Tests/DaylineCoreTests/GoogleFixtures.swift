import DaylineCore
import Foundation

enum GoogleFixtures {
    static func response(_ json: String, status: Int = 200) -> HTTPResponse {
        HTTPResponse(status: status, body: Data(json.utf8))
    }

    static let idToken = jwt(claims: #"{"iss":"https://accounts.google.com","azp":"1234567890-abc.apps.googleusercontent.com","aud":"1234567890-abc.apps.googleusercontent.com","sub":"110169484474386276334","email":"alex.rivera@example.com","email_verified":true,"at_hash":"HK6E_P6Dh8Y93mRNtsDB1Q","name":"Álex Rivera","picture":"https://lh3.googleusercontent.com/a/ACg8ocK","given_name":"Álex","family_name":"Rivera","iat":1795190400,"exp":1795194000}"#)

    static let idTokenWithoutEmail = jwt(claims: #"{"iss":"https://accounts.google.com","sub":"110169484474386276334","email_verified":true,"iat":1795190400,"exp":1795194000}"#)

    private static func jwt(claims: String) -> String {
        let header = #"{"alg":"RS256","kid":"5aaff47c21d06e266cce395b2145c7c6d4730ea5","typ":"JWT"}"#
        return [header, claims, "signature"]
            .map { Data($0.utf8).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
            .joined(separator: ".")
    }

    static func codeExchange(scope: String = "https://www.googleapis.com/auth/userinfo.email https://www.googleapis.com/auth/calendar.readonly openid https://www.googleapis.com/auth/userinfo.profile", refreshToken: Bool = true, idToken: String = idToken) -> String {
        """
        {
          "access_token": "ya29.a0AeDClZCtestaccesstoken0001",
          "expires_in": 3599,
          \(refreshToken ? #""refresh_token": "1//0gTestRefreshTokenCgYIARAAGBASNwF-L9Ir","# : "")
          "scope": "\(scope)",
          "token_type": "Bearer",
          "id_token": "\(idToken)"
        }
        """
    }

    static let refreshed = """
        {
          "access_token": "ya29.a0AeDClZCrefreshedtoken0002",
          "expires_in": 3599,
          "scope": "https://www.googleapis.com/auth/calendar.readonly https://www.googleapis.com/auth/userinfo.profile openid https://www.googleapis.com/auth/userinfo.email",
          "token_type": "Bearer",
          "id_token": "\(idToken)"
        }
        """

    static let invalidGrant = """
        {
          "error": "invalid_grant",
          "error_description": "Token has been expired or revoked."
        }
        """

    static let invalidClient = """
        {
          "error": "invalid_client",
          "error_description": "The OAuth client was not found."
        }
        """

    static let unauthenticated = """
        {
          "error": {
            "code": 401,
            "message": "Request had invalid authentication credentials. Expected OAuth 2 access token, login cookie or other valid authentication credential. See https://developers.google.com/identity/sign-in/web/devconsole-project.",
            "errors": [
              {
                "message": "Invalid Credentials",
                "domain": "global",
                "reason": "authError",
                "location": "Authorization",
                "locationType": "header"
              }
            ],
            "status": "UNAUTHENTICATED"
          }
        }
        """

    static let insufficientScope = """
        {
          "error": {
            "code": 403,
            "message": "Request had insufficient authentication scopes.",
            "errors": [
              {
                "message": "Insufficient Permission",
                "domain": "global",
                "reason": "insufficientPermissions"
              }
            ],
            "status": "PERMISSION_DENIED",
            "details": [
              {
                "@type": "type.googleapis.com/google.rpc.ErrorInfo",
                "reason": "ACCESS_TOKEN_SCOPE_INSUFFICIENT",
                "domain": "googleapis.com",
                "metadata": { "service": "calendar-json.googleapis.com", "method": "calendar.v3.Events.Patch" }
              }
            ]
          }
        }
        """

    static let rateLimited = """
        {
          "error": {
            "errors": [
              {
                "domain": "usageLimits",
                "reason": "rateLimitExceeded",
                "message": "Rate Limit Exceeded"
              }
            ],
            "code": 403,
            "message": "Rate Limit Exceeded"
          }
        }
        """

    static let calendarListFirstPage = #"""
        {
          "kind": "calendar#calendarList",
          "etag": "\"p32g9nb5sq1p8g0o\"",
          "nextPageToken": "calendars-p2",
          "items": [
            {
              "kind": "calendar#calendarListEntry",
              "etag": "\"1700000000000000\"",
              "id": "alex.rivera@example.com",
              "summary": "alex.rivera@example.com",
              "timeZone": "America/New_York",
              "colorId": "15",
              "backgroundColor": "#9fc6e7",
              "foregroundColor": "#000000",
              "selected": true,
              "accessRole": "owner",
              "defaultReminders": [{ "method": "popup", "minutes": 10 }],
              "notificationSettings": { "notifications": [{ "type": "eventCreation", "method": "email" }] },
              "primary": true,
              "conferenceProperties": { "allowedConferenceSolutionTypes": ["hangoutsMeet"] }
            },
            {
              "kind": "calendar#calendarListEntry",
              "etag": "\"1700000000000001\"",
              "id": "c_8f1b2a90d3e44c1e@group.calendar.google.com",
              "summary": "Platform Team",
              "summaryOverride": "Team",
              "timeZone": "America/Los_Angeles",
              "colorId": "8",
              "backgroundColor": "#16a765",
              "foregroundColor": "#000000",
              "selected": true,
              "accessRole": "reader",
              "defaultReminders": [],
              "conferenceProperties": { "allowedConferenceSolutionTypes": ["hangoutsMeet"] }
            },
            {
              "kind": "calendar#calendarListEntry",
              "etag": "\"1700000000000002\"",
              "id": "en.usa#holiday@group.v.calendar.google.com",
              "summary": "Holidays in United States",
              "description": "Holidays and Observances in United States",
              "timeZone": "America/New_York",
              "colorId": "8",
              "backgroundColor": "#b1365f",
              "foregroundColor": "#ffffff",
              "accessRole": "reader",
              "defaultReminders": [],
              "conferenceProperties": { "allowedConferenceSolutionTypes": ["hangoutsMeet"] }
            }
          ]
        }
        """#

    static let calendarListLastPage = #"""
        {
          "kind": "calendar#calendarList",
          "etag": "\"p32g9nb5sq1p8g0p\"",
          "items": [
            {
              "kind": "calendar#calendarListEntry",
              "id": "addressbook#contacts@group.v.calendar.google.com",
              "summary": "Birthdays",
              "colorId": "13",
              "backgroundColor": "#92e1c0",
              "foregroundColor": "#000000",
              "selected": false,
              "hidden": true,
              "accessRole": "reader"
            }
          ]
        }
        """#

    static let eventsFirstPage = #"""
        {
          "kind": "calendar#events",
          "etag": "\"p33cb5ce7g6ho80o\"",
          "summary": "alex.rivera@example.com",
          "updated": "2026-11-19T21:04:11.512Z",
          "timeZone": "America/New_York",
          "accessRole": "owner",
          "defaultReminders": [{ "method": "popup", "minutes": 10 }],
          "nextPageToken": "events-p2",
          "items": [
            {
              "kind": "calendar#event",
              "etag": "\"3460000000000000\"",
              "id": "5qk8c1v3f0d2t9n6e4m7b1a0s8",
              "status": "confirmed",
              "htmlLink": "https://www.google.com/calendar/event?eid=NXFrOGMxdjNmMGQydDluNmU0bTdiMWEwczggYWxleC5yaXZlcmFAZXhhbXBsZS5jb20",
              "created": "2026-10-01T16:00:00.000Z",
              "updated": "2026-11-18T21:04:11.512Z",
              "summary": "Design review: onboarding",
              "description": "Agenda:<br><ul><li>Flows</li><li>Copy</li></ul>Spec: <a href=\"https://docs.example.com/d/123?a=1&amp;b=2\">Onboarding spec</a><br>Tom &amp; Jerry&nbsp;attend &lt;both&gt; &#8212; see <a href=\"https://example.com/x\">https://example.com/x</a>",
              "location": "Room 4B",
              "colorId": "11",
              "creator": { "email": "sam@example.com" },
              "organizer": { "email": "sam@example.com" },
              "start": { "dateTime": "2026-11-20T11:00:00-05:00", "timeZone": "America/New_York" },
              "end": { "dateTime": "2026-11-20T12:00:00-05:00", "timeZone": "America/New_York" },
              "iCalUID": "5qk8c1v3f0d2t9n6e4m7b1a0s8@google.com",
              "sequence": 2,
              "attendees": [
                { "email": "sam@example.com", "organizer": true, "responseStatus": "accepted" },
                { "email": "alex.rivera@example.com", "self": true, "responseStatus": "accepted" },
                { "email": "jordan@example.com", "responseStatus": "tentative" },
                { "email": "c_1889a7@resource.calendar.google.com", "displayName": "Room 4B", "resource": true, "responseStatus": "accepted" }
              ],
              "hangoutLink": "https://meet.google.com/kmn-opqr-stu",
              "conferenceData": {
                "entryPoints": [
                  { "entryPointType": "more", "uri": "https://tel.meet/kmn-opqr-stu?pin=1234567890123" },
                  { "entryPointType": "video", "uri": "https://meet.google.com/kmn-opqr-stu", "label": "meet.google.com/kmn-opqr-stu" },
                  { "entryPointType": "phone", "uri": "tel:+1-650-555-0100", "label": "+1 650-555-0100", "pin": "123456789", "regionCode": "US" }
                ],
                "conferenceSolution": { "key": { "type": "hangoutsMeet" }, "name": "Google Meet", "iconUri": "https://fonts.gstatic.com/s/i/productlogos/meet_2020q4/v6/web-512dp/logo_meet_2020q4_color_2x_web_512dp.png" },
                "conferenceId": "kmn-opqr-stu"
              },
              "reminders": { "useDefault": true },
              "eventType": "default"
            },
            {
              "kind": "calendar#event",
              "id": "zoomsync01",
              "status": "confirmed",
              "guestsCanModify": true,
              "htmlLink": "https://www.google.com/calendar/event?eid=em9vbXN5bmMwMQ",
              "summary": "Vendor call",
              "description": "Join Zoom Meeting\nhttps://us02web.zoom.us/j/81234567890?pwd=abc\n\nMeeting ID: 812 3456 7890\n\n\n\nOne tap mobile <tel:+16465588656,,81234567890#>",
              "start": { "dateTime": "2026-11-20T15:30:00Z" },
              "end": { "dateTime": "2026-11-20T16:00:00Z" },
              "attendees": [
                { "email": "alex.rivera@example.com", "self": true, "responseStatus": "tentative" },
                { "email": "rep@vendor.example", "organizer": true, "responseStatus": "accepted" }
              ],
              "conferenceData": {
                "entryPoints": [
                  { "entryPointType": "video", "uri": "https://us02web.zoom.us/j/81234567890?pwd=abc", "label": "us02web.zoom.us/j/81234567890?pwd=abc", "meetingCode": "81234567890", "passcode": "abc" }
                ],
                "conferenceSolution": { "key": { "type": "addOn" }, "name": "Zoom Meeting" },
                "conferenceId": "81234567890"
              },
              "eventType": "default"
            },
            {
              "kind": "calendar#event",
              "id": "legacyhangout",
              "status": "confirmed",
              "summary": "  Weekly sync  ",
              "start": { "dateTime": "2026-11-20T23:30:00+09:00", "timeZone": "Asia/Tokyo" },
              "end": { "dateTime": "2026-11-21T00:30:00+09:00", "timeZone": "Asia/Tokyo" },
              "hangoutLink": "https://meet.google.com/abc-defg-hij",
              "attendees": [
                { "email": "alex.rivera@example.com", "self": true, "responseStatus": "needsAction" },
                { "email": "kenji@example.jp", "organizer": true, "responseStatus": "accepted" },
                { "email": "mika@example.jp", "responseStatus": "declined" }
              ]
            },
            {
              "kind": "calendar#event",
              "id": "busyblock",
              "status": "confirmed",
              "organizer": { "email": "alex.rivera@example.com", "self": true },
              "locked": true,
              "visibility": "private",
              "start": { "dateTime": "2026-11-21T09:00:00-05:00" },
              "end": { "dateTime": "2026-11-21T09:30:00-05:00" },
              "attendees": [
                { "email": "alex.rivera@example.com", "self": true, "responseStatus": "declined" }
              ],
              "conferenceData": {
                "entryPoints": [
                  { "entryPointType": "phone", "uri": "tel:+1-650-555-0101", "pin": "987654" }
                ],
                "conferenceSolution": { "key": { "type": "addOn" }, "name": "Dial-in" }
              }
            },
            {
              "kind": "calendar#event",
              "id": "blanktitle",
              "status": "tentative",
              "summary": "   ",
              "description": "   \n  ",
              "location": "",
              "organizer": { "email": "alex.rivera@example.com", "self": true },
              "start": { "dateTime": "2026-11-22T10:00:00-05:00" },
              "end": { "dateTime": "2026-11-22T10:00:00-05:00" }
            }
          ]
        }
        """#

    static let eventsLastPage = #"""
        {
          "kind": "calendar#events",
          "summary": "alex.rivera@example.com",
          "timeZone": "America/New_York",
          "items": [
            {
              "kind": "calendar#event",
              "id": "trashnight_20261120",
              "status": "confirmed",
              "summary": "Trash night",
              "colorId": "5",
              "start": { "date": "2026-11-20" },
              "end": { "date": "2026-11-21" },
              "recurringEventId": "trashnight",
              "originalStartTime": { "date": "2026-11-20" },
              "transparency": "transparent"
            },
            {
              "kind": "calendar#event",
              "id": "portlandtrip",
              "status": "confirmed",
              "summary": "Trip to Portland",
              "start": { "date": "2026-11-30" },
              "end": { "date": "2026-12-03" }
            },
            {
              "kind": "calendar#event",
              "id": "redeye",
              "status": "confirmed",
              "summary": "Flight AS 1123 PDX → JFK",
              "location": "PDX Terminal C",
              "start": { "dateTime": "2026-12-02T22:15:00-08:00", "timeZone": "America/Los_Angeles" },
              "end": { "dateTime": "2026-12-03T06:40:00-05:00", "timeZone": "America/New_York" }
            },
            {
              "kind": "calendar#event",
              "id": "cancelledstandup_20261123T143000Z",
              "status": "cancelled",
              "summary": "Team standup",
              "start": { "dateTime": "2026-11-23T09:30:00-05:00" },
              "end": { "dateTime": "2026-11-23T09:45:00-05:00" },
              "recurringEventId": "cancelledstandup"
            },
            {
              "kind": "calendar#event",
              "id": "cancelledexception",
              "status": "cancelled",
              "recurringEventId": "cancelledstandup",
              "originalStartTime": { "dateTime": "2026-11-24T09:30:00-05:00" }
            },
            {
              "kind": "calendar#event",
              "id": "wfh_20261120",
              "status": "confirmed",
              "summary": "Home",
              "start": { "date": "2026-11-20" },
              "end": { "date": "2026-11-21" },
              "visibility": "public",
              "transparency": "transparent",
              "eventType": "workingLocation",
              "workingLocationProperties": { "type": "homeOffice", "homeOffice": {} }
            },
            {
              "kind": "calendar#event",
              "id": "ooo",
              "status": "confirmed",
              "summary": "Out of office",
              "start": { "dateTime": "2026-11-27T00:00:00-05:00" },
              "end": { "dateTime": "2026-11-28T00:00:00-05:00" },
              "eventType": "outOfOffice",
              "outOfOfficeProperties": { "autoDeclineMode": "declineOnlyNewConflictingInvitations" }
            }
          ]
        }
        """#
}
