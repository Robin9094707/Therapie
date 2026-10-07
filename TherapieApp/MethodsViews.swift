import SwiftUI

struct MethodsHubView: View {
    @EnvironmentObject private var store: AppStore
    @State private var query = ""
    @State private var category: BatteryCategory?
    @State private var stage: MethodStage?
    @State private var thoughtStopsOnly = false
    @State private var draft: CopingMethod?
    @State private var showAI = false
    private var methods: [CopingMethod] {
        store.data.copingMethods.filter { (!thoughtStopsOnly || $0.kind == .thoughtStop) && $0.matches(category: category, stage: stage, query: query, data: store.data) }
            .sorted { $0.favorite != $1.favorite ? $0.favorite : $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
    var body: some View {
        TherapyScreen {
            LazyVStack(alignment: .leading, spacing: 18) {
                GlassCard(emphasized: true) {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeader(title: "Was hilft mir wann?", icon: "square.grid.2x2.fill", subtitle: "Deine persönlichen Zuordnungen. Du entscheidest, was für dich passt.")
                        Picker("Akkuthema", selection: $category) {
                            Text("Alle Akkuthemen").tag(BatteryCategory?.none)
                            ForEach(BatteryCategory.allCases) { Text($0.title).tag(Optional($0)) }
                        }
                        methodMap
                        if stage != nil || category != nil { Button("Alle Zuordnungen anzeigen", systemImage: "line.3.horizontal.decrease.circle") { stage = nil; category = nil } }
                        Toggle("Nur Gedankenstopps", isOn: $thoughtStopsOnly)
                    }
                }
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        NavigationLink { GroundingExerciseView() } label: { Label("5-4-3-2-1 · Schritt für Schritt", systemImage: "hand.raised.fingers.spread.fill").font(.headline) }
                        NavigationLink { GroundingHistoryView() } label: { Label("Gespeicherte Übungen", systemImage: "clock.arrow.circlepath") }
                        NavigationLink { EmergencyPlanView() } label: { Label("Meinen Notfallplan öffnen", systemImage: "lifepreserver.fill") }
                        NavigationLink { ShowerDaysView() } label: { Label("Meine Duschtage", systemImage: "shower.fill") }
                    }
                }
                if store.data.copingMethods.isEmpty {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Dein Methodenkoffer ist bereit").font(.title3.bold())
                            Text("Lege eigene Methoden an oder passe ein Beispiel an. Beispiele werden erst gespeichert, wenn du sie bestätigst.").foregroundStyle(.secondary)
                            Button("ASMR-Beispiel anpassen", systemImage: "headphones") { draft = .asmrExample }.buttonStyle(.bordered)
                            Button("Gedankenstopp anpassen", systemImage: "hand.raised") { draft = .thoughtStopExample }.buttonStyle(.bordered)
                        }
                    }
                } else if methods.isEmpty { ContentUnavailableView.search(text: query.isEmpty ? "Diese Zuordnung" : query) }
                ForEach(methods) { method in
                    NavigationLink { MethodDetailView(methodID: method.id) } label: {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Label(method.title, systemImage: method.kind == .thoughtStop ? "hand.raised.fill" : "sparkles").font(.title3.bold()).foregroundStyle(.primary)
                                if !method.situation.isEmpty { Text(method.situation).font(.subheadline).foregroundStyle(.secondary) }
                                Text(method.stages.map(\.title).joined(separator: " · ")).font(.caption.bold()).foregroundStyle(Color.accentColor)
                                if !method.categories.isEmpty { Text(method.categories.map(\.title).joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) }
                                if method.favorite { Label("Favorit", systemImage: "star.fill").font(.caption).foregroundStyle(Color.accentColor) }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }.buttonStyle(.plain)
                }
            }
        }.navigationTitle("Meine Methoden").navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Methode, Situation oder Akku-Punkt")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Menu {
                    Button("Methode anlegen", systemImage: "plus") { draft = CopingMethod() }
                    Button("Gedankenstopp anlegen", systemImage: "hand.raised") { draft = CopingMethod(kind: .thoughtStop) }
                    Button("Mit KI entwerfen", systemImage: "sparkles") { showAI = true }
                } label: { Image(systemName: "plus.circle.fill") } }
            }
            .sheet(item: $draft) { MethodEditorView(method: $0) }
            .sheet(isPresented: $showAI) { SupportAIProposalView(purpose: .method, category: category ?? .sensory, stage: stage ?? .calm) }
    }
    private var methodMap: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tippe auf eine Phase, um passende Methoden zu sehen.").font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 135))], spacing: 10) {
                ForEach(MethodStage.allCases) { value in
                    let count = store.data.copingMethods.filter { $0.matches(category: category, stage: value, query: "", data: store.data) }.count
                    Button { stage = stage == value ? nil : value } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Image(systemName: value.symbol).font(.title2)
                            Text(value.title).font(.headline)
                            Text("\(count) Methoden").font(.caption)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
                            .background(Color.accentColor.opacity(stage == value ? 0.2 : 0.08), in: RoundedRectangle(cornerRadius: 18))
                    }.buttonStyle(.plain).foregroundStyle(Color.accentColor).accessibilityAddTraits(stage == value ? .isSelected : [])
                }
            }
        }
    }
}

