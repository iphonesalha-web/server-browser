import SwiftUI

@main
struct ServerBrowserApp: App {
    @StateObject private var store = PanelStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environment(\.layoutDirection, .rightToLeft)
                .tint(.orange)
        }
    }
}
