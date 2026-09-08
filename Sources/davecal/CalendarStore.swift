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
        guard let range = loadedRange else { return }
        let predicate = eventStore.predicateForEvents(
            withStart: range.start, end: range.end, calendars: nil)
        events = eventStore.events(matching: predicate)
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
        for event in events {
            if let id = event.calendar?.calendarIdentifier {
                if let soloID { if id != soloID { continue } }
                else if disabledIDs.contains(id) { continue }
            }
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