struct MethodDetailView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let methodID: UUID
    @State private var editing: CopingMethod?
    @State private var deleting = false
    @State private var showAI = false
    private var method: CopingMethod? { store.data.copingMethods.first { $0.id == methodID } }
    var body: some View {
        TherapyScreen {
            if let method {
                VStack(alignment: .leading, spacing: 18) {
                    GlassCard(emphasized: true) {
                        VStack(alignment: .leading, spacing: 16) {
                            Label(method.title, systemImage: method.kind == .thoughtStop ? "hand.raised.fill" : "sparkles").font(.largeTitle.bold()).foregroundStyle(Color.accentColor)
                            if !method.situation.isEmpty { Text("Wenn …").font(.headline); Text(method.situation).font(.title3) }
                            Text(method.details).font(method.kind == .thoughtStop ? .title2.weight(.semibold) : .body).textSelection(.enabled)
                            ForEach(Array(method.steps.enumerated()), id: \.offset) { index, text in
                                HStack(alignment: .top, spacing: 12) { Text("\(index + 1)").font(.headline).foregroundStyle(Color.accentColor); Text(text).font(.title3) }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Passt für mich zu").font(.headline)
                            Text(method.categories.map(\.title).joined(separator: " · "))
                            Text(method.stages.map(\.title).joined(separator: " · ")).foregroundStyle(Color.accentColor)
                            ForEach(store.data.batteryPoints.filter { method.batteryPointIDs.contains($0.id) }) { Label($0.title, systemImage: $0.direction.symbol).font(.subheadline) }
                            Button(method.favorite ? "Favorit entfernen" : "Als Favorit merken", systemImage: method.favorite ? "star.fill" : "star") {
                                if let index = store.data.copingMethods.firstIndex(where: { $0.id == methodID }) { store.data.copingMethods[index].favorite.toggle() }
                            }
                            Button("In den Notfallplan aufnehmen", systemImage: "lifepreserver") {
                                if !store.data.emergencyPlan.methodIDs.contains(methodID) { store.data.emergencyPlan.methodIDs.append(methodID) }
                            }.disabled(store.data.emergencyPlan.methodIDs.contains(methodID))
                            Button("Mit KI weiterentwickeln", systemImage: "sparkles") { showAI = true }
                            Button("Bearbeiten", systemImage: "pencil") { editing = method }
                            Button("Löschen", systemImage: "trash", role: .destructive) { deleting = true }
                        }
                    }
                }
            } else { ContentUnavailableView("Methode nicht mehr vorhanden", systemImage: "sparkles") }
        }.navigationTitle(method?.title ?? "Methode").navigationBarTitleDisplayMode(.inline)
            .sheet(item: $editing) { MethodEditorView(method: $0) }
            .sheet(isPresented: $showAI) { SupportAIProposalView(purpose: method?.kind == .thoughtStop ? .thoughtStop : .method, originalMethod: method) }
            .alert("Methode löschen?", isPresented: $deleting) {
                Button("Abbrechen", role: .cancel) {}
                Button("Löschen", role: .destructive) {
                    var snapshot = store.data; snapshot.copingMethods.removeAll { $0.id == methodID }; snapshot.emergencyPlan.methodIDs.removeAll { $0 == methodID }; store.data = snapshot
                    if store.lastSaveError == nil { dismiss() }
                }
            }
    }
}

