import SwiftUI

enum ViewMode: String, CaseIterable {
    case month = "Month"
    case week = "Week"
}

struct ContentView: View {
    @Environment(CalendarStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    @State private var mode: ViewMode = .month
    @State private var anchor = Date.now

    private let calendar = Calendar.current

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            VStack(spacing: 0) {
                header
                switch mode {
                case .month: MonthView(month: calendar.startOfMonth(for: anchor))
                case .week: WeekView(weekStart: calendar.startOfWeek(for: anchor))
                }
            }
        }
        .frame(minWidth: 1200, minHeight: 700)
        .task { await store.requestAccess() }
    }

    private var header: some View {
        HStack {
            Button("Today") { anchor = .now }
            Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                .keyboardShortcut(.leftArrow, modifiers: [])
            Button { shift(1) } label: { Image(systemName: "chevron.right") }
                .keyboardShortcut(.rightArrow, modifiers: [])
            Text(title)
                .font(.system(size: 24, weight: .semibold))
                .padding(.leading, 12)
            Spacer()
            Picker("", selection: $mode) {
                ForEach(ViewMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 180)
            Button("New Event") {
                let today = calendar.startOfDay(for: .now)
                let day = isCurrentPeriod ? today : periodStart
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
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var periodStart: Date {
        mode == .month ? calendar.startOfMonth(for: anchor) : calendar.startOfWeek(for: anchor)
    }

    private var isCurrentPeriod: Bool {
        switch mode {
        case .month: return calendar.isDate(anchor, equalTo: .now, toGranularity: .month)
        case .week: return calendar.startOfWeek(for: anchor) == calendar.startOfWeek(for: .now)
        }
    }

    private var title: String {
        switch mode {
        case .month:
            return anchor.formatted(.dateTime.month(.wide).year())
        case .week:
            let start = calendar.startOfWeek(for: anchor)
            let end = calendar.date(byAdding: .day, value: 6, to: start)!
            if calendar.isDate(start, equalTo: end, toGranularity: .month) {
                return "\(start.formatted(.dateTime.day())) – \(end.formatted(.dateTime.day().month(.wide).year()))"
            }
            return "\(start.formatted(.dateTime.day().month(.abbreviated))) – \(end.formatted(.dateTime.day().month(.abbreviated).year()))"
        }
    }

    private func shift(_ by: Int) {
        switch mode {
        case .month: anchor = calendar.date(byAdding: .month, value: by, to: calendar.startOfMonth(for: anchor))!
        case .week: anchor = calendar.date(byAdding: .day, value: 7 * by, to: calendar.startOfWeek(for: anchor))!
        }
    }
}

extension Calendar {
    func startOfWeek(for date: Date) -> Date {
        let day = startOfDay(for: date)
        let offset = (component(.weekday, from: day) - firstWeekday + 7) % 7
        return self.date(byAdding: .day, value: -offset, to: day)!
    }
}
