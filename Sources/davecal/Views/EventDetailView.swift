import EventKit
import SwiftUI

/// The event window. Stays open until Save, Close, Discard or Delete;
/// Save writes through EventKit and closes.
struct EventDetailView: View {
    @Environment(CalendarStore.self) private var store
    @Environment(\.dismissWindow) private var dismissWindow

    let request: EventRequest

    @State private var draft = Draft()
    @State private var original = Draft()
    @State private var errorMessage: String?
    @State private var askingAboutChanges = false
    @State private var askingToDelete = false
    @State private var askingSaveSpan = false
    @State private var repeatDescription: String?
    @State private var isDetached = false

    private let calendar = Calendar.current
    private let defaultLength: TimeInterval = 3600

    /// The editable fields, kept apart from EventKit until Save.
    struct Draft: Equatable {
        var title = ""
        var calendarID = ""
        var isAllDay = false
        var start = Date.now
        var end = Date.now
        var location = ""
        var notes = ""
        var repeats = Repeat.never
        /// Weekdays for weekly and fortnightly, as EKWeekday raw values (1 = Sunday).
        var weekdays: Set<Int> = []
        var repeatEnd = RepeatEnd.never
        var repeatUntil = Date.now
        var repeatCount = 10

        var recurrence: Recurrence { Recurrence(repeats: repeats, weekdays: weekdays, end: repeatEnd, until: repeatUntil, count: repeatCount) }
    }

    /// Just the repeat settings, for spotting whether they changed.
    struct Recurrence: Equatable {
        var repeats: Repeat
        var weekdays: Set<Int>
        var end: RepeatEnd
        var until: Date
        var count: Int
    }

    enum Repeat: String, CaseIterable {
        case never = "Never"
        case daily = "Daily"
        case weekly = "Weekly"
        case fortnightly = "Fortnightly"
        case monthly = "Monthly"
        case yearly = "Yearly"
        /// A rule this window can't express; shown but left alone.
        case custom = "Custom"

        var isWeekBased: Bool { self == .weekly || self == .fortnightly }
    }

    enum RepeatEnd: String, CaseIterable {
        case never = "Never"
        case date = "On date"
        case count = "After"
    }

    /// Close this window. Works from inside a dialog too, which the plain
    /// dismiss action does not.
    private func close() {
        DispatchQueue.main.async { dismissWindow(id: "event", value: request) }
    }