struct MethodEditorView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State var method: CopingMethod
    @State private var stepsText = ""
    @State private var initial: CopingMethod?
    @State private var confirmExit = false
    var body: some View {
        NavigationStack {
            Form {
                Section("Meine Methode") {
                    TextField("Name", text: $method.title)
                    Picker("Art", selection: $method.kind) { ForEach(CopingMethodKind.allCases) { Text($0.title).tag($0) } }
                    TextField("Welche Situation?", text: $method.situation, axis: .vertical).lineLimit(2...5)
                    TextField(method.kind == .thoughtStop ? "Mein persönlicher Stoppsatz" : "Was hilft mir?", text: $method.details, axis: .vertical).lineLimit(3...10)
                    Toggle("Favorit", isOn: $method.favorite)
                }
                Section("Schritte · eine Zeile pro Schritt") { TextEditor(text: $stepsText).frame(minHeight: 130) }
                Section("Wann passt sie?") {
                    ForEach(MethodStage.allCases) { value in Toggle(value.title, isOn: Binding(get: { method.stages.contains(value) }, set: { selected in method.stages.removeAll { $0 == value }; if selected { method.stages.append(value) } })) }
                }
                Section("Akkuthemen") {
                    ForEach(BatteryCategory.allCases) { value in Toggle(value.title, isOn: Binding(get: { method.categories.contains(value) }, set: { selected in method.categories.removeAll { $0 == value }; if selected { method.categories.append(value) } })) }
                }
                Section("Meine konkreten Akku-Punkte") {
                    if store.data.batteryPoints.isEmpty { Text("Sobald du Akku-Punkte erfasst hast, kannst du sie hier zuordnen.").foregroundStyle(.secondary) }
                    ForEach(store.data.batteryPoints.sorted { $0.date > $1.date }) { point in
                        Toggle(point.title + " · " + point.direction.title, isOn: Binding(get: { method.batteryPointIDs.contains(point.id) }, set: { selected in method.batteryPointIDs.removeAll { $0 == point.id }; if selected { method.batteryPointIDs.append(point.id) } }))
                    }
                }
                if let error = store.lastSaveError { Section { Text(error).foregroundStyle(.red) } }
            }.navigationTitle(method.kind.title + " gestalten").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { if changed { confirmExit = true } else { dismiss() } } }
                    ToolbarItem(placement: .confirmationAction) { Button("Speichern") {
                        var clean = method; clean.title = method.title.trimmingCharacters(in: .whitespacesAndNewlines); clean.steps = SupportText.steps(stepsText); clean.updatedAt = Date()
                        var snapshot = store.data; snapshot.copingMethods.removeAll { $0.id == clean.id }; snapshot.copingMethods.insert(clean, at: 0); store.data = snapshot
                        if store.lastSaveError == nil { dismiss() }
                    }.disabled(method.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || method.stages.isEmpty) }
                }
        }.onAppear { if initial == nil { initial = method; stepsText = method.steps.joined(separator: "\n") } }
            .interactiveDismissDisabled(changed)
            .alert("Änderungen verwerfen?", isPresented: $confirmExit) { Button("Weiter bearbeiten", role: .cancel) {}; Button("Verwerfen", role: .destructive) { dismiss() } }
    }
    private var changed: Bool { initial != nil && (method != initial || SupportText.steps(stepsText) != initial?.steps) }
}
enum SupportText {
    static func steps(_ text: String) -> [String] { text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } }
}

struct MethodsHomeCard: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        GlassCard(emphasized: true) {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Mein Methodenkoffer", icon: "sparkles", subtitle: "Passende Hilfe in deinem Tempo.")
                NavigationLink { MethodsHubView() } label: { Label("\(store.data.copingMethods.count) Methoden & Gedankenstopps", systemImage: "square.grid.2x2") }
                NavigationLink { GroundingExerciseView() } label: { Label("5-4-3-2-1 starten", systemImage: "hand.raised.fingers.spread") }
                NavigationLink { EmergencyPlanView() } label: { Label("Notfallplan öffnen", systemImage: "lifepreserver.fill").font(.headline) }
            }
        }
    }
}
