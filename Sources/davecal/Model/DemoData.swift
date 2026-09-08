import EventKit
import Foundation

/// Made-up calendars and events for screenshots. Turned on by launching with
/// the DAVECAL_DEMO environment variable set; nothing is read or written.
@MainActor
struct DemoData {
    let calendars: [EKCalendar]
    private let accounts: [String: String]
    private let eventStore: EKEventStore
    private let calendar = Calendar.current

    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["DAVECAL_DEMO"] != nil
    }

    init(eventStore: EKEventStore) {
        self.eventStore = eventStore
        func make(_ title: String, _ account: String, _ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> EKCalendar {
            let cal = EKCalendar(for: .event, eventStore: eventStore)
            cal.title = title
            cal.cgColor = CGColor(red: r, green: g, blue: b, alpha: 1)
            return cal
        }
        let home = make("Home", "iCloud", 0.95, 0.55, 0.15)
        let family = make("Family", "iCloud", 0.25, 0.65, 0.35)
        let work = make("Work", "Work account", 0.30, 0.45, 0.85)
        calendars = [home, family, work]
        accounts = [
            home.calendarIdentifier: "iCloud",
            family.calendarIdentifier: "iCloud",
            work.calendarIdentifier: "Work account",
        ]
    }

    func account(for cal: EKCalendar) -> String? {
        accounts[cal.calendarIdentifier]
    }

    /// Events overlapping the range. The same pattern repeats every month.
    func events(from rangeStart: Date, to rangeEnd: Date) -> [EKEvent] {
        var result: [EKEvent] = []
        var month = calendar.startOfMonth(for: rangeStart)
        while month < rangeEnd {
            result += monthEvents(month)
            month = calendar.date(byAdding: .month, value: 1, to: month)!
        }
        return result.filter { $0.startDate < rangeEnd && $0.endDate > rangeStart }
    }

    private func monthEvents(_ month: Date) -> [EKEvent] {
        let home = calendars[0], family = calendars[1], work = calendars[2]
        var events: [EKEvent] = []

        func timed(_ day: Int, _ h1: Int, _ m1: Int, _ h2: Int, _ m2: Int, _ title: String, _ cal: EKCalendar) {
            guard let date = calendar.date(byAdding: .day, value: day - 1, to: month) else { return }
            let e = EKEvent(eventStore: eventStore)
            e.title = title
            e.calendar = cal
            e.startDate = calendar.date(bySettingHour: h1, minute: m1, second: 0, of: date)
            e.endDate = calendar.date(bySettingHour: h2, minute: m2, second: 0, of: date)
            events.append(e)
        }
        func allDay(_ first: Int, _ last: Int, _ title: String, _ cal: EKCalendar) {
            guard let a = calendar.date(byAdding: .day, value: first - 1, to: month),
                  let b = calendar.date(byAdding: .day, value: last, to: month) else { return }
            let e = EKEvent(eventStore: eventStore)
            e.title = title
            e.calendar = cal
            e.isAllDay = true
            e.startDate = a
            e.endDate = b.addingTimeInterval(-1)
            events.append(e)
        }

        let daysInMonth = calendar.range(of: .day, in: .month, for: month)!.count
        for day in 1...daysInMonth {
            let date = calendar.date(byAdding: .day, value: day - 1, to: month)!
            let weekday = calendar.component(.weekday, from: date)
            if (2...6).contains(weekday) { timed(day, 9, 0, 9, 15, "Stand-up", work) }
            if weekday == 3 || weekday == 5 { timed(day, 6, 30, 7, 30, "Gym", home) }
        }
        allDay(1, 5, "Conference", work)
        allDay(9, 11, "Grandparents visiting", family)
        timed(3, 10, 30, 11, 15, "Dentist", home)
        timed(7, 19, 0, 21, 30, "Dinner with Sam and Alex", home)
        allDay(12, 14, "Wellington trip", home)
        timed(12, 7, 45, 8, 50, "Flight NZ423 — Auckland to Wellington", home)
        timed(14, 17, 10, 18, 15, "Flight NZ456 — Wellington to Auckland", home)
        timed(15, 14, 0, 15, 30, "Project review", work)
        timed(15, 15, 30, 16, 0, "1:1 with Priya", work)
        allDay(18, 18, "Mum's birthday", family)
        allDay(20, 26, "School holidays", family)
        timed(22, 8, 0, 12, 0, "Car service", home)
        timed(25, 9, 30, 12, 0, "Quarterly planning", work)
        timed(25, 12, 30, 13, 30, "Lunch with Jordan", work)
        timed(25, 10, 0, 10, 30, "Call the plumber", home)
        timed(28, 16, 15, 16, 45, "Vet: Biscuit", home)
        return events
    }
}
