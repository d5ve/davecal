import EventKit
import SwiftUI

struct MonthView: View {
    @Environment(CalendarStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    let month: Date

    private let calendar = Calendar.current

    var body: some View {
        VStack(spacing: 0) {
            weekdayRow
            grid
        }
        .task(id: month) { loadMonth() }
    }

    // MARK: Pieces

    private var weekdayRow: some View {
        HStack(spacing: 2) {
            ForEach(weekdayNames, id: \.self) { name in
                Text(name)
                    .font(.system(size: 13, weight: .semibold))
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
        return VStack(spacing: 2) {
            ForEach(0..<6, id: \.self) { row in
                HStack(spacing: 2) {
                    ForEach(days[(row * 7)..<(row * 7 + 7)], id: \.self) { day in
                        DayCell(
                            day: day,
                            inMonth: calendar.isDate(day, equalTo: month, toGranularity: .month),
                            isToday: day == today,
                            events: byDay[day] ?? [],
                            openNew: { openWindow(id: "event", value: EventRequest.newEvent(on: day)) },
                            openEvent: { openWindow(id: "event", value: EventRequest.existing($0)) }
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(2)
        .background(Color.primary, ignoresSafeAreaEdges: [])
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private let maxShown = 6
    @State private var showAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button { showAll = true } label: {
                Text(day.formatted(.dateTime.day()))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isToday ? .white : (inMonth ? .primary : .secondary))
            }
            .buttonStyle(.plain)
            .help("Click to list this day's events")
            .popover(isPresented: $showAll, arrowEdge: .bottom) { dayPopover }
            ForEach(Array(events.prefix(maxShown).enumerated()), id: \.offset) { _, event in
                EventChip(event: event, onToday: isToday)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { openEvent(event) }
            }
            if events.count > maxShown {
                Button("+\(events.count - maxShown) more") { showAll = true }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isToday ? .white : Color.accentColor)
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

    private var dayPopover: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .font(.system(size: 18, weight: .bold))
                .padding(.bottom, 4)
            if events.isEmpty {
                Text("Nothing on.")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(events.enumerated()), id: \.offset) { _, event in
                EventChip(event: event, onToday: false, truncate: false)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { showAll = false; openEvent(event) }
            }
            Text("Double-click an event to open it.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .padding(14)
        .frame(minWidth: 320)
    }

    private var background: Color {
        if isToday { return .accentColor }
        return inMonth ? Color(nsColor: .textBackgroundColor) : Color(nsColor: .windowBackgroundColor)
    }
}

struct EventChip: View {
    let event: EKEvent
    let onToday: Bool
    var truncate = true

    private var color: Color {
        if let cg = event.calendar?.cgColor { return Color(cgColor: cg) }
        return .gray
    }

    /// Runs across more than one day, so it shows up in several cells.
    private var isMultiDay: Bool {
        guard let start = event.startDate, let end = event.endDate else { return false }
        return !Calendar.current.isDate(start, inSameDayAs: end.addingTimeInterval(-1))
    }

    var body: some View {
        if event.isAllDay {
            Text(event.title ?? "")
                .font(.system(size: isMultiDay ? 11 : 12, weight: .medium))
                .lineLimit(truncate ? 1 : nil)
                .help(event.title ?? "")
                .foregroundStyle(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(color.opacity(isMultiDay ? 0.75 : 1), in: RoundedRectangle(cornerRadius: 3))
        } else {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(event.startDate.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute()))
                    .font(.system(size: 12, weight: .semibold))
                Text(event.title ?? "")
                    .font(.system(size: 12))
                    .lineLimit(truncate ? 1 : nil)
            }
            .foregroundStyle(onToday ? .white : .primary)
            .help(event.title ?? "")
        }
    }
}

extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        self.date(from: dateComponents([.year, .month], from: date))!
    }
}
