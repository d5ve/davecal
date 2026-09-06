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
                    HStack {
                        Text(group.account)
                            .font(.system(size: 16, weight: .bold))
                        Spacer()
                        Text("Enabled").font(.system(size: 12, weight: .semibold)).frame(width: 56)
                        Text("Visible").font(.system(size: 12, weight: .semibold)).frame(width: 56)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 260, ideal: 300)
    }
}

struct CalendarRow: View {
    @Environment(CalendarStore.self) private var store
    let calendar: EKCalendar

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(cgColor: calendar.cgColor))
                .frame(width: 14, height: 14)
            // Plain text: clicking the name does nothing.
            Text(calendar.title)
                .font(.system(size: 17))
                .lineLimit(1)
                .foregroundStyle(store.isVisible(calendar) ? .primary : .secondary)
            Spacer()
            Toggle("", isOn: Binding(
                get: { store.isEnabled(calendar) },
                set: { store.setEnabled(calendar, $0) }
            ))
            .labelsHidden()
            .frame(width: 56)
            Toggle("", isOn: Binding(
                get: { store.isVisible(calendar) },
                set: { store.setVisible(calendar, $0) }
            ))
            .labelsHidden()
            .frame(width: 56)
        }
        .toggleStyle(.checkbox)
        .controlSize(.large)
        .padding(.vertical, 2)
    }
}
