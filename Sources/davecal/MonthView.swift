import EventKit
import SwiftUI

struct MonthView: View {
    @Environment(CalendarStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    @State private var month: Date = Calendar.current.startOfMonth(for: .now)

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)

    var body: some View {
        VStack(spacing: 0) {
            header
            weekdayRow
            grid
        }
        .task { await store.requestAccess(); loadMonth() }
        .onChange(of: month) { loadMonth() }
    }

    // MARK: Pieces

    private var header: some View {
        HStack {
            Button("Today") { month = calendar.startOfMonth(for: .now) }
            Button { shift(-1) } label: { Image(systemName: "chevron.left") }
            Button { shift(1) } label: { Image(systemName: "chevron.right") }
            Text(month.formatted(.dateTime.month(.wide).year()))
                .font(.system(size: 32, weight: .bold))
                .padding(.leading, 12)
            Spacer()
            Button("New Event") {
                let today = calendar.startOfDay(for: .now)
                let day = calendar.isDate(today, equalTo: month, toGranularity: .month) ? today : month
                openWindow(id: "event", value: EventRequest.newEvent(on: day))
            }
            .keyboardShortcut("n")
            if store.denied {
                Text("Calendar access denied. Enable it in System Settings > Privacy & Security > Calendars.")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.red)
            }
        }
        .controlSize(.large)
        .padding(12)
    }

    private var weekdayRow: some View {
        HStack(spacing: 2) {
            ForEach(weekdayNames, id: \.self) { name in
                Text(name)
                    .font(.system(size: 18, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
        }
        .padding(.horizontal, 2)
    }

    private var grid: some View {
        let days = gridDays
        let byDay = store.eventsByDay(calendar: calendar)
        let today = calendar.startOfDay(for: .now)
        return LazyVGrid(columns: columns, spacing: 2) {
            ForEach(days, id: \.self) { day in
                DayCell(
                    day: day,
                    inMonth: calendar.isDate(day, equalTo: month, toGranularity: .month),
                    isToday: day == today,
                    events: byDay[day] ?? [],
                    openNew: { openWindow(id: "event", value: EventRequest.newEvent(on: day)) },
                    openEvent: { openWindow(id: "event", value: EventRequest.existing($0)) }
                )
                .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            }
        }
        .padding(2)
        .background(Color.primary)
    }

    // MARK: Dates

    private var weekdayNames: [String] {
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    /// Six full weeks starting on the week that contains the 1st.
    private var gridDays: [Date] {
        let weekday = calendar.component(.weekday, from: month)
        let offset = (weekday - calendar.firstWeekday + 7) % 7
        let start = calendar.date(byAdding: .day, value: -offset, to: month)!
        return (0..<42).map { calendar.date(byAdding: .day, value: $0, to: start)! }
    }

    private func shift(_ months: Int) {
        month = calendar.date(byAdding: .month, value: months, to: month)!
    }

    private func loadMonth() {
        let days = gridDays
        let end = calendar.date(byAdding: .day, value: 1, to: days.last!)!
        store.load(start: days.first!, end: end)
    }
}

struct DayCell: View {
    let day: Date
    let inMonth: Bool
    let isToday: Bool
    let events: [EKEvent]
    let openNew: () -> Void
    let openEvent: (EKEvent) -> Void

    private let maxShown = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(day.formatted(.dateTime.day()))
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(isToday ? .white : (inMonth ? .primary : .secondary))
            ForEach(Array(events.prefix(maxShown).enumerated()), id: \.offset) { _, event in
                EventChip(event: event, onToday: isToday)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { openEvent(event) }
            }
            if events.count > maxShown {
                Text("+\(events.count - maxShown) more")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isToday ? .white : .secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(background)
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { openNew() }
    }

    private var background: Color {
        if isToday { return .accentColor }
        return inMonth ? Color(nsColor: .textBackgroundColor) : Color(nsColor: .windowBackgroundColor)
    }
}

struct EventChip: View {
    let event: EKEvent
    let onToday: Bool

    private var color: Color {
        if let cg = event.calendar?.cgColor { return Color(cgColor: cg) }
        return .gray
    }

    var body: some View {
        if event.isAllDay {
            Text(event.title ?? "")
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(color, in: RoundedRectangle(cornerRadius: 4))
        } else {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 10, height: 10)
                Text(event.startDate.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute()))
                    .font(.system(size: 15, weight: .bold))
                Text(event.title ?? "")
                    .font(.system(size: 15))
                    .lineLimit(1)
            }
            .foregroundStyle(onToday ? .white : .primary)
        }
    }
}

extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        self.date(from: dateComponents([.year, .month], from: date))!
    }
}
