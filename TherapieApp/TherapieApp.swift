import SwiftUI

@main
struct TherapieApp: App {
    @StateObject private var store: AppStore
    @AppStorage("therapy.appearance") private var appearance = TherapyAppearance.system.rawValue
    init() { let store = AppStore(); _store = StateObject(wrappedValue: store) }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme((TherapyAppearance(rawValue: appearance) ?? .system).colorScheme)
                .environment(\.locale, Locale(identifier: "de_DE"))
        }
    }
}
