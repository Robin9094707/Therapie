import SwiftUI

@main
struct TherapieApp: App {
    @StateObject private var store = AppStore()
    @AppStorage("therapy.appearance") private var appearance = TherapyAppearance.system.rawValue

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme((TherapyAppearance(rawValue: appearance) ?? .system).colorScheme)
                .environment(\.locale, Locale(identifier: "de_DE"))
        }
    }
}

