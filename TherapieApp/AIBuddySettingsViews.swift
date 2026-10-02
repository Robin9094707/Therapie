import SwiftUI

struct AIBuddySettingsCard: View {
    @State private var show = false
    @EnvironmentObject private var store: AppStore
    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Dein optionaler KI-Begleiter", icon: "sparkles", subtitle: store.data.aiSettings.enabled ? "Gespräche, Rückblicke und bearbeitbare App-Vorschläge" : "Die App funktioniert vollständig ohne KI.")
                Button("KI & OpenAI-Schlüssel einrichten", systemImage: "key") { show = true }.buttonStyle(.bordered)
                if store.data.aiSettings.enabled || !store.data.aiConversations.isEmpty { NavigationLink { AIBuddyView() } label: { Label("Meine KI-Gespräche", systemImage: "bubble.left.and.bubble.right") } }
                NavigationLink { TherapyJournalView() } label: { Label("Mein Therapietagebuch", systemImage: "book.closed") }
                Text("Gespeicherte Eingaben lassen sich zehn Minuten lang rückgängig machen, solange die App geöffnet bleibt. Auch gelöschte lokale Anhänge bleiben in diesem Zeitraum verfügbar.").font(.caption).foregroundStyle(.secondary)
            }
        }.sheet(isPresented: $show) { AIBuddySettingsView() }
    }
}
struct AIBuddySettingsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var hasKey = AIBuddyKeychain.read() != nil
    @State private var status = ""
    @State private var deleteKey = false
    var body: some View {
        NavigationStack {
            Form {
                Section("Optional aktivieren") {
                    Toggle("KI-Begleiter verwenden", isOn: $store.data.aiSettings.enabled)
                    Toggle("Check-ins standardmäßig mit KI führen", isOn: $store.data.aiSettings.preferGuidedCheckIns)
                    Text("Du kannst jederzeit zum normalen Check-in wechseln. Der Entwurf und das Gespräch bleiben erhalten.").font(.caption).foregroundStyle(.secondary)
                    Text("Beim Senden werden deine Nachricht und der angezeigte Textzeitraum an OpenAI übertragen. Aktuelle offene Aufgaben, Routinen und Gesprächspunkte können zusätzlich enthalten sein. Keine automatischen Anfragen im Hintergrund. Die OpenAI-API wird getrennt von einem ChatGPT-Abo abgerechnet.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Persönlicher API-Schlüssel") {
                    SecureField(hasKey ? "Neuen Schlüssel hinterlegen" : "OpenAI-API-Schlüssel", text: $key).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Schlüssel sicher speichern") {
                        do { try AIBuddyKeychain.save(key); key = ""; hasKey = true; status = "Im iPhone-Schlüsselbund gespeichert." } catch { status = error.localizedDescription }
                    }.disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if hasKey { Button("Schlüssel entfernen", role: .destructive) { deleteKey = true } }
                    Text("Der Schlüssel bleibt auf diesem iPhone und wird niemals exportiert. Nach Import auf ein anderes Gerät bitte neu hinterlegen.").font(.caption).foregroundStyle(.secondary)
                    if !status.isEmpty { Text(status).font(.caption) }
                }
                Section("Modelle & Aufwand") {
                    Picker("Text-Modell", selection: $store.data.aiSettings.model) {
                        Text("GPT-5.6 Luna · Standard").tag("gpt-5.6-luna")
                        Text("GPT-6 Luna · sparsam").tag("gpt-6-luna")
                        Text("GPT-5.6 Terra").tag("gpt-5.6-terra")
                        Text("GPT-6.1 Sol").tag("gpt-6.1-sol")
                        if !["gpt-5.6-luna", "gpt-6-luna", "gpt-5.6-terra", "gpt-6.1-sol"].contains(store.data.aiSettings.model) { Text(store.data.aiSettings.model).tag(store.data.aiSettings.model) }
                    }
                    TextField("Eigene kompatible Modell-ID", text: $store.data.aiSettings.model).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Picker("Sprache zu Text", selection: $store.data.aiSettings.transcriptionModel) { Text("GPT-4o Mini Transcribe · günstig").tag("gpt-4o-mini-transcribe"); Text("GPT Transcribe · aktuelles Modell").tag("gpt-transcribe") }
                    Text("Preisstand 01.10.2026: GPT-5.6 Luna $0,20 / $1,20 und GPT-6 Luna $0,10 / $0,50 je Mio. Eingabe-/Ausgabetokens. Mini Transcribe etwa $0,003 pro Minute, GPT Transcribe etwa $0,0045. Bilder und Wiederholungen können zusätzliche Kosten verursachen; tatsächliche Abrechnung bei OpenAI.").font(.caption).foregroundStyle(.secondary)
                    Link("Aktuelle OpenAI-API-Preise", destination: URL(string: "https://developers.openai.com/api/docs/pricing")!)
                }
                Section("Dein Kontext") {
                    Stepper("Standard: letzte \(store.data.aiSettings.contextDays) Tage", value: $store.data.aiSettings.contextDays, in: 1...90)
                    Toggle("Zeitraum aus der Frage erkennen", isOn: $store.data.aiSettings.automaticRange)
                    Toggle("Notizen & Tagebuch einbeziehen", isOn: $store.data.aiSettings.includeJournal)
                    Text("Maximal 100 Text-Einträge mit begrenzter Textlänge. Der verwendete Zeitraum und ausgelassene Einträge werden angezeigt. Anhänge werden nie automatisch hochgeladen.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Zusätzliche Uploads") {
                    Toggle("Ausgewähltes Foto analysieren dürfen", isOn: $store.data.aiSettings.allowPhotoUploads)
                    Toggle("Sprachnachricht transkribieren dürfen", isOn: $store.data.aiSettings.allowVoiceUploads)
                    Text("Vor jedem Foto-Upload folgt eine Bestätigung. Eine Sprachaufnahme sendest du ausdrücklich zum Transkribieren und kannst den Text vor dem Chat-Senden bearbeiten. Keine Aufnahme der Therapiestunde im Hintergrund.").font(.caption).foregroundStyle(.secondary)
                }
            }.navigationTitle("KI-Begleiter").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { key = ""; dismiss() } } }
                .alert("API-Schlüssel entfernen?", isPresented: $deleteKey) { Button("Abbrechen", role: .cancel) {}; Button("Entfernen", role: .destructive) { AIBuddyKeychain.remove(); hasKey = false; store.data.aiSettings.enabled = false } }
        }
    }
}

