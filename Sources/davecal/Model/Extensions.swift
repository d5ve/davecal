import EventKit
import SwiftUI

extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        self.date(from: dateComponents([.year, .month], from: date))!
    }

    /// Start of the week containing `date`, using the locale's first weekday.
    func startOfWeek(for date: Date) -> Date {
        let day = startOfDay(for: date)
        let offset = (component(.weekday, from: day) - firstWeekday + 7) % 7
        return self.date(byAdding: .day, value: -offset, to: day)!
    }

    /// Weekday names starting from the locale's first weekday.
    var orderedWeekdayNames: [String] {
        let symbols = shortStandaloneWeekdaySymbols
        let first = firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }
}

extension Date {
    /// "09:05"
    var timeText: String {
        formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute())
    }

    /// "Wed 9th", with the month added on the 1st: "Thu 1st Oct".
    var shortDayLabel: String {
        let n = Calendar.current.component(.day, from: self)
        let ordinal = Self.ordinalFormatter.string(from: NSNumber(value: n)) ?? "\(n)"
        let weekday = formatted(.dateTime.weekday(.abbreviated))
        if n == 1 { return "\(weekday) \(ordinal) \(formatted(.dateTime.month(.abbreviated)))" }
        return "\(weekday) \(ordinal)"
    }

    /// "Wednesday, 9 September"
    var longDayLabel: String {
        formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    private static let ordinalFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .ordinal
        return f
    }()
}

extension EKCalendar {
    var color: Color { Color(cgColor: cgColor) }
}

extension EKEvent {
    var color: Color { calendar?.color ?? .gray }

    var displayTitle: String { title ?? "" }

    /// Runs across more than one day, so it shows up in several cells.
    var spansMultipleDays: Bool {
        guard let startDate, let endDate else { return false }
        return !Calendar.current.isDate(startDate, inSameDayAs: endDate.addingTimeInterval(-1))
    }

    /// Unique per occurrence: repeating events share an identifier but not a start.
    var occurrenceKey: String {
        "\(eventIdentifier ?? "")@\(startDate?.timeIntervalSince1970 ?? 0)"
    }

    /// The start of every day this event touches. End dates are exclusive
    /// (an all-day event ends at 00:00 the next day), so step back a second.
    func daysCovered(_ calendar: Calendar) -> [Date] {
        guard let startDate, let endDate else { return [] }
        let first = calendar.startOfDay(for: startDate)
        let last = max(first, calendar.startOfDay(for: endDate.addingTimeInterval(-1)))
        var days: [Date] = []
        var day = first
        while day <= last {
            days.append(day)
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        return days
    }

    /// What VoiceOver reads for this event.
    var accessibilityDescription: String {
        isAllDay ? "\(displayTitle), all day" : "\(startDate.timeText), \(displayTitle)"
    }
}
