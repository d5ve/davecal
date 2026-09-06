import SwiftUI

@main
struct DavecalApp: App {
    @State private var store = CalendarStore()

    var body: some Scene {
        WindowGroup("davecal") {
            ContentView()
                .environment(store)
        }
    }
}
