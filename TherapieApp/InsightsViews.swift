import SwiftUI
import Charts

struct MoodBarometerControl: View {
    @Binding var percent: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(MoodBarometer.title(percent)).font(.system(.title2, design: .rounded, weight: .semibold))
                Spacer(); Text("\(percent)").font(.system(.title, design: .rounded, weight: .bold)).monospacedDigit()
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(LinearGradient(colors: [.orange.opacity(0.75), .yellow.opacity(0.6), .teal.opacity(0.8), .indigo], startPoint: .leading, endPoint: .trailing))
                    Circle().fill(.white).overlay { Circle().strokeBorder(.indigo, lineWidth: 3) }.frame(width: 28, height: 28).offset(x: max(0, geometry.size.width - 28) * CGFloat(max(0, min(100, percent))) / 100)
                }.contentShape(Rectangle()).gesture(DragGesture(minimumDistance: 0).onChanged { value in percent = max(0, min(100, Int(value.location.x / max(1, geometry.size.width) * 100))) })
            }.frame(height: 28).accessibilityHidden(true)
            Slider(value: Binding(get: { Double(percent) }, set: { percent = Int($0) }), in: 0...100, step: 1).accessibilityLabel("Stimmungsbarometer").accessibilityValue("\(percent) von 100, \(MoodBarometer.title(percent))")
            HStack { Text("Sehr niedrig"); Spacer(); Text("Gemischt"); Spacer(); Text("Sehr gut") }.font(.caption).foregroundStyle(.secondary)
        }.padding(16).background(Color.indigo.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: percent)
    }
}
struct CheckInKeywordSection: View {
    @Binding var points: [BatteryPoint]
    let add: (BatteryDirection) -> Void
    let edit: (BatteryPoint) -> Void
    var body: some View {
        ForEach(BatteryDirection.allCases) { direction in
            VStack(alignment: .leading, spacing: 12) {
                HStack { Label(direction.title, systemImage: direction.symbol).font(.headline); Spacer(); Button { add(direction) } label: { Image(systemName: "plus.circle.fill").frame(width: 44, height: 44) }.accessibilityLabel(direction.title + " hinzufügen") }
                ForEach(points.filter { $0.direction == direction }) { point in
                    HStack(alignment: .top) {
                        Button { edit(point) } label: { VStack(alignment: .leading, spacing: 5) { Text(point.title).font(.headline); if !point.note.isEmpty { Text(point.note).font(.subheadline).foregroundStyle(.secondary) }; Text("Wirkung \(point.impact)/5").font(.caption).foregroundStyle(.secondary) } }.buttonStyle(.plain)
                        Spacer(); Button(role: .destructive) { let id = point.id; points.removeAll { $0.id == id } } label: { Image(systemName: "trash").frame(width: 44, height: 44) }.accessibilityLabel(point.title + " entfernen")
                    }
                }
                if !points.contains(where: { $0.direction == direction }) { Text("Ein Stichwort hinzufügen, zum Beispiel Technik. Ein erklärender Satz ist optional.").font(.caption).foregroundStyle(.secondary) }
            }.padding(14).background(direction == .gives ? Color.teal.opacity(0.06) : Color.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
        }
    }
}
struct CheckInKeywordEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var point: BatteryPoint
    let save: (BatteryPoint) -> Void
    private var valid: Bool { let title = point.title.trimmingCharacters(in: .whitespacesAndNewlines); return !title.isEmpty && title.count <= 40 && !title.contains(where: { $0.isWhitespace }) }
    var body: some View {
        NavigationStack {
            Form {
                Section(point.direction.title) {
                    TherapyInputField(title: "Ein Stichwort", prompt: "Zum Beispiel Technik", multiline: false, text: $point.title)
                    Text("Ein Wort ohne Leerzeichen. Erklärungen kommen in das Feld darunter.").font(.caption).foregroundStyle(.secondary)
                    TherapyInputField(title: "Ein Satz dazu (optional)", text: $point.note)
                    Stepper("Wie stark? \(point.impact)/5", value: $point.impact, in: 1...5)
                    Picker("Bereich", selection: $point.category) { ForEach(BatteryCategory.allCases) { Text($0.title).tag($0) } }
                }
            }.buttonStyle(.borderless).navigationTitle("Akku-Punkt").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Speichern") { var clean = point; clean.title = clean.title.trimmingCharacters(in: .whitespacesAndNewlines); save(clean); dismiss() }.disabled(!valid) }
                }
        }
    }
}
struct DayCheckInButtons: View {
    @EnvironmentObject private var store: AppStore
    let open: (GuidedCheckIn) -> Void
    var body: some View {
        SwiftUI.TimelineView(.periodic(from: .now, by: 30)) { context in
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145))], spacing: 10) {
                ForEach(DayCheckInPolicy.slots(store.data.companionSettings).filter(\.enabled)) { slot in
                    let entry = DayCheckInPolicy.reopen(DayCheckInPolicy.entry(slot, at: context.date), in: store.data)
                    let exists = store.data.guidedCheckIns.contains { $0.id == entry.id }
                    let allowed = exists || slot.contains(context.date)
                    Button {
                        guard exists || DayCheckInPolicy.allows(kind: slot.kind, id: slot.id, settings: store.data.companionSettings) else { return }
                        open(entry)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) { Label(slot.title.replacingOccurrences(of: "-Check-in", with: ""), systemImage: slot.kind.symbol).font(.subheadline.bold()); Text(exists ? (entry.isDraft ? "Entwurf fortsetzen" : "Heute erledigt · bearbeiten") : slot.windowText).font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
                    }.buttonStyle(.bordered).disabled(!allowed).accessibilityHint(allowed ? "Check-in starten" : "Verfügbar zwischen " + slot.windowText)
                }
            }
        }
    }
}
struct DayCheckInSettingsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State var slots: [DailyCheckInSlot]
    @State private var error: String?
    @State private var allowMultiple = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Mehrere Check-ins je Zeitfenster erlauben", isOn: $allowMultiple)
                    Text("Standardmäßig wird derselbe Check-in pro Tag wieder geöffnet. Eigene Zeitfenster zählen separat. Neue Tages-Check-ins sind nur innerhalb ihres Zeitfensters verfügbar. Begonnene Entwürfe und ältere Einträge kannst du weiterhin bearbeiten. Therapie- und freie Check-ins sind jederzeit möglich.") }
                ForEach(slots) { initial in
                    let slot = identifiedEditorBinding($slots, to: initial)
                    Section(initial.title) {
                        Toggle("Aktiv", isOn: slot.enabled)
                        if initial.kind == .free { TextField("Name", text: slot.name) }
                        Stepper("Beginn: \(slot.wrappedValue.startHour):00", value: slot.startHour, in: 0...23)
                        Stepper("Ende: \(slot.wrappedValue.endHour):00", value: slot.endHour, in: 0...23)
                        Text(slot.wrappedValue.windowText).font(.caption).foregroundStyle(.secondary)
                        if initial.kind == .free { Button("Eigenen Check-in entfernen", role: .destructive) { let id = initial.id; slots.removeAll { $0.id == id } } }
                    }
                }
                Button("Eigenen Check-in ergänzen", systemImage: "plus.circle") { slots.append(DailyCheckInSlot(kind: .free, name: "Mein Check-in", startHour: 12, endHour: 14)) }
                if let error { Text(error).foregroundStyle(.red) }
            }.onAppear { allowMultiple = store.data.companionSettings.allowMultipleCheckInsPerSlot ?? false }.buttonStyle(.borderless).navigationTitle("Dein Check-in-Rhythmus").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Speichern") { var snapshot = store.data; snapshot.companionSettings.dayCheckInSlots = slots; snapshot.companionSettings.allowMultipleCheckInsPerSlot = allowMultiple; store.data = snapshot; if store.lastSaveError == nil { dismiss() } else { error = store.lastSaveError } }.disabled(slots.contains { $0.kind == .free && $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) }
                }
        }
    }
}
struct InsightsHubView: View {
    @EnvironmentObject private var store: AppStore
    @State private var range: WellnessRange = .thirty
    @State private var mood: MoodCheckIn?
    @State private var report = false
    private var period: WellnessPeriod { range.period }
    var body: some View {
        NavigationStack {
            TherapyScreen {
                LazyVStack(alignment: .leading, spacing: 16) {
                    GlassCard(emphasized: true) {
                        VStack(alignment: .leading, spacing: 14) {
                            Text(store.data.profile.userName.isEmpty ? "Dein persönlicher Überblick" : "Der Überblick für " + store.data.profile.userName).font(.system(.title2, design: .rounded, weight: .bold))
                            Text("Stimmung, Akku, kleine Schritte – so, wie du sie festgehalten hast.").foregroundStyle(.secondary)
                            Picker("Zeitraum", selection: $range) { ForEach(WellnessRange.allCases) { Text($0.rawValue).tag($0) } }
                            Button("Stimmung eintragen", systemImage: "face.smiling") { mood = MoodCheckIn() }.buttonStyle(.borderedProminent)
                            NavigationLink { WellnessHubView() } label: { Label("Alle Einträge & Wochenrückblicke", systemImage: "list.bullet.rectangle") }
                        }
                    }
                    if let comparison = InsightsAnalytics.comparison(data: store.data) {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 10) {
                                SectionHeader(title: "Dein Stimmungsbarometer", icon: "gauge.with.dots.needle.50percent")
                                Text("Zuletzt \(comparison.latest, specifier: "%.1f") / 5").font(.title2.bold())
                                ProgressView(value: max(0, min(100, (comparison.latest - 1) * 25)), total: 100).tint(.indigo)
                                Text(comparison.message).font(.subheadline)
                                if let value = comparison.reference { Text("Vergleich: \(value, specifier: "%.1f") / 5 aus \(min(14, comparison.previousDays)) früheren Tagen innerhalb der letzten 30 Tage.").font(.caption).foregroundStyle(.secondary) }
                                if let trend = InsightsAnalytics.trend(data: store.data, period: period) { Text("Trend im gewählten Zeitraum: \(trend >= 0 ? "+" : "")\(trend, specifier: "%.1f") Punkte zwischen erster und zweiter Hälfte der erfassten Tage.").font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                    }
                    WellnessChartsView(period: period)
                    ForEach(BatteryDirection.allCases) { direction in
                        GlassCard {
                            VStack(alignment: .leading, spacing: 12) {
                                SectionHeader(title: direction == .gives ? "Was lädt deinen Akku?" : "Was kostet dich Akku?", icon: direction.symbol, subtitle: "Stichwörter aus deinen Einträgen, nach selbst bewerteter Wirkung.")
                                let topics = InsightsAnalytics.keywords(data: store.data, period: period).filter { $0.direction == direction }
                                if topics.isEmpty { Text("Noch keine einzelnen Akku-Punkte in diesem Zeitraum.").foregroundStyle(.secondary) }
                                ForEach(topics.prefix(8)) { topic in
                                    DisclosureGroup {
                                        ForEach(topic.points.prefix(6)) { point in VStack(alignment: .leading, spacing: 4) { Text(point.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary); Text(point.note.isEmpty ? "Keine Zusatznotiz" : point.note).font(.subheadline) } }
                                    } label: {
                                        VStack(alignment: .leading, spacing: 4) { Text(topic.keyword).font(.headline); Text("\(topic.count) Einträge · Wirkungssumme \(topic.impact)").font(.caption).foregroundStyle(.secondary) }
                                    }
                                }
                            }
                        }
                    }
                    GlassCard(emphasized: true) {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "Für deine Therapie", icon: "doc.text", subtitle: "Den Überblick gemeinsam ansehen oder die letzte Woche als PDF mitnehmen.")
                            Button("Wochenbericht als PDF / drucken", systemImage: "printer") { report = true }.buttonStyle(.borderedProminent)
                            NavigationLink { TherapyHubView() } label: { Label("Therapie, Ziele & Beiträge", systemImage: "leaf") }
                            Text("Vergleiche beschreiben deine Angaben. Sie sind keine Diagnose; freie Tage werden nicht als schlechte Stimmung gewertet.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }.buttonStyle(.borderless).navigationTitle("Insights")
                .sheet(item: $mood) { MoodEditorView(entry: $0) }
                .sheet(isPresented: $report) { WeeklyPDFReportView() }
        }
    }
}

struct PersonalWelcomeCard: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    var body: some View {
        SwiftUI.TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(alignment: .leading, spacing: 8) {
                Text(PersonalGreeting.title(at: context.date, name: store.data.profile.userName)).font(.system(.title, design: .rounded, weight: .bold))
                Text(PersonalGreeting.sentence(at: context.date)).font(.subheadline).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
                .opacity(appeared ? 1 : 0).offset(y: appeared || reduceMotion ? 0 : 8)
        }
        .onAppear { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.35)) { appeared = true } }
        .onChange(of: scenePhase) { _, phase in if phase == .active { appeared = true } }
    }
}
