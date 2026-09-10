import EventKit
import SwiftUI

/// Matching events grouped by day. Double-click opens one; the arrow jumps
/// the calendar to its day.
struct SearchResultsView: View {
    @Environment(CalendarStore.self) private var store
    @Environment(CalendarNavigation.self) private var navigation
    @Environment(\.openWindow) private var openWindow
    let query: String
    let clearSearch: () -> Void

    @State private var results: [EKEvent] = []
    @State private var searched = false

    private let calendar = Calendar.current

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title)
                    .font(.system(size: 24, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Back to calendar", action: clearSearch)
                    .keyboardShortcut(.cancelAction)
            }
            .controlSize(.large)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            ScrollViewReader { proxy in
                List {
                    ForEach(groups, id: \.day) { group in
                        Section {
                            ForEach(group.events, id: \.occurrenceKey) { event in
                                row(event).id(event.occurrenceKey)
                            }
                        } header: {
                            Text(group.day.formatted(.dateTime.weekday(.wide).day().month(.wide).year()))
                                .font(.system(size: 14, weight: .bold))
                        }
                    }
                }
                // Wait a moment after typing stops before searching three years of events.
                .task(id: query) {
                    try? await Task.sleep(for: .milliseconds(250))
                    guard !Task.isCancelled else { return }
                    results = store.search(query)
                    searched = true
                    // Past matches pile up over time, so start at the first one
                    // from today onwards. Scrolling up shows the past.
                    if let first = results.first(where: { $0.endDate >= navigation.today }) {
                        DispatchQueue.main.async { proxy.scrollTo(first.occurrenceKey, anchor: .top) }
                    }
                }
            }
        }
    }

    private var title: String {
        if !searched { return "Searching…" }
        switch results.count {
        case 0: return "Nothing matches “\(query)”"
        case 1: return "1 event matches “\(query)”"
        default: return "\(results.count) events match “\(query)”"
        }
    }

    private var groups: [(day: Date, events: [EKEvent])] {
        var groups: [(day: Date, events: [EKEvent])] = []
        for event in results {
            let day = calendar.startOfDay(for: event.startDate)
            if let i = groups.firstIndex(where: { $0.day == day }) {
                groups[i].events.append(event)
            } else {
                groups.append((day, [event]))
            }
        }
        return groups
    }

    private func row(_ event: EKEvent) -> some View {
        HStack(spacing: 10) {
            Circle().fill(event.color).frame(width: 9, height: 9)
            Text(event.isAllDay ? "all day" : event.startDate.timeText)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 52, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.displayTitle).font(.system(size: 14))
                if let location = event.location, !location.isEmpty {
                    Text(location).font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(event.calendar?.title ?? "")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Button {
                navigation.anchor = event.startDate
                clearSearch()
            } label: {
                Image(systemName: "arrow.right.circle")
            }
            .buttonStyle(.plain)
            .help("Show this day in the calendar")
            .accessibilityLabel("Show in calendar")
        }
        .padding(.vertical, 2)
        .openable { openWindow(id: "event", value: EventRequest.existing(event)) }
    }
}
