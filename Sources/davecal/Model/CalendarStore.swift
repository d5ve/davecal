import EventKit
import Foundation
import Observation

/// The app's one connection to EventKit: permission, the calendars, the
/// events on screen, and the sidebar's calendar settings.
@MainActor
@Observable
final class CalendarStore {
    let eventStore = EKEventStore()
    private let calendar = Calendar.current

    private(set) var authorized = false
    private(set) var denied = false
    private(set) var calendars: [EKCalendar] = []
    /// Events for the month or week currently displayed.
    private(set) var events: [EKEvent] = []
    /// Events from now for the next two weeks, for the sidebar.
    private(set) var upcoming: [EKEvent] = []

    /// Calendars switched off in the sidebar, stored so everything defaults to on.
    private var disabledIDs: Set<String> = CalendarStore.loadDisabled() {
        didSet { CalendarStore.saveDisabled(disabledIDs) }
    }
    /// While a calendar name is held down, only that calendar is shown.
    var soloID: String?

    private var displayedRange: (start: Date, end: Date)?
    private let demo: DemoData?

    init() {
        demo = DemoData.isEnabled ? DemoData(eventStore: eventStore) : nil
        NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: eventStore, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
    }

    // MARK: Permission

    func requestAccess() async {
        if demo != nil {
            authorized = true
            reload()
            return
        }
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            authorized = true
        case .denied, .restricted:
            denied = true
        default:
            authorized = (try? await eventStore.requestFullAccessToEvents()) ?? false
            denied = !authorized
        }
        reload()
    }

    // MARK: Loading

    /// Set the date range on screen. Events for it are fetched straight away.
    func display(start: Date, end: Date) {
        displayedRange = (start, end)
        reload()
    }

    /// Fetch everything again. Called on any change in the calendar database.
    func reload() {
        guard authorized else { return }
        calendars = (demo?.calendars ?? eventStore.calendars(for: .event)).sorted {
            (accountName($0), $0.title) < (accountName($1), $1.title)
        }

        let now = Date.now
        let horizon = calendar.date(byAdding: .day, value: 14, to: now)!
        upcoming = fetch(from: now, to: horizon)
            .filter { !($0.isAllDay && $0.spansMultipleDays) }
            .sorted(by: displayOrder)

        if let range = displayedRange {
            events = fetch(from: range.start, to: range.end)
        }
    }

    private func fetch(from start: Date, to end: Date) -> [EKEvent] {
        if let demo { return demo.events(from: start, to: end) }
        return eventStore.events(matching: eventStore.predicateForEvents(withStart: start, end: end, calendars: nil))
    }

    /// The account a calendar belongs to, as shown in the sidebar and picker.
    func accountName(_ calendar: EKCalendar) -> String {
        demo?.account(for: calendar) ?? calendar.source?.title ?? "Other"
    }

    /// All-day first, then by start time.
    private func displayOrder(_ a: EKEvent, _ b: EKEvent) -> Bool {
        if a.isAllDay != b.isAllDay { return a.isAllDay }
        return a.startDate < b.startDate
    }

    /// Events whose title, location or notes contain the text, from a year
    /// back to two years ahead, respecting the sidebar settings.
    func search(_ text: String) -> [EKEvent] {
        let needle = text.trimmingCharacters(in: .whitespaces)
        guard authorized, !needle.isEmpty else { return [] }
        let start = calendar.date(byAdding: .year, value: -1, to: .now)!
        let end = calendar.date(byAdding: .year, value: 2, to: .now)!
        return fetch(from: start, to: end)
            .filter { shows($0) }
            .filter { event in
                [event.title, event.location, event.notes]
                    .contains { $0?.localizedCaseInsensitiveContains(needle) ?? false }
            }
            .sorted { $0.startDate < $1.startDate }
    }

    /// Find one occurrence of an event. Repeating events share an identifier,
    /// so the start time picks out which occurrence.
    func occurrence(identifier: String, startingAt start: Date) -> EKEvent? {
        let matches = { (e: EKEvent) in e.eventIdentifier == identifier && e.startDate == start }
        if let hit = (events + upcoming).first(where: matches) { return hit }
        if let hit = fetch(from: start, to: start.addingTimeInterval(1)).first(where: matches) { return hit }
        return eventStore.event(withIdentifier: identifier)
    }

    // MARK: Sidebar settings

    func isEnabled(_ calendar: EKCalendar) -> Bool {
        !disabledIDs.contains(calendar.calendarIdentifier)
    }

    func setEnabled(_ calendar: EKCalendar, _ on: Bool) {
        if on {
            disabledIDs.remove(calendar.calendarIdentifier)
        } else {
            disabledIDs.insert(calendar.calendarIdentifier)
        }
    }

    /// Whether the sidebar settings (checkbox, hold-to-solo) let this event show.
    func shows(_ event: EKEvent) -> Bool {
        guard let id = event.calendar?.calendarIdentifier else { return true }
        if let soloID { return id == soloID }
        return !disabledIDs.contains(id)
    }

    /// Calendars the user can put new events into.
    var writableCalendars: [EKCalendar] {
        calendars.filter { isEnabled($0) && $0.allowsContentModifications }
    }

    /// Calendars grouped by account, in account then calendar name order.
    var calendarsByAccount: [(account: String, calendars: [EKCalendar])] {
        var groups: [(account: String, calendars: [EKCalendar])] = []
        for cal in calendars {
            let account = accountName(cal)
            if let i = groups.firstIndex(where: { $0.account == account }) {
                groups[i].calendars.append(cal)
            } else {
                groups.append((account, [cal]))
            }
        }
        return groups
    }

    // MARK: Grouping for the views

    /// Displayed events keyed by the start of each day they touch. A multi-day
    /// event appears under every day it covers.
    var eventsByDay: [Date: [EKEvent]] {
        var result: [Date: [EKEvent]] = [:]
        for event in events where shows(event) {
            for day in event.daysCovered(calendar) {
                result[day, default: []].append(event)
            }
        }
        for key in result.keys {
            result[key]?.sort(by: displayOrder)
        }
        return result
    }

    /// Upcoming events that pass the sidebar settings, grouped by day in order.
    var upcomingByDay: [(day: Date, events: [EKEvent])] {
        var groups: [(day: Date, events: [EKEvent])] = []
        for event in upcoming where shows(event) {
            let day = calendar.startOfDay(for: event.startDate)
            if let i = groups.firstIndex(where: { $0.day == day }) {
                groups[i].events.append(event)
            } else {
                groups.append((day, [event]))
            }
        }
        return groups.sorted { $0.day < $1.day }
    }

    // MARK: Persistence

    private static let disabledKey = "disabledCalendars"

    private static func loadDisabled() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: disabledKey) ?? [])
    }

    private static func saveDisabled(_ ids: Set<String>) {
        UserDefaults.standard.set(ids.sorted(), forKey: disabledKey)
    }
}
