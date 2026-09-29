import SwiftUI

@main
struct TherapieApp: App {
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(nil)
        }
    }
}
