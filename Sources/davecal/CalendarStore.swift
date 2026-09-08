import EventKit
import Foundation
import Observation

/// Holds the EventKit store and the events for the range currently on screen.
@MainActor
@Observable
final class CalendarStore {
    let eventStore = EKEventStore()
    var authorized = false
    var denied = false
    var events: [EKEvent] = []
    var calendars: [EKCalendar] = []
    /// Events from now for the next two weeks, for the sidebar.
    var upcoming: [EKEvent] = []

    /// Calendars switched off in the sidebar. Stored as a set of identifiers so
    /// everything defaults to on.
    var disabledIDs: Set<String> = CalendarStore.loadSet("disabledCalendars") {
        didSet { CalendarStore.saveSet(disabledIDs, "disabledCalendars") }
    }
    /// While a calendar name is held down, only that calendar is shown.
    var soloID: String?

    private var loadedRange: (start: Date, end: Date)?

    init() {
        NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: eventStore, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
    }

    func requestAccess() async {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            authorized = true
        case .denied, .restricted:
            denied = true
        default:
            do {
                authorized = try await eventStore.requestFullAccessToEvents()
                denied = !authorized
            } catch {
                denied = true
            }
        }
        reload()
    }

    func load(start: Date, end: Date) {
        loadedRange = (start, end)
        reload()
    }

    func reload() {
        guard authorized else { return }
        calendars = eventStore.calendars(for: .event).sorted {
            ($0.source.title, $0.title) < ($1.source.title, $1.title)
        }
        let now = Date.now
        let horizon = calendar.date(byAdding: .day, value: 14, to: now)!
        upcoming = eventStore.events(matching: eventStore.predicateForEvents(withStart: now, end: horizon, calendars: nil))
            .filter { !($0.isAllDay && isMultiDay($0)) }
            .sorted { a, b in
                if a.isAllDay != b.isAllDay { return a.isAllDay }
                return a.startDate < b.startDate
            }
        guard let range = loadedRange else { return }
        let predicate = eventStore.predicateForEvents(
            withStart: range.start, end: range.end, calendars: nil)
        events = eventStore.events(matching: predicate)
    }

    private var calendar: Calendar { .current }

    func isMultiDay(_ event: EKEvent) -> Bool {
        guard let start = event.startDate, let end = event.endDate else { return false }
        return !calendar.isDate(start, inSameDayAs: end.addingTimeInterval(-1))
    }

    /// Whether the sidebar settings (checkbox, hold-to-solo) allow this event to show.
    func shows(_ event: EKEvent) -> Bool {
        guard let id = event.calendar?.calendarIdentifier else { return true }
        if let soloID { return id == soloID }
        return !disabledIDs.contains(id)
    }

    /// Upcoming events that pass the sidebar settings, grouped by day in order.
    var upcomingByDay: [(day: Date, events: [EKEvent])] {
        var groups: [(Date, [EKEvent])] = []
        for event in upcoming where shows(event) {
            let day = calendar.startOfDay(for: event.startDate)
            if let i = groups.firstIndex(where: { $0.0 == day }) {
                groups[i].1.append(event)
            } else {
                groups.append((day, [event]))
            }
        }
        return groups.sorted { $0.0 < $1.0 }.map { (day: $0.0, events: $0.1) }
    }

    func isEnabled(_ calendar: EKCalendar) -> Bool { !disabledIDs.contains(calendar.calendarIdentifier) }

    func setEnabled(_ calendar: EKCalendar, _ on: Bool) {
        if on { disabledIDs.remove(calendar.calendarIdentifier) } else { disabledIDs.insert(calendar.calendarIdentifier) }
    }

    /// Calendars grouped by account, in account then calendar name order.
    var calendarsByAccount: [(account: String, calendars: [EKCalendar])] {
        var groups: [(String, [EKCalendar])] = []
        for cal in calendars {
            let name = cal.source.title
            if let i = groups.firstIndex(where: { $0.0 == name }) {
                groups[i].1.append(cal)
            } else {
                groups.append((name, [cal]))
            }
        }
        return groups.map { (account: $0.0, calendars: $0.1) }
    }

    private static func loadSet(_ key: String) -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }
    private static func saveSet(_ set: Set<String>, _ key: String) {
        UserDefaults.standard.set(Array(set).sorted(), forKey: key)
    }

    /// Events keyed by the start of each day they touch. A multi-day event
    /// appears under every day it covers.
    func eventsByDay(calendar: Calendar) -> [Date: [EKEvent]] {
        var result: [Date: [EKEvent]] = [:]
        for event in events where shows(event) {
            guard let start = event.startDate, let end = event.endDate else { continue }
            let firstDay = calendar.startOfDay(for: start)
            // End dates are exclusive (an all-day event ends at 00:00 the next
            // day), so step back one second before finding the last day.
            var lastDay = calendar.startOfDay(for: end.addingTimeInterval(-1))
            if lastDay < firstDay { lastDay = firstDay }
            var day = firstDay
            while day <= lastDay {
                result[day, default: []].append(event)
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
        }
        for key in result.keys {
            result[key]?.sort { a, b in
                if a.isAllDay != b.isAllDay { return a.isAllDay }
                return a.startDate < b.startDate
            }
        }
        return result
    }
}
