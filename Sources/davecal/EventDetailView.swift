import EventKit
import SwiftUI

/// What the detail window was opened for: a brand new event on a day, or an
/// existing event (identified by its id plus the start of that occurrence).
struct EventRequest: Codable, Hashable {
    var eventIdentifier: String?
    var date: Date

    static func newEvent(on day: Date) -> EventRequest {
        EventRequest(eventIdentifier: nil, date: day)
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
            }
            field("End") {
                DatePicker("", selection: $draft.end, in: draft.start..., displayedComponents: components).labelsHidden()
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
        .alert("Could not save", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
        .confirmationDialog("You have unsaved changes.", isPresented: $askAboutChanges, titleVisibility: .visible) {
            Button("Save") { save() }
            Button("Discard changes", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) {}
        }
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
            if calendar.isDateInToday(day) {
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
