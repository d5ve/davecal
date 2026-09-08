import EventKit
import SwiftUI

struct WeekView: View {
    @Environment(CalendarStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    let weekStart: Date

    private let calendar = Calendar.current
    private let hourHeight: CGFloat = 52
    private let labelWidth: CGFloat = 54
    private let firstVisibleHour = 7
    /// Width of the scrolling grid, which is narrower than the headers by the scrollbar.
    @State private var gridWidth: CGFloat?

    private var days: [Date] {
        (0..<7).map { calendar.date(byAdding: .day, value: $0, to: weekStart)! }
    }

    var body: some View {
        let byDay = store.eventsByDay
        VStack(alignment: .leading, spacing: 0) {
            dayHeaders.frame(width: gridWidth)
            allDayStrip(byDay).frame(width: gridWidth)
            Divider()
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    HStack(alignment: .top, spacing: 0) {
                        hourLabels
                        ForEach(days, id: \.self) { day in
                            DayColumn(
                                day: day,
                                events: (byDay[day] ?? []).filter { !$0.isAllDay },
                                hourHeight: hourHeight,
                                openNew: { openWindow(id: "event", value: EventRequest.newEvent(at: $0)) },
                                openEvent: { openWindow(id: "event", value: EventRequest.existing($0)) }
                            )
                            .frame(maxWidth: .infinity)
                            .overlay(alignment: .leading) { columnLine }
                        }
                    }
                    .frame(height: hourHeight * 24)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { gridWidth = $0 }
                }
                .onAppear {
                    // Wait for the first layout pass, or the scroll doesn't happen.
                    DispatchQueue.main.async { proxy.scrollTo("hour-\(firstVisibleHour)", anchor: .top) }
                }
            }
        }
        .task(id: weekStart) {
            store.display(start: weekStart, end: calendar.date(byAdding: .day, value: 7, to: weekStart)!)
        }
    }

    private var columnLine: some View {
        Rectangle().fill(Color.primary.opacity(0.5)).frame(width: 1)
    }

    private var dayHeaders: some View {
        HStack(spacing: 0) {
            Spacer().frame(width: labelWidth)
            ForEach(days, id: \.self) { day in
                let today = calendar.isDateInToday(day)
                VStack(spacing: 0) {
                    Text(day.formatted(.dateTime.weekday(.abbreviated)))
                        .font(.system(size: 13, weight: .semibold))
                    Text(day.formatted(.dateTime.day()))
                        .font(.system(size: 20, weight: .semibold))
                }
                .foregroundStyle(today ? .white : .primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(today ? Color.accentColor : Color.clear)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(today ? "Today, \(day.longDayLabel)" : day.longDayLabel)
                .accessibilityAddTraits(.isHeader)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func allDayStrip(_ byDay: [Date: [EKEvent]]) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text("all day")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: labelWidth, alignment: .trailing)
                .padding(.trailing, 4)
            ForEach(days, id: \.self) { day in
                VStack(spacing: 2) {
                    ForEach((byDay[day] ?? []).filter(\.isAllDay), id: \.occurrenceKey) { event in
                        EventChip(event: event)
                            .openable { openWindow(id: "event", value: EventRequest.existing(event)) }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 2)
                .overlay(alignment: .leading) { columnLine }
            }
        }
        .padding(.vertical, 4)
        .frame(minHeight: 24)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var hourLabels: some View {
        ZStack(alignment: .topTrailing) {
            Color.clear
            ForEach(0..<24, id: \.self) { hour in
                Text(String(format: "%02d:00", hour))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 4)
                    .offset(y: CGFloat(hour) * hourHeight - 7) // centred on the hour line
                    .id("hour-\(hour)")
            }
        }
        .frame(width: labelWidth, height: hourHeight * 24)
        .accessibilityHidden(true)
    }
}

/// One day's column of timed events, drawn to scale.
struct DayColumn: View {
    let day: Date
    let events: [EKEvent]
    let hourHeight: CGFloat
    let openNew: (Date) -> Void
    let openEvent: (EKEvent) -> Void

    private let calendar = Calendar.current
    private let minimumBlockHeight: CGFloat = 18
    private let snapMinutes = 15

    /// An event clipped to this day, with its lane among overlapping events.
    struct Placed {
        let event: EKEvent
        let start: Date
        let end: Date
        var lane = 0
        var lanes = 1
    }

    var body: some View {
        let dayStart = calendar.startOfDay(for: day)
        let placed = layout(dayStart: dayStart)
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                hourLines
                ForEach(placed, id: \.event.occurrenceKey) { p in
                    let top = y(for: p.start, dayStart: dayStart)
                    let height = max(y(for: p.end, dayStart: dayStart) - top, minimumBlockHeight)
                    let width = (geo.size.width - 4) / CGFloat(p.lanes)
                    EventBlock(event: p.event)
                        .frame(width: width - 2, height: height)
                        .offset(x: 3 + CGFloat(p.lane) * width, y: top)
                        .openable { openEvent(p.event) }
                }
                if calendar.isDateInToday(day) {
                    Rectangle().fill(.red).frame(height: 2)
                        .offset(y: y(for: .now, dayStart: dayStart))
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2, coordinateSpace: .local) { point in
                let minutes = Int(point.y / hourHeight * 60) / snapMinutes * snapMinutes
                openNew(calendar.date(byAdding: .minute, value: minutes, to: dayStart)!)
            }
        }
        .accessibilityLabel(day.longDayLabel)
        .accessibilityAction(named: "New event at 9:00") {
            openNew(calendar.date(bySettingHour: 9, minute: 0, second: 0, of: dayStart)!)
        }
    }

    private var hourLines: some View {
        ForEach(0..<24, id: \.self) { hour in
            Rectangle().fill(Color.primary.opacity(0.25))
                .frame(height: 1)
                .offset(y: CGFloat(hour) * hourHeight)
        }
        .accessibilityHidden(true)
    }

    /// Vertical position by clock time, so daylight-saving days still line up.
    private func y(for date: Date, dayStart: Date) -> CGFloat {
        if date >= calendar.date(byAdding: .day, value: 1, to: dayStart)! {
            return hourHeight * 24
        }
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minutes = CGFloat(parts.hour ?? 0) * 60 + CGFloat(parts.minute ?? 0)
        return minutes / 60 * hourHeight
    }

    /// Clip each event to this day, then give overlapping events side-by-side lanes.
    private func layout(dayStart: Date) -> [Placed] {
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
        let shortest = TimeInterval(snapMinutes * 60)
        var items = events.compactMap { event -> Placed? in
            guard let s = event.startDate, let e = event.endDate else { return nil }
            let start = max(s, dayStart)
            let end = min(max(e, start.addingTimeInterval(shortest)), dayEnd)
            return Placed(event: event, start: start, end: end)
        }
        items.sort { a, b in a.start != b.start ? a.start < b.start : a.end > b.end }

        // Walk in start order. Events that overlap form a cluster; each takes
        // the first free lane, and the cluster's lane count sets the widths.
        var result: [Placed] = []
        var cluster: [Int] = []
        var laneEnds: [Date] = []
        var clusterEnd = Date.distantPast

        func closeCluster() {
            for i in cluster { result[i].lanes = laneEnds.count }
            cluster = []
            laneEnds = []
        }

        for var item in items {
            if item.start >= clusterEnd { closeCluster() }
            if let lane = laneEnds.firstIndex(where: { $0 <= item.start }) {
                item.lane = lane
                laneEnds[lane] = item.end
            } else {
                item.lane = laneEnds.count
                laneEnds.append(item.end)
            }
            clusterEnd = max(clusterEnd, item.end)
            result.append(item)
            cluster.append(result.count - 1)
        }
        closeCluster()
        return result
    }
}
