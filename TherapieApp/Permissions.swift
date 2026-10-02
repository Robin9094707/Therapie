import SwiftUI
import EventKit
import AlarmKit
import AVFoundation
import CoreLocation
import UserNotifications

@MainActor
final class PermissionCoordinator: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var running = false
    @Published var current = ""
    @Published var results: [String: String] = [:]
    private let location = CLLocationManager()
    private var locationContinuation: CheckedContinuation<Bool, Never>?
    override init() { super.init(); location.delegate = self }

    func requestAll() async {
        guard !running else { return }
        running = true
        defer { running = false; current = "" }
        current = "Kalender"
        do {
            let state = EKEventStore.authorizationStatus(for: .event)
            let allowed = state == .notDetermined ? try await CalendarSyncService.shared.requestAccess() : state == .fullAccess
            results[current] = allowed ? "Erlaubt" : "Nicht erlaubt"
        } catch { results[current] = "Nicht verfügbar: " + error.localizedDescription }
        current = "Therapie-Alarme"
        do {
            let state = AlarmManager.shared.authorizationState
            let allowed = state == .notDetermined ? try await AlarmService.shared.requestAuthorization() : state == .authorized
            results[current] = allowed ? "Erlaubt" : "Nicht erlaubt"
        } catch { results[current] = "Nicht verfügbar: " + error.localizedDescription }
        current = "Mitteilungen"
        do {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            let allowed = settings.authorizationStatus == .notDetermined
                ? try await center.requestAuthorization(options: [.alert, .sound, .badge])
                : [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus)
            results[current] = allowed ? "Erlaubt" : "Nicht erlaubt"
        } catch { results[current] = "Nicht verfügbar: " + error.localizedDescription }
        current = "Mikrofon"
        let audioState = AVAudioApplication.shared.recordPermission
        let audioAllowed = audioState == .undetermined ? await AVAudioApplication.requestRecordPermission() : audioState == .granted
        results[current] = audioAllowed ? "Erlaubt" : "Nicht erlaubt"
        current = "Standort"
        let locationAllowed = await requestLocationPermission()
        results[current] = locationAllowed ? "Erlaubt" : "Nicht erlaubt"
        UserDefaults.standard.set(true, forKey: "therapy.permissions3000")
    }

    private func requestLocationPermission() async -> Bool {
        switch location.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                locationContinuation = continuation
                location.requestWhenInUseAuthorization()
            }
        default: return false
        }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard manager.authorizationStatus != .notDetermined, let continuation = locationContinuation else { return }
        locationContinuation = nil
        continuation.resume(returning: manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways)
    }
}

struct PermissionSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var permissions = PermissionCoordinator()
    @State private var started = false
    private let purposes = [
        ("Kalender", "calendar", "Therapietermine mit deinem iPhone-Kalender synchronisieren."),
        ("Therapie-Alarme", "alarm", "Die von dir eingerichteten Therapie-Erinnerungen auslösen."),
        ("Mitteilungen", "bell", "Eine freiwillige wöchentliche Check-in-Erinnerung anzeigen."),
        ("Mikrofon", "mic", "Sprachnotizen aufnehmen, wenn du eine Aufnahme startest."),
        ("Standort", "location", "Auf Wunsch den Ort zu einem neuen Foto speichern.")
    ]
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Deine Freigaben").font(.system(.title2, design: .rounded, weight: .bold))
                    Text("Beim ersten Öffnen fragt das iPhone die benötigten Freigaben nacheinander ab. Du entscheidest bei jeder Anfrage. Check-ins und Akku-Punkte funktionieren auch ohne diese Freigaben.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Section {
                    ForEach(purposes, id: \.0) { purpose in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: purpose.1).frame(width: 26).foregroundStyle(Color.accentColor)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(purpose.0).font(.headline)
                                Text(purpose.2).font(.caption).foregroundStyle(.secondary)
                                Text(permissions.results[purpose.0] ?? (permissions.current == purpose.0 ? "Wird abgefragt …" : "Noch nicht geprüft"))
                                    .font(.caption.bold())
                            }
                        }.padding(.vertical, 5)
                    }
                }
                Section {
                    Text("Fotos gibst du einzeln über die Systemauswahl frei. Einen Backup-Ordner wählst du selbst unter Profil. Dafür gibt es keine allgemeine Berechtigungsabfrage.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Link("iPhone-Einstellungen öffnen", destination: URL(string: UIApplication.openSettingsURLString)!)
                    Button(permissions.running ? "Freigaben werden geprüft …" : "Freigaben erneut prüfen") {
                        Task { await permissions.requestAll() }
                    }.disabled(permissions.running)
                }
            }
            .navigationTitle("App einrichten").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { UserDefaults.standard.set(true, forKey: "therapy.permissions3000"); dismiss() }
                        .disabled(permissions.running)
                }
            }
            .interactiveDismissDisabled(permissions.running)
            .task {
                guard !started, !ProcessInfo.processInfo.arguments.contains("--ui-testing") else { return }
                started = true
                try? await Task.sleep(for: .milliseconds(500))
                await permissions.requestAll()
            }
        }
    }
}

enum WeeklyReminderService {
    static let identifier = "therapy.weekly-checkin"
    static func apply(_ settings: WellnessSettings) async throws {
        let center = UNUserNotificationCenter.current()
        if !settings.reminderEnabled {
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            return
        }
        let granted = try await center.requestAuthorization(options: [.alert, .sound])
        guard granted else { throw ServiceError.permissionDenied("Mitteilungen sind nicht erlaubt. Du kannst sie in den iPhone-Einstellungen aktivieren.") }
        let content = UNMutableNotificationContent()
        content.title = "Ein Moment für dich"
        content.body = "Wenn es für dich passt, halte kurz fest, wie deine Woche war."
        content.sound = .default
        let components = DateComponents(hour: settings.reminderHour, minute: settings.reminderMinute, weekday: settings.reminderWeekday)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }
    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [identifier])
    }
}
