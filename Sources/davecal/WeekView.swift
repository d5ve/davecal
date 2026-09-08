import EventKit
import SwiftUI

struct WeekView: View {
    @Environment(CalendarStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    let weekStart: Date

    private let calendar = Calendar.current
    private let hourHeight: CGFloat = 52
    private let labelWidth: CGFloat = 54

    private var days: [Date] { (0..<7).map { calendar.date(byAdding: .day, value: $0, to: weekStart)! } }

    var body: some View {
        let byDay = store.eventsByDay(calendar: calendar)
        VStack(spacing: 0) {
            dayHeaders
            allDayStrip(byDay)
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
                            .overlay(alignment: .leading) { Rectangle().fill(Color.primary.opacity(0.5)).frame(width: 1) }
                        }
                    }
                    .frame(height: hourHeight * 24)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                }
                .onAppear {
                    DispatchQueue.main.async { proxy.scrollTo("hour-7", anchor: .top) }
                }
            }
        }
        .task(id: weekStart) {
            store.load(start: weekStart, end: calendar.date(byAdding: .day, value: 7, to: weekStart)!)
        }
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
                    ForEach(Array((byDay[day] ?? []).filter(\.isAllDay).enumerated()), id: \.offset) { _, event in
                        EventChip(event: event, onToday: false)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) { openWindow(id: "event", value: EventRequest.existing(event)) }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 2)
                .overlay(alignment: .leading) { Rectangle().fill(Color.primary.opacity(0.5)).frame(width: 1) }
            }
        }
        .padding(.vertical, 4)
        .frame(minHeight: 24)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var hourLabels: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                Text(String(format: "%02d:00", hour))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: labelWidth, height: hourHeight, alignment: .topTrailing)
                    .padding(.trailing, 4)
                    .offset(y: -7)
                    .id("hour-\(hour)")
            }
        }
    }
}

/// One day's column of timed events.
struct DayColumn: View {
    let day: Date
    let events: [EKEvent]
    let hourHeight: CGFloat
    let openNew: (Date) -> Void
    let openEvent: (EKEvent) -> Void

    private let calendar = Calendar.current

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
                ForEach(Array(placed.enumerated()), id: \.offset) { _, p in
                    let top = yFor(p.start, dayStart: dayStart)
                    let height = max(yFor(p.end, dayStart: dayStart) - top, 18)
                    let width = (geo.size.width - 4) / CGFloat(p.lanes)
                    EventBlock(event: p.event)
                        .frame(width: width - 2, height: height)
                        .offset(x: 3 + CGFloat(p.lane) * width, y: top)
                        .onTapGesture(count: 2) { openEvent(p.event) }
                }
                if calendar.isDateInToday(day) {
                    Rectangle().fill(.red).frame(height: 2)
                        .offset(y: yFor(.now, dayStart: dayStart))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2, coordinateSpace: .local) { point in
                let minutes = Int(point.y / hourHeight * 60 / 15) * 15
                openNew(calendar.date(byAdding: .minute, value: minutes, to: dayStart)!)
            }
        }
    }

    private var hourLines: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                Rectangle().fill(Color.primary.opacity(0.25)).frame(height: 1)
                Spacer(minLength: 0)
            }
        }
    }

    private func yFor(_ date: Date, dayStart: Date) -> CGFloat {
        CGFloat(date.timeIntervalSince(dayStart)) / 3600 * hourHeight
    }

    /// Clip each event to this day, then give overlapping events side-by-side lanes.
    private func layout(dayStart: Date) -> [Placed] {
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
        var items = events.compactMap { event -> Placed? in
            guard let s = event.startDate, let e = event.endDate else { return nil }
            let start = max(s, dayStart)
            let end = min(max(e, start.addingTimeInterval(15 * 60)), dayEnd)
            return Placed(event: event, start: start, end: end)
        }
        items.sort { a, b in a.start != b.start ? a.start < b.start : a.end > b.end }

        var result: [Placed] = []
        var cluster: [Int] = []
        var laneEnds: [Date] = []
        var clusterEnd = Date.distantPast

        func closeCluster() {
            for i in cluster { result[i].lanes = laneEnds.count }
            cluster = []; laneEnds = []
        }

        for var item in items {
            if item.start >= clusterEnd { closeCluster() }
            if let lane = laneEnds.firstIndex(where: { $0 <= item.start }) {
                item.lane = lane; laneEnds[lane] = item.end
            } else {
                item.lane = laneEnds.count; laneEnds.append(item.end)
            }
            clusterEnd = max(clusterEnd, item.end)
            result.append(item)
            cluster.append(result.count - 1)
        }
        closeCluster()
        return result
    }
}

struct EventBlock: View {
    let event: EKEvent

    private var color: Color {
        if let cg = event.calendar?.cgColor { return Color(cgColor: cg) }
        return .gray
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(event.startDate.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute()))
                .font(.system(size: 11, weight: .semibold))
            Text(event.title ?? "")
                .font(.system(size: 12))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(color.opacity(0.9), in: RoundedRectangle(cornerRadius: 4))
        .clipped()
        .help(event.title ?? "")
    }
}
