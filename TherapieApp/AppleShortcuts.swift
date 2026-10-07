import AppIntents
import Foundation

@MainActor
enum TherapyIntentRuntime {
    static var liveStore: AppStore?
    static func store() -> AppStore { if let liveStore { return liveStore }; let value = AppStore(); liveStore = value; return value }
    static func writableStore() throws -> AppStore {
        let value = store()
        guard value.storageReady, value.lastSaveError == nil else { throw ServiceError.generic("Öffne und entsperre die Therapie-App, damit deine Daten sicher verfügbar sind.") }
        return value
    }
}
enum TherapyShortcutPage: String, AppEnum {
    case emergency, medicalpass, alarms, apple, methods, grounding, showers, routines, today, archive, reminders, session
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Bereich"
    static var caseDisplayRepresentations: [Self:DisplayRepresentation] = [
        .emergency:"Notfallplan", .medicalpass:"Therapiepass", .alarms:"Wecker", .apple:"Apple-Integration", .methods:"Methoden", .grounding:"5-4-3-2-1", .showers:"Duschtage", .routines:"Routinen", .today:"Heute", .archive:"Archiv", .reminders:"Aufgaben", .session:"Therapie-Timer"]
}
struct OpenTherapyPageIntent: AppIntent {
    static var title: LocalizedStringResource = "Therapiebereich öffnen"
    static var description = IntentDescription("Öffnet deinen persönlichen Plan oder einen Bereich direkt in der App.")
    static var openAppWhenRun = true
    @Parameter(title: "Bereich") var page: TherapyShortcutPage
    init() {}
    init(page: TherapyShortcutPage) { self.page = page }
    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set("page|" + page.rawValue, forKey: "therapy.apple.shortcut")
        return .result()
    }
}
struct TherapyRoutineEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Routine"
    static var defaultQuery = TherapyRoutineQuery()
    var id: UUID
    var name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}