struct TherapyJournalView: View {
    @EnvironmentObject private var store: AppStore
    @State private var edited: TherapyNote?
    private var notes: [TherapyNote] { store.data.notes.filter { $0.category == "Therapietagebuch" || $0.tags.contains("Tagebuch") }.sorted { $0.createdAt > $1.createdAt } }
    var body: some View {
        TherapyScreen {
            LazyVStack(alignment: .leading, spacing: 16) {
                GlassCard(emphasized: true) {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Raum für deine Gedanken", icon: "book.closed", subtitle: "Ein Gedanke, ein Satz oder ein Rückblick – in deinem Tempo.")
                        Button("Tagebucheintrag schreiben", systemImage: "square.and.pencil") { edited = TherapyNote(title: "Mein Tag", text: "", tags: ["Tagebuch"], category: "Therapietagebuch") }.buttonStyle(.borderedProminent)
                        if store.data.aiSettings.enabled { NavigationLink { AIBuddyView() } label: { Label("Gemeinsam mit KI reflektieren", systemImage: "sparkles") } }
                    }
                }
                ForEach(notes) { note in
                    GlassCard { Button { edited = note } label: { VStack(alignment: .leading, spacing: 8) { Text(note.title).font(.headline); Text(note.createdAt.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary); Text(note.text).font(.subheadline).lineLimit(5) }.frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(.plain) }
                }
            }
        }.navigationTitle("Therapietagebuch").sheet(item: $edited) { TherapyNoteEditorView(note: $0) }
    }
}
