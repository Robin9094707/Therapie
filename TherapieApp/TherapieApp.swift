import SwiftUI

@main
struct TherapieApp: App {
    @StateObject private var store: AppStore
    @AppStorage("therapy.appearance") private var appearance = TherapyAppearance.system.rawValue
    init() { let store = TherapyIntentRuntime.store(); _store = StateObject(wrappedValue: store) }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .tint(store.data.accentTheme.color)
                .accentColor(store.data.accentTheme.color)
                .environment(\.therapyAccent, store.data.accentTheme)
                .preferredColorScheme((TherapyAppearance(rawValue: appearance) ?? .system).colorScheme)
                .environment(\.locale, Locale(identifier: "de_DE"))
        }
        // Redraws or ends a running session's Live Activity near its next phase boundary while the app is suspended.
        .backgroundTask(.appRefresh(TherapySessionController.refreshTaskIdentifier)) {
            await TherapySessionController.refreshLiveActivitiesInBackground()
        }
    }
}
