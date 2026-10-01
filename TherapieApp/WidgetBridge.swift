import Foundation
import WidgetKit

@MainActor
enum TherapyWidgetBridge {
    private static var lastCache: Data?
    static func refresh(_ store: AppStore) {
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
            if signature != lastCache {
                let url = container.appendingPathComponent(TherapyWidgetSnapshot.fileName)
                try encoder.encode(snapshot).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                lastCache = signature
                WidgetCenter.shared.reloadAllTimelines()
            }
            store.widgetStatus = "Widgets synchronisiert · Therapie, Routinen, Erinnerungen und laufende Stunde."
        } catch { store.widgetStatus = "Widgets konnten noch nicht aktualisiert werden: " + error.localizedDescription }
    }
}
