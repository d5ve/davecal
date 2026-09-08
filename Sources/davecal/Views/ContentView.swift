import SwiftUI

struct ContentView: View {
    @Environment(CalendarStore.self) private var store
    @Environment(CalendarNavigation.self) private var navigation
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var navigation = navigation
        NavigationSplitView {
            SidebarView()
        } detail: {
            VStack(spacing: 0) {
                header
                if store.denied { deniedBanner }
                switch navigation.mode {
                case .month: MonthView(month: navigation.month)
                case .week: WeekView(weekStart: navigation.weekStart)
                }
            }
        }
        .frame(minWidth: 1100, minHeight: 650)
        .task { await store.requestAccess() }
    }

    private var header: some View {
        @Bindable var navigation = navigation
        return HStack {
            Button("Today") { navigation.goToToday() }
            Button { navigation.shift(-1) } label: { Image(systemName: "chevron.left") }
                .accessibilityLabel(navigation.mode == .month ? "Previous month" : "Previous week")
            Button { navigation.shift(1) } label: { Image(systemName: "chevron.right") }
                .accessibilityLabel(navigation.mode == .month ? "Next month" : "Next week")
            Text(navigation.title)
                .font(.system(size: 24, weight: .semibold))
                .padding(.leading, 12)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Picker("View", selection: $navigation.mode) {
                ForEach(ViewMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 180)
            Button("New Event") {
                openWindow(id: "event", value: EventRequest.newEvent(on: navigation.newEventDay))
            }
        }
        .controlSize(.large)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var deniedBanner: some View {
        Text("Calendar access is off. Turn it on in System Settings > Privacy & Security > Calendars, then reopen davecal.")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(10)
            .background(.red)
    }
}
