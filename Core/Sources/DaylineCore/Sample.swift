import Foundation

extension Snapshot {
    public static func sample(now: Date, calendar: Calendar) -> Snapshot {
        SampleBuilder(now: now, calendar: calendar).snapshot()
    }
}

private struct SampleBuilder {
    let now: Date
    let calendar: Calendar

    let work = CalendarInfo(
        id: CalendarID(rawValue: "alex@example.com"),
        title: "alex@example.com",
        color: RGBColor(hex: "#4285F4")!,
        isPrimary: true,
        isSelectedInGoogle: true,
        canEditEvents: true
    )
    let personal = CalendarInfo(
        id: CalendarID(rawValue: "personal@group.calendar.google.com"),
        title: "Personal",
        color: RGBColor(hex: "#33B679")!,
        isPrimary: false,
        isSelectedInGoogle: true,
        canEditEvents: true
    )
    let family = CalendarInfo(
        id: CalendarID(rawValue: "family@group.calendar.google.com"),
        title: "Family",
        color: RGBColor(hex: "#F4511E")!,
        isPrimary: false,
        isSelectedInGoogle: true,
        canEditEvents: true
    )
    let holidays = CalendarInfo(
        id: CalendarID(rawValue: "en.usa#holiday@group.v.calendar.google.com"),
        title: "Holidays in United States",
        color: RGBColor(hex: "#0B8043")!,
        isPrimary: false,
        isSelectedInGoogle: false
    )

    var today: CivilDate { CivilDate(now, in: calendar) }

    func snapshot() -> Snapshot {
        let start = today.start(in: calendar)
        let end = today.adding(days: 14, in: calendar).start(in: calendar)
        let all = events()
        func eventsOf(_ calendars: [CalendarInfo]) -> [CalendarEvent] {
            let ids = Set(calendars.map(\.id))
            return all.filter { ids.contains($0.calendarID) }
        }
        let personalCalendars = [personal, family]
        let workCalendars = [work, holidays, family]
        return Snapshot(
            accounts: [
                AccountSnapshot(
                    account: Account(email: "alex.rivera@gmail.com", name: "Alex Rivera"),
                    calendars: personalCalendars,
                    events: eventsOf(personalCalendars)
                ),
                AccountSnapshot(
                    account: Account(email: work.id.rawValue, name: "Alex Rivera"),
                    calendars: workCalendars,
                    events: eventsOf(workCalendars)
                ),
            ],
            range: DateInterval(start: start, end: end),
            fetchedAt: now
        )
    }

    func events() -> [CalendarEvent] {
        [
            timed(work, "focus", "Focus time", day: 0, at: 8, 0, minutes: 90, attendance: .accepted),
            timed(work, "standup", "Team standup", day: 0, at: 9, 30, minutes: 15, meet: "abc-defg-hij", attendees: 8, attendance: .accepted),
            timed(work, "design", "Design review: onboarding", day: 0, at: 11, 0, minutes: 60, location: "Room 4B", meet: "kmn-opqr-stu", attendees: 5, attendance: .accepted),
            timed(work, "interview", "Interview loop sync", day: 0, at: 11, 30, minutes: 30, attendees: 4, attendance: .tentative),
            timed(personal, "lunch", "Lunch with Sam", day: 0, at: 12, 30, minutes: 60, location: "Tartine Manufactory"),
            timed(work, "planning", "Q1 planning", day: 0, at: 14, 0, minutes: 90, notes: "Bring the draft roadmap and the hiring plan.", meet: "vwx-yzab-cde", attendees: 12, attendance: .needsAction),
            timed(work, "skip", "Vendor demo", day: 0, at: 16, 0, minutes: 30, attendees: 3, attendance: .declined),
            timed(family, "pickup", "Pick up Maya", day: 0, at: 17, 15, minutes: 30, location: "Lincoln Elementary"),
            timed(personal, "climb", "Climbing", day: 0, at: 19, 0, minutes: 120, location: "Mission Cliffs"),
            allDay(family, "trash", "Trash night", day: 0),
            timed(work, "standup-1", "Team standup", day: 1, at: 9, 30, minutes: 15, meet: "abc-defg-hij", attendees: 8, attendance: .accepted),
            timed(work, "oneonone", "1:1 with Jordan", day: 1, at: 10, 0, minutes: 30, meet: "fgh-ijkl-mno", attendees: 2, attendance: .accepted),
            timed(personal, "dentist", "Dentist", day: 1, at: 15, 0, minutes: 45, location: "450 Sutter St"),
            timed(work, "late", "Sync with Tokyo team", day: 1, at: 22, 30, minutes: 60, meet: "pqr-stuv-wxy", attendees: 6, attendance: .accepted),
            allDay(holidays, "holiday", "Company holiday", day: 3),
            timed(family, "dinner", "Family dinner", day: 3, at: 18, 30, minutes: 120, location: "Grandma's"),
            allDay(personal, "trip", "Trip to Portland", day: 5, through: 7),
            timed(personal, "flight", "Flight AS 1123 SFO → PDX", day: 5, at: 7, 10, minutes: 105, location: "SFO Terminal 2"),
            timed(work, "standup-8", "Team standup", day: 8, at: 9, 30, minutes: 15, meet: "abc-defg-hij", attendees: 8, attendance: .accepted),
            timed(work, "offsite", "Team offsite", day: 9, at: 9, 0, minutes: 480, location: "Presidio Officers' Club", attendees: 14, attendance: .accepted),
        ]
    }

    func timed(
        _ owner: CalendarInfo,
        _ id: String,
        _ title: String,
        day: Int,
        at hour: Int,
        _ minute: Int,
        minutes: Int,
        location: String? = nil,
        notes: String? = nil,
        meet: String? = nil,
        attendees: Int = 0,
        attendance: Attendance? = nil
    ) -> CalendarEvent {
        let start = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: today.adding(days: day, in: calendar).start(in: calendar))!
        return CalendarEvent(
            id: EventID(calendar: owner.id, event: id),
            title: title,
            time: .timed(start: start, end: start.addingTimeInterval(TimeInterval(minutes * 60))),
            location: location,
            notes: notes,
            conferenceURL: meet.flatMap { URL(string: "https://meet.google.com/\($0)") },
            webURL: URL(string: "https://calendar.google.com/calendar/event?eid=\(id)"),
            attendance: attendance,
            attendeeCount: attendees,
            canReschedule: owner.canEditEvents && (attendance == nil || attendance == .accepted)
        )
    }

    func allDay(_ owner: CalendarInfo, _ id: String, _ title: String, day: Int, through last: Int? = nil) -> CalendarEvent {
        CalendarEvent(
            id: EventID(calendar: owner.id, event: id),
            title: title,
            time: .allDay(first: today.adding(days: day, in: calendar), last: today.adding(days: last ?? day, in: calendar)),
            webURL: URL(string: "https://calendar.google.com/calendar/event?eid=\(id)")
        )
    }
}
