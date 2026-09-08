import Foundation
import Observation

enum ViewMode: String, CaseIterable {
    case month = "Month"
    case week = "Week"
}

/// Which period is on screen: month or week, and around which date.
@MainActor
@Observable
final class CalendarNavigation {
    var mode: ViewMode = .month
    var anchor: Date = .now

    private let calendar = Calendar.current

    var month: Date { calendar.startOfMonth(for: anchor) }
    var weekStart: Date { calendar.startOfWeek(for: anchor) }

    var periodStart: Date {
        mode == .month ? month : weekStart
    }

    var showsToday: Bool {
        switch mode {
        case .month: calendar.isDate(anchor, equalTo: .now, toGranularity: .month)
        case .week: weekStart == calendar.startOfWeek(for: .now)
        }
    }

    /// Where a new event goes when nothing more specific was chosen: today if
    /// it's on screen, otherwise the first day of the period.
    var newEventDay: Date {
        showsToday ? calendar.startOfDay(for: .now) : periodStart
    }

    var title: String {
        switch mode {
        case .month:
            return anchor.formatted(.dateTime.month(.wide).year())
        case .week:
            let start = weekStart
            let end = calendar.date(byAdding: .day, value: 6, to: start)!
            if calendar.isDate(start, equalTo: end, toGranularity: .month) {
                return "\(start.formatted(.dateTime.day())) – \(end.formatted(.dateTime.day().month(.wide).year()))"
            }
            return "\(start.formatted(.dateTime.day().month(.abbreviated))) – \(end.formatted(.dateTime.day().month(.abbreviated).year()))"
        }
    }

    func goToToday() {
        anchor = .now
    }

    /// Move forward or back by whole months or weeks.
    func shift(_ by: Int) {
        switch mode {
        case .month: anchor = calendar.date(byAdding: .month, value: by, to: month)!
        case .week: anchor = calendar.date(byAdding: .day, value: 7 * by, to: weekStart)!
        }
    }
}
