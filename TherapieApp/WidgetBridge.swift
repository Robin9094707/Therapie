import Foundation
import WidgetKit

@MainActor
enum TherapyWidgetBridge {
    private static var lastCache: Data?
    private static var lastRefresh = Date.distantPast
    static func refresh(_ store: AppStore, force: Bool = false) {
        guard store.loadError == nil, store.lastSaveError == nil else { return }
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: TherapyWidgetSnapshot.appGroup) else {
            store.widgetStatus = "Widgets sind vorbereitet. Der gemeinsame Zugriff benötigt beim Signieren die App-Gruppe group.eu.rjuhas.therapie für App und Erweiterung."
            return
        }
        do {
            let snapshot = TherapyWidgetSnapshotBuilder.make(data: store.data)
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            var comparable = snapshot; comparable.generatedAt = Date(timeIntervalSince1970: 0)
            let signature = try encoder.encode(comparable)
            if signature != lastCache || force || Date().timeIntervalSince(lastRefresh) >= 30 * 60 {
                let url = container.appendingPathComponent(TherapyWidgetSnapshot.fileName)
                let raw = try encoder.encode(snapshot)
                try raw.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                UserDefaults(suiteName: TherapyWidgetSnapshot.appGroup)?.set(raw, forKey: TherapyWidgetSnapshot.fileName)
                lastCache = signature; lastRefresh = Date()
                WidgetCenter.shared.reloadAllTimelines()
            }
            store.widgetStatus = "Widgets synchronisiert · Therapie, Routinen, Erinnerungen und laufende Stunde."
        } catch { store.widgetStatus = "Widgets konnten noch nicht aktualisiert werden: " + error.localizedDescription }
    }
}
