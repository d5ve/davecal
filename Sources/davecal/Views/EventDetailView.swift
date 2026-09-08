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
            if let repeatDescription {
                field("Repeats") {
                    Text(repeatDescription)
                        .font(.system(size: 16))
                        .padding(.top, 4)
                }
            }
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
        .frame(minWidth: 520, minHeight: 600)
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
        } else {
            d.start = defaultStart()
            d.end = d.start.addingTimeInterval(defaultLength)
            d.calendarID = defaultCalendar()?.calendarIdentifier ?? ""
        }
        draft = d
        original = d
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

    /// Repeating events first ask which occurrences to change. An occurrence
    /// already edited on its own can only be saved on its own.
    private func save() {
        if isRecurring && !isDetached {
            askingSaveSpan = true
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
