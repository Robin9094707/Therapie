import Foundation
import WidgetKit

@MainActor
enum TherapyWidgetBridge {
    private static var lastCache: Data?
    private static var lastRefresh = Date.distantPast
    static func refresh(_ store: AppStore, force: Bool = false) {
        guard store.loadError == nil, store.lastSaveError == nil else { return }
        guard let storage = TherapyWidgetStorage.container() else {
            store.widgetStatus = "Widgets sind vorbereitet. Der gemeinsame Zugriff benötigt beim Signieren die App-Gruppe group.eu.rjuhas.therapie für App und Erweiterung."
            WidgetCenter.shared.reloadAllTimelines()
            return
        }
        do {
            let snapshot = TherapyWidgetSnapshotBuilder.make(data: store.data)
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            var comparable = snapshot; comparable.generatedAt = Date(timeIntervalSince1970: 0)
            let signature = try encoder.encode(comparable)
            if signature != lastCache || force || Date().timeIntervalSince(lastRefresh) >= 30 * 60 {
                let url = storage.url.appendingPathComponent(TherapyWidgetSnapshot.fileName)
                let raw = try encoder.encode(snapshot)
                try raw.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                UserDefaults(suiteName: storage.group)?.set(raw, forKey: TherapyWidgetSnapshot.fileName)
                lastCache = signature; lastRefresh = Date()
                WidgetCenter.shared.reloadAllTimelines()
            }
            store.widgetStatus = "Widget-Daten geschrieben: " + Date().formatted(date: .omitted, time: .shortened) + " · Zugriff: " + storage.group + " · „Heute · direkt“ und „Duschtage · direkt“ benötigen keine Konfiguration."
        } catch { store.widgetStatus = "Widgets konnten noch nicht aktualisiert werden: " + error.localizedDescription }
    }
}
