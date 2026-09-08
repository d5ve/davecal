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
        .task(id: month) {
            let days = gridDays
            store.display(start: days.first!, end: calendar.date(byAdding: .day, value: 1, to: days.last!)!)
        }
    }

    private var weekdayRow: some View {
        HStack(spacing: 2) {
            ForEach(calendar.orderedWeekdayNames, id: \.self) { name in
                Text(name)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
        }
        .padding(.horizontal, 2)
    }

    /// Six equal rows of seven cells on a dark backing, which shows through
    /// the gaps as the grid lines.
    private var grid: some View {
        let days = gridDays
        let byDay = store.eventsByDay
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
                    }
                }
            }
        }
        .padding(2)
        .background(Color.primary, ignoresSafeAreaEdges: [])
    }

    /// Six full weeks starting on the week that contains the 1st.
    private var gridDays: [Date] {
        let start = calendar.startOfWeek(for: month)
        return (0..<42).map { calendar.date(byAdding: .day, value: $0, to: start)! }
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
    @State private var showingList = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            headerStrip
            VStack(alignment: .leading, spacing: 2) {
                ForEach(events.prefix(maxShown), id: \.occurrenceKey) { event in
                    EventChip(event: event, onToday: isToday)
                        .openable { openEvent(event) }
                }
                if events.count > maxShown {
                    Button("+\(events.count - maxShown) more") { showingList = true }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isToday ? .white : Color.accentColor)
                }
            }
            .padding(.horizontal, 5)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(background)
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: openNew)
        .accessibilityAction(named: "New event on this day", openNew)
    }

    /// "Wed 9th" on a tinted strip. Clicking anywhere on it lists the day.
    private var headerStrip: some View {
        Button { showingList = true } label: {
            Text(day.shortDayLabel)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isToday ? .white : (inMonth ? .primary : .secondary))
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(isToday ? Color.black.opacity(0.25) : Color.primary.opacity(0.08))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("List this day's events")
        .accessibilityLabel("\(day.longDayLabel), \(events.count) events")
        .accessibilityHint("Lists the day's events")
        .popover(isPresented: $showingList, arrowEdge: .bottom) { DayListPopover(day: day, events: events) {
            showingList = false
            openEvent($0)
        } }
    }

    private var background: Color {
        if isToday { return .accentColor }
        return inMonth ? Color(nsColor: .textBackgroundColor) : Color(nsColor: .windowBackgroundColor)
    }
}

/// Every event on one day with full titles.
struct DayListPopover: View {
    let day: Date
    let events: [EKEvent]
    let openEvent: (EKEvent) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(day.longDayLabel)
                .font(.system(size: 18, weight: .bold))
                .padding(.bottom, 4)
                .accessibilityAddTraits(.isHeader)
            if events.isEmpty {
                Text("Nothing on.")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
            ForEach(events, id: \.occurrenceKey) { event in
                EventChip(event: event, truncate: false)
                    .openable { openEvent(event) }
            }
            Text("Double-click an event to open it.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .padding(14)
        .frame(minWidth: 320)
    }
}
