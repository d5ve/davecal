import EventKit
import SwiftUI

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
                    Text(group.account)
                        .font(.system(size: 16, weight: .bold))
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
                    Text(dayLabel(group.day))
                        .font(.system(size: 13, weight: .bold))
                        .padding(.top, 6)
                    ForEach(group.events, id: \.occurrenceKey) { event in
                        UpcomingRow(event: event)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) { openWindow(id: "event", value: EventRequest.existing(event)) }
                    }
                }
            } header: {
                Text("Upcoming")
                    .font(.system(size: 16, weight: .bold))
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 260, ideal: 300)
    }

    private func dayLabel(_ day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Today" }
        if cal.isDateInTomorrow(day) { return "Tomorrow" }
        return day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }
}

struct UpcomingRow: View {
    let event: EKEvent

    private var color: Color {
        if let cg = event.calendar?.cgColor { return Color(cgColor: cg) }
        return .gray
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(event.isAllDay ? "all day" : event.startDate.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute()))
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 44, alignment: .leading)
            Text(event.title ?? "")
                .font(.system(size: 13))
                .lineLimit(1)
        }
        .help(event.title ?? "")
    }
}

struct CalendarRow: View {
    @Environment(CalendarStore.self) private var store
    let calendar: EKCalendar

    private var id: String { calendar.calendarIdentifier }
    private var dimmed: Bool {
        if let solo = store.soloID { return solo != id }
        return !store.isEnabled(calendar)
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(cgColor: calendar.cgColor))
                .frame(width: 14, height: 14)
            Text(calendar.title)
                .font(.system(size: 17, weight: store.soloID == id ? .bold : .regular))
                .lineLimit(1)
                .foregroundStyle(dimmed ? .secondary : .primary)
                .contentShape(Rectangle())
                .gesture(
                    LongPressGesture(minimumDuration: 0.25)
                        .sequenced(before: DragGesture(minimumDistance: 0))
                        .onChanged { value in
                            if case .second(true, _) = value { store.soloID = id }
                        }
                        .onEnded { _ in store.soloID = nil }
                )
            Spacer()
            Toggle("", isOn: Binding(
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
}

extension EKEvent {
    /// Unique per occurrence: repeating events share an identifier but not a start.
    var occurrenceKey: String {
        "\(eventIdentifier ?? "")@\(startDate?.timeIntervalSince1970 ?? 0)"
    }
}
