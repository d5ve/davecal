import SwiftUI

@main
struct DavecalApp: App {
    @State private var store = CalendarStore()

    var body: some Scene {
        WindowGroup("davecal") {
            ContentView()
                .environment(store)
        }

        WindowGroup("Event", id: "event", for: EventRequest.self) { $request in
            if let request {
                EventDetailView(request: request)
                    .environment(store)
            }
        }
        .defaultSize(width: 560, height: 640)
    }
}
