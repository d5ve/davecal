import SwiftUI

@main
struct DavecalApp: App {
    @State private var store = CalendarStore()
    @State private var navigation = CalendarNavigation()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup("davecal") {
            ContentView()
                .environment(store)
                .environment(navigation)
        }
        .commands {
            SidebarCommands()
            CommandGroup(replacing: .newItem) {
                Button("New Event") {
                    openWindow(id: "event", value: EventRequest.newEvent(on: navigation.newEventDay))
                }
                .keyboardShortcut("n")
            }
            CommandMenu("Go") {
                Button("Today") { navigation.goToToday() }
                    .keyboardShortcut("t")
                Button(navigation.mode == .month ? "Previous Month" : "Previous Week") { navigation.shift(-1) }
                    .keyboardShortcut(.leftArrow)
                Button(navigation.mode == .month ? "Next Month" : "Next Week") { navigation.shift(1) }
                    .keyboardShortcut(.rightArrow)
                Divider()
                Button("Month") { navigation.mode = .month }
                    .keyboardShortcut("1")
                Button("Week") { navigation.mode = .week }
                    .keyboardShortcut("2")
            }
        }

        WindowGroup("Event", id: "event", for: EventRequest.self) { $request in
            if let request {
                EventDetailView(request: request)
                    .environment(store)
            }
        }
        .defaultSize(width: 600, height: 720)
    }
}
