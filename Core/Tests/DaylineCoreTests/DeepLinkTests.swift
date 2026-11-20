import DaylineCore
import Foundation
import Testing

struct DeepLinkTests {
    @Test(arguments: [
        DeepLink.today,
        .day(CivilDate(year: 2026, month: 3, day: 7)),
        .event(EventID(calendar: CalendarID(rawValue: "en.usa#holiday@group.v.calendar.google.com"), event: "abc_123&x=y")),
    ])
    func roundTripsThroughURL(link: DeepLink) {
        #expect(DeepLink(url: link.url) == link)
    }

    @Test func rejectsForeignAndMalformedURLs() {
        #expect(DeepLink(url: URL(string: "https://today")!) == nil)
        #expect(DeepLink(url: URL(string: "dayline://day?date=2026-13-01")!) == nil)
        #expect(DeepLink(url: URL(string: "dayline://event?id=x")!) == nil)
        #expect(DeepLink(url: URL(string: "dayline://elsewhere")!) == nil)
    }

    @Test func isoDatesArePadded() {
        #expect(CivilDate(year: 2026, month: 3, day: 7).isoString == "2026-03-07")
        #expect(CivilDate(isoString: "2026-3-7") == nil)
    }
}
