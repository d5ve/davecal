import EventKit
import SwiftUI

/// What the detail window was opened for: a brand new event on a day, or an
/// existing event (identified by its id plus the start of that occurrence).
struct EventRequest: Codable, Hashable {
    var eventIdentifier: String?
    var date: Date
    /// For a new event: `date` is the exact start time rather than just a day.
    var startsAtTime = false

    static func newEvent(on day: Date) -> EventRequest {
        EventRequest(eventIdentifier: nil, date: day)
    }
    static func newEvent(at time: Date) -> EventRequest {
        EventRequest(eventIdentifier: nil, date: time, startsAtTime: true)
    }
    static func existing(_ event: EKEvent) -> EventRequest {
        EventRequest(eventIdentifier: event.eventIdentifier, date: event.startDate)
    }
}

struct EventDetailView: View {
    @Environment(CalendarStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let request: EventRequest

    @State private var draft = Draft()
    @State private var original = Draft()
    @State private var loaded = false
    @State private var savedMessage: String?
    @State private var errorMessage: String?
    @State private var askAboutChanges = false
    @State private var askDelete = false

    private let calendar = Calendar.current

    struct Draft: Equatable {
        var title = ""
        var calendarID = ""
        var isAllDay = false
        var start = Date.now
        var end = Date.now
        var location = ""
        var notes = ""
    }

    private var choosableCalendars: [EKCalendar] {
        store.calendars.filter { store.isEnabled($0) && $0.allowsContentModifications }
    }
    private var isDirty: Bool { draft != original }
    private var isNew: Bool { request.eventIdentifier == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isNew ? "New Event" : "Event")
                .font(.system(size: 26, weight: .bold))

            field("Title") {
                TextField("Title", text: $draft.title).font(.system(size: 18))
            }
            field("Calendar") {
                Picker("", selection: $draft.calendarID) {
                    ForEach(choosableCalendars, id: \.calendarIdentifier) { cal in
                        Text("\(cal.title)  (\(cal.source.title))").tag(cal.calendarIdentifier)
                    }
                }
                .labelsHidden()
            }
            field("All day") {
                Toggle("", isOn: $draft.isAllDay).labelsHidden().toggleStyle(.checkbox)
            }
            field("Start") {
                DatePicker("", selection: $draft.start, displayedComponents: components).labelsHidden()
                dayName(draft.start)
            }
            field("End") {
                DatePicker("", selection: $draft.end, in: draft.start..., displayedComponents: components).labelsHidden()
                dayName(draft.end)
            }
            field("Location") {
                TextField("Location", text: $draft.location).font(.system(size: 18))
            }
            field("Notes") {
                TextEditor(text: $draft.notes)
                    .font(.system(size: 16))
                    .frame(minHeight: 120)
                    .border(Color.secondary.opacity(0.4))
            }

            Spacer()

            HStack {
                Button("Discard", role: .destructive) { dismiss() }
                if !isNew {
                    Button("Delete", role: .destructive) { askDelete = true }
                }
                Spacer()
                Button("Close") {
                    if isDirty { askAboutChanges = true } else { dismiss() }
                }
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.title.trimmingCharacters(in: .whitespaces).isEmpty || draft.calendarID.isEmpty)
            }
            .controlSize(.large)
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 600)
        .onChange(of: draft.start) { _, new in
            // Keep the end after the start when the start moves.
            if draft.end < new { draft.end = new.addingTimeInterval(3600) }
        }
        .task { if !loaded { load(); loaded = true } }
        .alert("Saved", isPresented: Binding(get: { savedMessage != nil }, set: { if !$0 { savedMessage = nil } })) {
            Button("OK") { dismiss() }
        } message: {
            Text(savedMessage ?? "")
        }
        .alert("Something went wrong", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
        .confirmationDialog(deleteTitle, isPresented: $askDelete, titleVisibility: .visible) {
            if isRecurring {
                Button("Delete this occurrence only", role: .destructive) { delete(.thisEvent) }
                Button("Delete this and all later occurrences", role: .destructive) { delete(.futureEvents) }
                Button("Delete the entire series", role: .destructive) { deleteSeries() }
            } else {
                Button("Delete", role: .destructive) { delete(.thisEvent) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("You have unsaved changes.", isPresented: $askAboutChanges, titleVisibility: .visible) {
            Button("Save") { save() }
            Button("Discard changes", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) {}
        }
    }

    private func dayName(_ date: Date) -> some View {
        Text(date.formatted(.dateTime.weekday(.wide)))
            .font(.system(size: 18, weight: .semibold))
            .padding(.leading, 6)
            .padding(.top, 2)
    }

    private var components: DatePickerComponents {
        draft.isAllDay ? [.date] : [.date, .hourAndMinute]
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

    private var isRecurring: Bool { existingEvent()?.hasRecurrenceRules ?? false }

    private var deleteTitle: String {
        let name = original.title.isEmpty ? "this event" : "\"\(original.title)\""
        return isRecurring ? "\(name) repeats. What do you want to delete?" : "Delete \(name)? This cannot be undone."
    }

    // MARK: Delete

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
            dismiss()
        } catch {
            store.eventStore.reset()
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Load and save

    private func existingEvent() -> EKEvent? {
        guard let id = request.eventIdentifier else { return nil }
        if let occurrence = store.events.first(where: { $0.eventIdentifier == id && $0.startDate == request.date }) {
            return occurrence
        }
        return store.eventStore.event(withIdentifier: id)
    }

    private func load() {
        var d = Draft()
        if let event = existingEvent() {
            d.title = event.title ?? ""
            d.calendarID = event.calendar?.calendarIdentifier ?? ""
            d.isAllDay = event.isAllDay
            d.start = event.startDate
            d.end = event.endDate
            d.location = event.location ?? ""
            d.notes = event.notes ?? ""
        } else {
            let day = calendar.startOfDay(for: request.date)
            var start = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day)!
            if request.startsAtTime {
                start = request.date
            } else if calendar.isDateInToday(day) {
                // Next whole hour from now.
                let hour = calendar.component(.hour, from: .now) + 1
                start = calendar.date(bySettingHour: min(hour, 23), minute: 0, second: 0, of: day)!
            }
            d.start = start
            d.end = start.addingTimeInterval(3600)
            let preferred = store.eventStore.defaultCalendarForNewEvents
            if let preferred, choosableCalendars.contains(preferred) {
                d.calendarID = preferred.calendarIdentifier
            } else {
                d.calendarID = choosableCalendars.first?.calendarIdentifier ?? ""
            }
        }
        draft = d
        original = d
    }

    private func save() {
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
            let first = calendar.startOfDay(for: draft.start)
            let last = calendar.startOfDay(for: max(draft.end, draft.start))
            event.startDate = first
            event.endDate = calendar.date(byAdding: .day, value: 1, to: last)!.addingTimeInterval(-1)
        } else {
            event.startDate = draft.start
            event.endDate = max(draft.end, draft.start.addingTimeInterval(60))
        }
        do {
            try store.eventStore.save(event, span: .thisEvent, commit: true)
            original = draft
            store.reload()
            savedMessage = "\"\(event.title ?? "")\" saved to \(cal.title) (\(cal.source.title))."
        } catch {
            store.eventStore.reset()
            errorMessage = error.localizedDescription
        }
    }
}
