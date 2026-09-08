import EventKit
import SwiftUI

struct SidebarView: View {
    @Environment(CalendarStore.self) private var store

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
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 240, ideal: 280)
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
