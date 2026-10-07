import SwiftUI
import UIKit
import AppIntents

struct ApplePageDestination: View {
    let page: String
    var body: some View {
        switch page {
        case "emergency": EmergencyPlanView()
        case "medicalpass": MedicalPassView()
        case "alarms": WakeAlarmHubView()
        case "methods": MethodsHubView()
        case "grounding": GroundingExerciseView()
        default:
            if page.hasPrefix("wake|") { WakeChallengeView(route: page) }
            else { AppleIntegrationView() }
        }
    }
}
struct MedicalPassView: View {
    @EnvironmentObject private var store: AppStore
    @State private var editing = false
    private var pass: MedicalPass { store.data.medicalPass }
    var body: some View {
        TherapyScreen {
            VStack(alignment: .leading, spacing: 16) {
                GlassCard(emphasized: true) {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(pass.name.isEmpty ? store.data.profile.userName : pass.name, systemImage: "person.text.rectangle").font(.title2.bold())
                        if let birthDate = pass.birthDate { LabeledContent("Geboren", value: birthDate.formatted(date: .numeric, time: .omitted)) }
                        if let age = pass.age() { LabeledContent("Alter", value: "\(age) Jahre") }
                        if let height = pass.heightCM { LabeledContent("Größe", value: "\(height) cm") }
                        Text("Deine eigenen Angaben – beim Vorzeigen prüfst du, ob sie aktuell sind.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                passCard("Medikamente & Einnahmeplan", text: pass.medications, icon: "pills.fill")
                passCard("Wichtige Informationen", text: pass.conditions, icon: "heart.text.clipboard")
                passCard("Allergien / Unverträglichkeiten", text: pass.allergies, icon: "exclamationmark.circle")
                passCard("Kontakte", text: pass.contacts, icon: "person.2.fill")
                passCard("Weitere Angaben", text: pass.notes, icon: "note.text")
                GlassCard { VStack(alignment: .leading, spacing: 12) {
                    Label("Meine Methoden", systemImage: "sparkles").font(.headline)
                    ForEach(store.data.copingMethods) { method in NavigationLink { MethodDetailView(methodID: method.id) } label: { VStack(alignment: .leading, spacing: 4) { Text(method.title).bold(); if !method.situation.isEmpty { Text(method.situation).font(.caption).foregroundStyle(.secondary) } } } }
                    if store.data.copingMethods.isEmpty { Text("Deine gespeicherten Methoden erscheinen hier.").foregroundStyle(.secondary) }
                } }
                NavigationLink { EmergencyPlanView() } label: { Label("Mein Notfallplan", systemImage: "lifepreserver.fill") }.buttonStyle(.borderedProminent)
            }
        }.navigationTitle("Therapiepass").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Bearbeiten", systemImage: "pencil") { editing = true } } }
            .sheet(isPresented: $editing) { MedicalPassEditor(pass: pass) }
    }
    @ViewBuilder private func passCard(_ title: String, text: String, icon: String) -> some View {
        if !text.isEmpty { GlassCard { VStack(alignment: .leading, spacing: 8) { Label(title, systemImage: icon).font(.headline).foregroundStyle(Color.accentColor); Text(text).textSelection(.enabled) }.frame(maxWidth: .infinity, alignment: .leading) } }
    }
}
private struct MedicalPassEditor: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State var pass: MedicalPass
    var body: some View {
        NavigationStack {
            Form {
                Section("Über mich") {
                    TextField("Name", text: $pass.name)
                    Toggle("Geburtsdatum angeben", isOn: Binding(get: { pass.birthDate != nil }, set: { pass.birthDate = $0 ? Calendar.current.date(byAdding: .year, value: -18, to: Date()) : nil }))
                    if pass.birthDate != nil { DatePicker("Geburtsdatum", selection: Binding(get: { pass.birthDate ?? Date() }, set: { pass.birthDate = $0 }), in: ...Date(), displayedComponents: .date) }
                    Toggle("Größe angeben", isOn: Binding(get: { pass.heightCM != nil }, set: { pass.heightCM = $0 ? 170 : nil }))
                    if pass.heightCM != nil { Stepper("\(pass.heightCM ?? 170) cm", value: Binding(get: { pass.heightCM ?? 170 }, set: { pass.heightCM = $0 }), in: 30...250) }
                }
                Section("Medikamente") { TextField("Deinen ärztlich festgelegten Einnahmeplan eintragen", text: $pass.medications, axis: .vertical).lineLimit(4...12); Text("Die App gibt keine Dosierung vor. Hier trägst du deine aktuellen Informationen selbst ein.").font(.caption).foregroundStyle(.secondary) }
                Section("Weitere Angaben") {
                    TextField("Wichtige Erkrankungen / Hinweise", text: $pass.conditions, axis: .vertical).lineLimit(2...8)
                    TextField("Allergien / Unverträglichkeiten", text: $pass.allergies, axis: .vertical).lineLimit(2...8)
                    TextField("Kontakte / Telefonnummern", text: $pass.contacts, axis: .vertical).lineLimit(2...8)
                    TextField("Eigene Notizen", text: $pass.notes, axis: .vertical).lineLimit(2...8)
                }
                if let error = store.lastSaveError { Text(error).foregroundStyle(.red) }
            }.navigationTitle("Therapiepass bearbeiten").toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Speichern") { store.data.medicalPass = pass; if store.lastSaveError == nil { dismiss() } } }
            }
        }
    }
}
struct AppleIntegrationView: View {
    @EnvironmentObject private var store: AppStore
    @ObservedObject private var home = TherapyHomeService.shared
    var body: some View {
        Form {
            Section("Apple-Erinnerungen") {
                Toggle("Eigene Erinnerungen-Liste verwenden", isOn: $store.data.appleIntegration.remindersEnabled)
                Button("Zugriff erlauben & verbinden", systemImage: "checklist") { Task { await AppleRemindersService.shared.connect(store) } }
                Button("Jetzt abgleichen", systemImage: "arrow.clockwise") { AppleRemindersService.shared.refresh(store) }
                Text(store.appleReminderStatus).font(.caption)
                Toggle("Bestätigte Einträge entfernen", isOn: $store.data.appleIntegration.removeFinishedReminders)
                Toggle("Neutrale Titel in Erinnerungen", isOn: $store.data.appleIntegration.privateReminderTitles)
                Stepper("Standard: Wecker \(store.data.appleIntegration.alarmDelayMinutes) Minuten später", value: $store.data.appleIntegration.alarmDelayMinutes, in: 0...180, step: 5)
                Text("Fällige Routinen und Aufgaben mit Datum werden in „Therapie · Routinen“ angelegt. Nur app-eigene Einträge werden geändert. Die Liste kannst du in Apples Erinnerungen-Widget auswählen – das benötigt keine gemeinsame App-Gruppe.").font(.footnote)
                Text("Der Abgleich läuft beim Öffnen, bei Datenänderungen und bei Änderungen in Apple-Erinnerungen während die App aktiv ist. Im Hintergrund ist keine dauerhafte Überwachung garantiert. Ein vorher geplanter AlarmKit-Wecker kann deshalb trotz externer Bestätigung klingeln. Öffne die App für den rechtzeitigen Abgleich.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Wecker") {
                Button("AlarmKit freigeben", systemImage: "alarm.fill") { Task { await RoutineAlarmCoordinator.shared.requestAccess(store) } }
                Text(store.routineAlarmStatus).font(.caption)
                NavigationLink("Wecker & Aufsteh-Aufgaben") { WakeAlarmHubView() }
            }
            Section("Kurzbefehle & Siri") {
                ShortcutsLink()
                Text("In Kurzbefehle unter Apps → Therapie findest du den Notfallplan, Therapiepass, Methoden, Duschtage, Routinen und Wecker. Du kannst eine Routine bestätigen oder auslassen, einen Wecker aktivieren, heute aussetzen und eine Home-Szene ausführen.").font(.footnote)
                Text("Lege persönliche Automationen für feste Uhrzeiten und Home-Szenen in Kurzbefehle an. Eine geschlossene Therapie-App kann eine Home-Szene beim Klingeln nicht garantiert ausführen.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Apple Home") {
                Button("Home-Szenen laden", systemImage: "house.fill") { home.connect() }
                Text(home.status).font(.caption)
                Text("Verknüpfte Szenen starten beim Öffnen einer fälligen Routine oder Wecker-Aufgabe. Für HomeKit muss dein Signaturprofil die entsprechende Berechtigung erhalten. Geräte- und Szenenverknüpfungen werden auf diesem iPhone gespeichert und nach einem Import neu gewählt.").font(.footnote)
            }
            Section("Widgets") { NavigationLink("Widget-Zugriff & Alternativen") { WidgetSetupHelpView() } }
        }.buttonStyle(.borderless).navigationTitle("Apple-Integration").navigationBarTitleDisplayMode(.inline)
            .onAppear { AppleRemindersService.shared.refresh(store) }
    }
}
struct HomeSceneBindingView: View {
    let ownerID: UUID
    @ObservedObject private var home = TherapyHomeService.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("Optionale Home-Szene laden", systemImage: "house.fill") { home.connect() }
            if !home.scenes.isEmpty {
                Picker("Beim Öffnen ausführen", selection: Binding(get: { home.binding(for: ownerID) }, set: { home.bind($0, to: ownerID) })) { Text("Keine Szene").tag(""); ForEach(home.scenes) { Text($0.title).tag($0.id) } }
                Button("Verknüpfte Szene testen") { home.run(for: ownerID) }.disabled(home.binding(for: ownerID).isEmpty)
            }
            Text(home.status).font(.caption).foregroundStyle(.secondary)
        }
    }
}
