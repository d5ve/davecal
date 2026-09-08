import EventKit
import SwiftUI

/// Calendars with an on/off checkbox each, then the next two weeks of events.
struct SidebarView: View {
    @Environment(CalendarStore.self) private var store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        List {
            ForEach(store.calendarsByAccount, id: \.account) { group in
                Section {
                    ForEach(group.calendars, id: \.calendarIdentifier) { cal in
                        CalendarRow(calendar: cal)
                    }
                } header: {
                    Text(group.account).font(.system(size: 16, weight: .bold))
                }
            }

            Text("Hold a name to show only that calendar.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.top, 8)

            Section {
                let groups = store.upcomingByDay
                if groups.isEmpty {
                    Text("Nothing in the next two weeks.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                ForEach(groups, id: \.day) { group in
                    Text(relativeDayLabel(group.day))
                        .font(.system(size: 13, weight: .bold))
                        .padding(.top, 6)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(group.events, id: \.occurrenceKey) { event in
                        UpcomingRow(event: event)
                            .openable { openWindow(id: "event", value: EventRequest.existing(event)) }
                    }
                }
            } header: {
                Text("Upcoming").font(.system(size: 16, weight: .bold))
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 260, ideal: 300)
    }

    private func relativeDayLabel(_ day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Today" }
        if cal.isDateInTomorrow(day) { return "Tomorrow" }
        return day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }
}

struct CalendarRow: View {
    @Environment(CalendarStore.self) private var store
    let calendar: EKCalendar

    private var id: String { calendar.calendarIdentifier }
    private var isSolo: Bool { store.soloID == id }
    private var dimmed: Bool {
        if store.soloID != nil { return !isSolo }
        return !store.isEnabled(calendar)
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(calendar.color)
                .frame(width: 14, height: 14)
                .accessibilityHidden(true)
            // Plain text: a click does nothing, a press-and-hold solos the calendar.
            Text(calendar.title)
                .font(.system(size: 17, weight: isSolo ? .bold : .regular))
                .lineLimit(1)
                .foregroundStyle(dimmed ? .secondary : .primary)
                .contentShape(Rectangle())
                .gesture(soloGesture)
                .accessibilityHint("Hold to show only this calendar")
            Spacer()
            Toggle(calendar.title, isOn: Binding(
                get: { store.isEnabled(calendar) },
                set: { store.setEnabled(calendar, $0) }
            ))
            .labelsHidden()
            .frame(width: 40)
        }
        .toggleStyle(.checkbox)
        .controlSize(.large)
        .padding(.vertical, 2)
    }

    private var soloGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.25)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                if case .second(true, _) = value { store.soloID = id }
            }
            .onEnded { _ in store.soloID = nil }
    }
}

struct UpcomingRow: View {
    let event: EKEvent

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Circle().fill(event.color).frame(width: 8, height: 8)
            Text(event.isAllDay ? "all day" : event.startDate.timeText)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 44, alignment: .leading)
            Text(event.displayTitle)
                .font(.system(size: 13))
                .lineLimit(1)
        }
        .help(event.displayTitle)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(event.accessibilityDescription)
    }
}