struct TherapyRoutineQuery: EntityQuery {
    @MainActor func entities(for identifiers: [UUID]) async throws -> [TherapyRoutineEntity] { try await suggestedEntities().filter { identifiers.contains($0.id) } }
    @MainActor func suggestedEntities() async throws -> [TherapyRoutineEntity] { try TherapyIntentRuntime.writableStore().data.routines.map { .init(id:$0.id,name:$0.title) } }
}
enum TherapyRoutineShortcutAction: String, AppEnum {
    case done, skipped, home
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Aktion"
    static var caseDisplayRepresentations: [Self:DisplayRepresentation] = [.done:"Heutigen Termin bestätigen",.skipped:"Heutigen Termin auslassen",.home:"Verknüpfte Home-Szene ausführen"]
}
struct PerformRoutineShortcutIntent: AppIntent {
    static var title: LocalizedStringResource = "Routine-Aktion ausführen"
    static var openAppWhenRun = true
    @Parameter(title:"Routine") var routine: TherapyRoutineEntity
    @Parameter(title:"Aktion") var action: TherapyRoutineShortcutAction
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = try TherapyIntentRuntime.writableStore()
        if action == .home { TherapyHomeService.shared.run(for:routine.id); store.notificationApplePage = "apple"; return .result(dialog:"Die verknüpfte Home-Szene wurde angefragt. Prüfe ihren Status in der App.") }
        guard let occurrence = RoutinePlanner.occurrences(data:store.data,now:Date(),days:1).first(where: { $0.routineID == routine.id && Calendar.current.isDateInToday($0.due) && !RoutinePlanner.resolved($0,completions:store.data.routineCompletions) }) else { return .result(dialog:"Für heute ist kein offener Termin dieser Routine vorhanden.") }
        var snapshot = store.data
        guard RoutineDayMutation.resolve(occurrence, outcome: action == .done ? .done : .skipped, note:"Über Kurzbefehle bestätigt", in:&snapshot) else { throw ServiceError.generic("Dieser Termin ist nicht mehr offen.") }
        store.data = snapshot
        guard store.lastSaveError == nil else { throw ServiceError.generic(store.lastSaveError!) }
        return .result(dialog:"Deine Routine wurde für diesen Termin gespeichert.")
    }
}
struct TherapyWakeEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Wecker"
    static var defaultQuery = TherapyWakeQuery()
    var id: UUID
    var name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title:"\(name)") }
}
struct TherapyWakeQuery: EntityQuery {
    @MainActor func entities(for identifiers:[UUID]) async throws -> [TherapyWakeEntity] { try await suggestedEntities().filter { identifiers.contains($0.id) } }
    @MainActor func suggestedEntities() async throws -> [TherapyWakeEntity] { try TherapyIntentRuntime.writableStore().data.wakeAlarms.map { .init(id:$0.id,name:$0.title) } }
}
enum TherapyWakeShortcutAction: String, AppEnum {
    case enable, disable, skipNext, home
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Wecker-Aktion"
    static var caseDisplayRepresentations: [Self:DisplayRepresentation] = [.enable:"Aktivieren",.disable:"Deaktivieren",.skipNext:"Nächsten Termin aussetzen",.home:"Verknüpfte Home-Szene ausführen"]
}
struct PerformWakeShortcutIntent: AppIntent {
    static var title: LocalizedStringResource = "Wecker-Aktion ausführen"
    static var openAppWhenRun = true
    @Parameter(title:"Wecker") var alarm: TherapyWakeEntity
    @Parameter(title:"Aktion") var action: TherapyWakeShortcutAction
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = try TherapyIntentRuntime.writableStore()
        guard var value = store.data.wakeAlarms.first(where: { $0.id == alarm.id }) else { throw ServiceError.generic("Dieser Wecker existiert nicht mehr.") }
        switch action {
        case .enable: value.enabled = true
        case .disable: value.enabled = false
        case .skipNext:
            guard let occurrence = WakePlanner.occurrences(data:store.data).first(where: { $0.alarm.id == alarm.id && $0.date > Date() }) else { return .result(dialog:"Kein nächster aktiver Wecker gefunden.") }
            value.excludedDays.append(occurrence.date)
        case .home: TherapyHomeService.shared.run(for:alarm.id); store.notificationApplePage = "apple"; return .result(dialog:"Die verknüpfte Home-Szene wurde angefragt.")
        }
        store.saveWakeAlarm(value)
        guard store.lastSaveError == nil else { throw ServiceError.generic(store.lastSaveError!) }
        await RoutineAlarmCoordinator.shared.refresh(store)
        return .result(dialog:"Dein Wecker wurde angepasst.")
    }
}
struct TherapyAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent:OpenTherapyPageIntent(page:.emergency), phrases:["Öffne den Notfallplan in \(.applicationName)"], shortTitle:"Notfallplan", systemImageName:"lifepreserver.fill")
        AppShortcut(intent:OpenTherapyPageIntent(page:.medicalpass), phrases:["Öffne meinen Pass in \(.applicationName)"], shortTitle:"Therapiepass", systemImageName:"person.text.rectangle")
        AppShortcut(intent:OpenTherapyPageIntent(page:.alarms), phrases:["Öffne die Wecker in \(.applicationName)"], shortTitle:"Wecker", systemImageName:"alarm.fill")
        AppShortcut(intent:OpenTherapyPageIntent(page:.methods), phrases:["Öffne die Methoden in \(.applicationName)"], shortTitle:"Methoden", systemImageName:"sparkles")
        AppShortcut(intent:OpenTherapyPageIntent(page:.grounding), phrases:["Starte die Sinnesübung in \(.applicationName)"], shortTitle:"5-4-3-2-1", systemImageName:"hand.raised.fill")
        AppShortcut(intent:OpenTherapyPageIntent(page:.showers), phrases:["Öffne die Duschtage in \(.applicationName)"], shortTitle:"Duschtage", systemImageName:"shower.fill")
        AppShortcut(intent:OpenTherapyPageIntent(page:.routines), phrases:["Öffne die Routinen in \(.applicationName)"], shortTitle:"Routinen", systemImageName:"checklist")
        AppShortcut(intent:OpenTherapyPageIntent(page:.today), phrases:["Öffne heute in \(.applicationName)"], shortTitle:"Heute", systemImageName:"sun.max.fill")
        AppShortcut(intent:OpenTherapyPageIntent(page:.reminders), phrases:["Öffne die Aufgaben in \(.applicationName)"], shortTitle:"Aufgaben", systemImageName:"checkmark.circle")
        AppShortcut(intent:OpenTherapyPageIntent(page:.session), phrases:["Öffne den Timer in \(.applicationName)"], shortTitle:"Therapie-Timer", systemImageName:"timer")
    }
}
