import EventKit
import SwiftUI

/// A one-line event in the month grid, the day popup and the week's all-day strip.
struct EventChip: View {
    let event: EKEvent
    /// Drawn on today's solid blue cell, so text must be white.
    var onToday = false
    var truncate = true

    var body: some View {
        Group {
            if event.isAllDay {
                allDayBar
            } else {
                timedLine
            }
        }
        .help(event.displayTitle)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(event.accessibilityDescription)
    }

    private var allDayBar: some View {
        // Multi-day bars are the background of most days, so they're kept small.
        let multi = event.spansMultipleDays
        return Text(event.displayTitle)
            .font(.system(size: multi ? 11 : 12, weight: .medium))
            .lineLimit(truncate ? 1 : nil)
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(event.color.opacity(multi ? 0.75 : 1), in: RoundedRectangle(cornerRadius: 3))
    }

    private var timedLine: some View {
        HStack(spacing: 4) {
            Circle().fill(event.color).frame(width: 7, height: 7)
            Text(event.startDate.timeText)
                .font(.system(size: 12, weight: .semibold))
            Text(event.displayTitle)
                .font(.system(size: 12))
                .lineLimit(truncate ? 1 : nil)
        }
        .foregroundStyle(onToday ? .white : .primary)
    }
}

/// A timed event drawn to scale in the week view.
struct EventBlock: View {
    let event: EKEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(event.startDate.timeText)
                .font(.system(size: 11, weight: .semibold))
            Text(event.displayTitle)
                .font(.system(size: 12))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(event.color.opacity(0.9), in: RoundedRectangle(cornerRadius: 4))
        .clipped()
        .help(event.displayTitle)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(event.accessibilityDescription)
    }
}

extension View {
    /// Double-click opens; VoiceOver users get an "Open" action.
    func openable(_ open: @escaping () -> Void) -> some View {
        self
            .contentShape(Rectangle())
            .onTapGesture(count: 2, perform: open)
            .accessibilityAction(named: "Open", open)
    }
}