    private var isDirty: Bool { draft != original }
    private var canSave: Bool {
        !draft.title.trimmingCharacters(in: .whitespaces).isEmpty && !draft.calendarID.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(request.isNew ? "New Event" : "Event")
                .font(.system(size: 26, weight: .bold))
                .accessibilityAddTraits(.isHeader)

            field("Title") {
                TextField("Title", text: $draft.title).font(.system(size: 18))
            }
            field("Calendar") {
                Picker("Calendar", selection: $draft.calendarID) {
                    ForEach(store.writableCalendars, id: \.calendarIdentifier) { cal in
                        Text("\(cal.title)  (\(store.accountName(cal)))").tag(cal.calendarIdentifier)
                    }
                }
                .labelsHidden()
            }
            field("All day") {
                Toggle("All day", isOn: $draft.isAllDay).labelsHidden().toggleStyle(.checkbox)
            }
            field("Start") {
                DatePicker("Start", selection: $draft.start, displayedComponents: dateComponents).labelsHidden()
                weekdayName(draft.start)
            }
            field("End") {
                DatePicker("End", selection: $draft.end, in: draft.start..., displayedComponents: dateComponents).labelsHidden()
                weekdayName(draft.end)
            }
            field("Repeats") { repeatEditor }
            field("Location") {
                TextField("Location", text: $draft.location).font(.system(size: 18))
            }
            field("Notes") {
                TextEditor(text: $draft.notes)
                    .font(.system(size: 16))
                    .frame(minHeight: 120)
                    .border(Color.secondary.opacity(0.4))
                    .accessibilityLabel("Notes")
            }

            Spacer()
            buttons
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 680)
        .onChange(of: draft.start) { _, newStart in
            // Keep the end after the start when the start moves.
            if draft.end < newStart { draft.end = newStart.addingTimeInterval(defaultLength) }
        }
        .task { load() }
        .alert("Something went wrong", isPresented: presence($errorMessage)) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
        .confirmationDialog("This event repeats. Which occurrences should change?", isPresented: $askingSaveSpan, titleVisibility: .visible) {
            Button("Only this occurrence") { save(span: .thisEvent) }
            Button("This and all later occurrences") { save(span: .futureEvents) }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(deleteQuestion, isPresented: $askingToDelete, titleVisibility: .visible) {
            if isRecurring {
                Button("Delete this occurrence only", role: .destructive) { delete(.thisEvent) }
                Button("Delete this and all later occurrences", role: .destructive) { delete(.futureEvents) }
                Button("Delete the entire series", role: .destructive) { deleteSeries() }
            } else {
                Button("Delete", role: .destructive) { delete(.thisEvent) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("You have unsaved changes.", isPresented: $askingAboutChanges, titleVisibility: .visible) {
            Button("Save") { save() }
            Button("Discard changes", role: .destructive) { close() }
            Button("Keep editing", role: .cancel) {}
        }
    }

    private var buttons: some View {
        HStack {
            Button("Discard", role: .destructive) { close() }
            if !request.isNew {
                Button("Delete", role: .destructive) { askingToDelete = true }
            }
            Spacer()
            Button("Close") {
                if isDirty { askingAboutChanges = true } else { close() }
            }
            .keyboardShortcut(.cancelAction)
            Button("Save") { save() }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
        }
        .controlSize(.large)
    }

    @ViewBuilder
    private var repeatEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isDetached {
                Text(repeatDescription ?? "")
                    .font(.system(size: 16))
                    .padding(.top, 4)
            } else {
                Picker("Repeats", selection: $draft.repeats) {
                    ForEach(Repeat.allCases.filter { $0 != .custom || draft.repeats == .custom }, id: \.self) {
                        Text($0.rawValue).tag($0)
                    }
                }
                .labelsHidden()
                .frame(width: 160)
                .disabled(draft.repeats == .custom)
                if draft.repeats == .custom, let repeatDescription {
                    Text(repeatDescription).font(.system(size: 14)).foregroundStyle(.secondary)
                }
                if draft.repeats.isWeekBased { weekdayPicker }
                if draft.repeats != .never && draft.repeats != .custom { repeatEndEditor }
            }
        }
    }

    private var weekdayPicker: some View {
        HStack(spacing: 6) {
            ForEach(orderedWeekdays, id: \.self) { weekday in
                Toggle(calendar.shortWeekdaySymbols[weekday - 1], isOn: Binding(
                    get: { draft.weekdays.contains(weekday) },
                    set: { on in
                        if on { draft.weekdays.insert(weekday) } else if draft.weekdays.count > 1 { draft.weekdays.remove(weekday) }
                    }
                ))
                .toggleStyle(.button)
            }
        }
    }

    private var repeatEndEditor: some View {
        HStack(spacing: 8) {
            Text("Ends").font(.system(size: 14))
            Picker("Ends", selection: $draft.repeatEnd) {
                ForEach(RepeatEnd.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .labelsHidden()
            .frame(width: 110)
            switch draft.repeatEnd {
            case .never:
                EmptyView()
            case .date:
                DatePicker("Until", selection: $draft.repeatUntil, in: draft.start..., displayedComponents: [.date]).labelsHidden()
            case .count:
                Stepper(value: $draft.repeatCount, in: 1...999) {
                    Text("\(draft.repeatCount) times").font(.system(size: 14)).frame(width: 70, alignment: .leading)
                }
            }
        }
    }

    /// EKWeekday values (1 = Sunday) starting from the locale's first weekday.
    private var orderedWeekdays: [Int] {
        (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 80, alignment: .trailing)
                .padding(.top, 4)
            content()
        }
    }

    private func weekdayName(_ date: Date) -> some View {
        Text(date.formatted(.dateTime.weekday(.wide)))
            .font(.system(size: 18, weight: .semibold))
            .padding(.leading, 6)
            .padding(.top, 2)
    }

    private var dateComponents: DatePickerComponents {
        draft.isAllDay ? [.date] : [.date, .hourAndMinute]
    }

    /// A yes/no binding for whether an optional message is set, for alerts.
    private func presence(_ message: Binding<String?>) -> Binding<Bool> {
        Binding(get: { message.wrappedValue != nil }, set: { if !$0 { message.wrappedValue = nil } })
    }

    // MARK: Loading

    private func existingEvent() -> EKEvent? {
        guard let id = request.eventIdentifier else { return nil }
        return store.occurrence(identifier: id, startingAt: request.date)
    }

    private func load() {
        var d = Draft()
        if let event = existingEvent() {
            d.title = event.displayTitle
            d.calendarID = event.calendar?.calendarIdentifier ?? ""
            d.isAllDay = event.isAllDay
            d.start = event.startDate
            d.end = event.endDate
            d.location = event.location ?? ""
            d.notes = event.notes ?? ""
            repeatDescription = event.repeatDescription
            isDetached = event.isDetached
            apply(rule: event.recurrenceRules?.first, to: &d)
        } else {
            d.start = defaultStart()
            d.end = d.start.addingTimeInterval(defaultLength)
            d.calendarID = defaultCalendar()?.calendarIdentifier ?? ""
        }
        if d.weekdays.isEmpty { d.weekdays = [calendar.component(.weekday, from: d.start)] }
        if d.repeatEnd == .never { d.repeatUntil = calendar.date(byAdding: .month, value: 3, to: d.start) ?? d.start }
        draft = d
        original = d
    }

    /// Read an EventKit rule into the simple choices, or mark it Custom.
    private func apply(rule: EKRecurrenceRule?, to d: inout Draft) {
        guard let rule else { return }
        let plain = (rule.daysOfTheMonth ?? []).isEmpty && (rule.monthsOfTheYear ?? []).isEmpty
            && (rule.setPositions ?? []).isEmpty && (rule.daysOfTheYear ?? []).isEmpty && (rule.weeksOfTheYear ?? []).isEmpty
        switch (rule.frequency, rule.interval, plain) {
        case (.daily, 1, true): d.repeats = .daily
        case (.weekly, 1, true): d.repeats = .weekly
        case (.weekly, 2, true): d.repeats = .fortnightly
        case (.monthly, 1, true) where (rule.daysOfTheWeek ?? []).isEmpty: d.repeats = .monthly
        case (.yearly, 1, true) where (rule.daysOfTheWeek ?? []).isEmpty: d.repeats = .yearly
        default: d.repeats = .custom
        }
        if let days = rule.daysOfTheWeek, !days.isEmpty {
            d.weekdays = Set(days.map { $0.dayOfTheWeek.rawValue })
        }
        if let end = rule.recurrenceEnd {
            if let date = end.endDate {
                d.repeatEnd = .date
                d.repeatUntil = date
            } else if end.occurrenceCount > 0 {
                d.repeatEnd = .count
                d.repeatCount = end.occurrenceCount
            }
        }
    }

    /// Build the EventKit rule for the draft, or nil for no repeat.
    private func recurrenceRule() -> EKRecurrenceRule? {
        let frequency: EKRecurrenceFrequency
        var interval = 1
        switch draft.repeats {
        case .never, .custom: return nil
        case .daily: frequency = .daily
        case .weekly: frequency = .weekly
        case .fortnightly: frequency = .weekly; interval = 2
        case .monthly: frequency = .monthly
        case .yearly: frequency = .yearly
        }
        let days: [EKRecurrenceDayOfWeek]? = draft.repeats.isWeekBased
            ? draft.weekdays.sorted().compactMap { EKWeekday(rawValue: $0) }.map { EKRecurrenceDayOfWeek($0) }
            : nil
        let end: EKRecurrenceEnd?
        switch draft.repeatEnd {
        case .never: end = nil
        case .date: end = EKRecurrenceEnd(end: draft.repeatUntil)
        case .count: end = EKRecurrenceEnd(occurrenceCount: draft.repeatCount)
        }
        return EKRecurrenceRule(
            recurrenceWith: frequency, interval: interval, daysOfTheWeek: days,
            daysOfTheMonth: nil, monthsOfTheYear: nil, weeksOfTheYear: nil,
            daysOfTheYear: nil, setPositions: nil, end: end)
    }

    /// The clicked time if there was one, else the next whole hour today, else 09:00.
    private func defaultStart() -> Date {
        if request.startsAtTime { return request.date }
        let day = calendar.startOfDay(for: request.date)
        var hour = 9
        if calendar.isDateInToday(day) {
            hour = min(calendar.component(.hour, from: .now) + 1, 23)
        }
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
    }

    private func defaultCalendar() -> EKCalendar? {
        let writable = store.writableCalendars
        if let preferred = store.eventStore.defaultCalendarForNewEvents, writable.contains(preferred) {
            return preferred
        }
        return writable.first
    }

    // MARK: Saving

    private var recurrenceChanged: Bool { draft.recurrence != original.recurrence }

    /// Repeating events first ask which occurrences to change. A changed
    /// repeat rule can only apply from this occurrence on, so that skips the
    /// question. An occurrence already edited on its own is saved on its own.
    private func save() {
        if isRecurring && !isDetached {
            if recurrenceChanged { save(span: .futureEvents) } else { askingSaveSpan = true }
        } else {
            save(span: .thisEvent)
        }
    }

    private func save(span: EKSpan) {
        guard let cal = store.eventStore.calendar(withIdentifier: draft.calendarID) else {
            errorMessage = "Pick a calendar first."
            return
        }
        let event = existingEvent() ?? EKEvent(eventStore: store.eventStore)
        event.title = draft.title.trimmingCharacters(in: .whitespaces)
        event.calendar = cal
        event.isAllDay = draft.isAllDay
        event.location = draft.location.isEmpty ? nil : draft.location
        event.notes = draft.notes.isEmpty ? nil : draft.notes
        if draft.repeats != .custom && (request.isNew || recurrenceChanged) {
            event.recurrenceRules = recurrenceRule().map { [$0] }
        }
        if draft.isAllDay {
            // EventKit wants all-day events to run from 00:00 to the last second of the last day.
            let first = calendar.startOfDay(for: draft.start)
            let last = calendar.startOfDay(for: max(draft.end, draft.start))
            event.startDate = first
            event.endDate = calendar.date(byAdding: .day, value: 1, to: last)!.addingTimeInterval(-1)
        } else {
            event.startDate = draft.start
            event.endDate = max(draft.end, draft.start.addingTimeInterval(60))
        }
        do {
            try store.eventStore.save(event, span: span, commit: true)
            store.reload()
            close()
        } catch {
            store.eventStore.reset()
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Deleting

    private var isRecurring: Bool { existingEvent()?.hasRecurrenceRules ?? false }

    private var deleteQuestion: String {
        let name = original.title.isEmpty ? "this event" : "\"\(original.title)\""
        return isRecurring
            ? "\(name) repeats. What do you want to delete?"
            : "Delete \(name)? This cannot be undone."
    }

    private func delete(_ span: EKSpan) {
        guard let event = existingEvent() else { return }
        remove(event, span: span)
    }

    /// Removing from the first occurrence onwards takes out the whole series.
    private func deleteSeries() {
        guard let id = request.eventIdentifier,
              let first = store.eventStore.event(withIdentifier: id) else { return }
        remove(first, span: .futureEvents)
    }

    private func remove(_ event: EKEvent, span: EKSpan) {
        do {
            try store.eventStore.remove(event, span: span, commit: true)
            store.reload()
            close()
        } catch {
            store.eventStore.reset()
            errorMessage = error.localizedDescription
        }
    }
}
