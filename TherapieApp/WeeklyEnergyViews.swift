import SwiftUI
import Charts

struct WeeklyEnergyCard: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        GlassCard(emphasized: true) {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Deine Energie seit der letzten Therapie", icon: "battery.100percent",
                              subtitle: "Was hat dir Kraft gegeben? Was hat sie gekostet?")
                Button { store.openEnergyReview = true } label: { Label("Wochenenergie visuell eintragen", systemImage: "plus.circle.fill").frame(maxWidth: .infinity).fixedSize(horizontal: false, vertical: true) }.buttonStyle(.borderedProminent)
                Text("Dein Therapietag: " + TherapyDateHelper.weekdayName(store.data.schedule.weekday)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct EnergyLevelButtons: View {
    @Binding var value: Int
    var title = "Wie voll war dein Akku im Durchschnitt?"
    var color: Color = .teal
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.subheadline.weight(.semibold))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 48))], spacing: 8) {
                ForEach(1...5, id: \.self) { number in
                    Button { value = number; TherapyEffects.shared.light() } label: {
                        VStack(spacing: 5) { Image(systemName: number <= 2 ? "battery.25percent" : number == 3 ? "battery.50percent" : "battery.100percent"); Text("\(number)/5").font(.caption.bold()) }
                            .frame(maxWidth: .infinity, minHeight: 48).padding(6)
                            .background(value == number ? color.opacity(0.2) : Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                            .overlay { RoundedRectangle(cornerRadius: 12).stroke(value == number ? color : .clear, lineWidth: 2) }
                    }.buttonStyle(.plain).accessibilityLabel("\(number) von 5").accessibilityAddTraits(value == number ? .isSelected : [])
                }
            }
            Text(value <= 2 ? "Wenig Energie" : value == 3 ? "Gemischt" : "Viel Energie").font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct EnergyFactorDraft: Identifiable {
    let id = UUID()
    var factor: WeeklyEnergyFactor
    var gives: Bool
}

struct WeeklyEnergyEditorView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var review: WeeklyEnergyReview
    @State private var initial: WeeklyEnergyReview
    @State private var loaded = false
    @State private var factorDraft: EnergyFactorDraft?
    @State private var deleting: EnergyFactorDraft?
    @State private var confirmDelete = false
    @State private var discard = false
    @State private var replace = false
    private let provided: Bool
    init(review: WeeklyEnergyReview? = nil) {
        let entry = review ?? WeeklyEnergyReview()
        provided = review != nil; _review = State(initialValue: entry); _initial = State(initialValue: entry)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Rückblick bis", selection: $review.periodEnd, in: ...Date(), displayedComponents: .date)
                    Text("\(review.periodStart.formatted(date: .abbreviated, time: .omitted)) bis \(Calendar.therapyCalendar.date(byAdding: .day, value: -1, to: review.periodEnd)!.formatted(date: .abbreviated, time: .omitted))")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text("Die sieben abgeschlossenen Tage vor deinem gewählten Therapietag.").font(.caption).foregroundStyle(.secondary)
                    EnergyLevelButtons(value: $review.energy)
                } header: { Text("Meine Woche") }
                factors(gives: true)
                factors(gives: false)
                Section("Schon eingetragen?") {
                    Button("Akku-Punkte aus diesem Zeitraum übernehmen", systemImage: "arrow.down.doc") { reusePoints() }
                    Text("Übernimmt deine einzelnen Punkte als Wochenbeobachtungen. Die Originaleinträge bleiben erhalten.").font(.caption).foregroundStyle(.secondary)
                }
                if !review.gives.isEmpty || !review.takes.isEmpty {
                    Section("Mein Wochenbild") {
                        EnergyBalanceChart(review: review)
                    }
                }
                Section("In die Therapie mitnehmen") {
                    TextField("Was ist mir aufgefallen?", text: $review.note, axis: .vertical).lineLimit(3...8)
                    TextField("Eine Frage für meine Therapeutin / meinen Therapeuten", text: $review.therapyQuestion, axis: .vertical).lineLimit(2...6)
                    TextField("Mein nächster kleiner Schritt", text: $review.nextStep, axis: .vertical).lineLimit(2...6)
                }
            }
            .navigationTitle("Wochenenergie").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { if review != initial { discard = true } else { dismiss() } } }
                ToolbarItem(placement: .confirmationAction) { Button("Speichern") {
                    if store.data.weeklyEnergyReviews.contains(where: { $0.id != review.id && Calendar.therapyCalendar.isDate($0.periodEnd, inSameDayAs: review.periodEnd) }) { replace = true } else { save() }
                } }
            }
            .interactiveDismissDisabled(review != initial)
            .safeAreaInset(edge: .bottom) { WellnessSaveErrorView() }
            .onAppear {
                guard !loaded else { return }; loaded = true
                if !provided {
                    let date = TherapyReviewPeriod.latestTherapyDay(schedule: store.data.schedule)
                    review = store.data.weeklyEnergyReviews.first(where: { Calendar.therapyCalendar.isDate($0.periodEnd, inSameDayAs: date) }) ?? WeeklyEnergyReview(periodEnd: date)
                    initial = review
                }
            }
            .sheet(item: $factorDraft) { draft in
                WeeklyEnergyFactorEditor(factor: draft.factor, gives: draft.gives) { value in
                    if draft.gives {
                        review.gives.removeAll { $0.id == value.id }; review.gives.append(value)
                    } else { review.takes.removeAll { $0.id == value.id }; review.takes.append(value) }
                }
            }
            .alert("Punkt entfernen?", isPresented: $confirmDelete) {
                Button("Abbrechen", role: .cancel) {}
                Button("Entfernen", role: .destructive) {
                    if let deleting {
                        if deleting.gives { review.gives.removeAll { $0.id == deleting.factor.id } } else { review.takes.removeAll { $0.id == deleting.factor.id } }
                        TherapyEffects.shared.light()
                    }
                }
            } message: { Text("Dieser Punkt wird aus dem Wochenrückblick entfernt. Gespeichert wird die Änderung erst mit Speichern.") }
            .alert("Änderungen verwerfen?", isPresented: $discard) {
                Button("Weiter bearbeiten", role: .cancel) {}
                Button("Als Entwurf speichern") { store.saveEditorDraft(review, id: review.id, kind: "weeklyEnergy", title: "Wochenenergie"); if store.lastSaveError == nil { dismiss() } }
                Button("Verwerfen", role: .destructive) { store.removeEditorDraft(review.id); if store.lastSaveError == nil { dismiss() } }
            }
            .alert("Vorhandenen Rückblick ersetzen?", isPresented: $replace) {
                Button("Abbrechen", role: .cancel) {}
                Button("Ersetzen", role: .destructive) { save() }
            } message: { Text("Für diesen Therapietag ist bereits ein Energie-Rückblick gespeichert.") }
        }
    }
    private func factors(gives: Bool) -> some View {
        Section {
            let values = gives ? review.gives : review.takes
            ForEach(values) { factor in
                VStack(alignment: .leading, spacing: 8) {
                    Label(factor.title, systemImage: gives ? "plus.circle.fill" : "minus.circle.fill").foregroundStyle(gives ? .teal : .orange).font(.headline)
                    Text("Einfluss: \(factor.impact)/5 · \(factor.category.title)").font(.caption).foregroundStyle(.secondary)
                    if !factor.note.isEmpty { Text(factor.note).font(.subheadline) }
                    ResponsiveButtonRow {
                        Button("Bearbeiten", systemImage: "pencil") { factorDraft = EnergyFactorDraft(factor: factor, gives: gives) }
                        Button("Entfernen", role: .destructive) { deleting = EnergyFactorDraft(factor: factor, gives: gives); confirmDelete = true }
                    }
                }.padding(.vertical, 4)
            }
            Button(gives ? "Energie-Geber hinzufügen" : "Energie-Nehmer hinzufügen", systemImage: "plus") { factorDraft = EnergyFactorDraft(factor: WeeklyEnergyFactor(), gives: gives) }
            ScrollView(.horizontal) {
                HStack {
                    ForEach(gives ? ["Freunde", "Ruhe", "Musik", "Spaziergang"] : ["Viele Reize", "Wenig Schlaf", "Viele Termine", "Medikamente"], id: \.self) { title in
                        Button(title) { factorDraft = EnergyFactorDraft(factor: WeeklyEnergyFactor(title: title), gives: gives) }.buttonStyle(.bordered)
                    }
                }
            }.scrollIndicators(.hidden)
        } header: { Text(gives ? "Das hat mir Energie gegeben" : "Das hat mich Energie gekostet") } footer: { Text("Jeder Punkt ist deine eigene Beobachtung. Du kannst Titel, Stärke, Kategorie und Notiz frei anpassen.") }
    }
    private func reusePoints() {
        let end = Calendar.therapyCalendar.startOfDay(for: review.periodEnd)
        let start = review.periodStart
        let known = Set((review.gives + review.takes).map(\.id))
        for point in store.data.batteryPoints where point.hasConfirmedImpact && point.date >= start && point.date < end && !known.contains(point.id) {
            let factor = WeeklyEnergyFactor(id: point.id, title: point.title, impact: point.impact, category: point.category, note: point.note)
            if point.direction == .gives { review.gives.append(factor) } else { review.takes.append(factor) }
        }
        TherapyEffects.shared.light()
    }
    private func save() { store.saveEnergyReview(review); if store.lastSaveError == nil { store.removeEditorDraft(review.id); if store.lastSaveError == nil { dismiss() } } }
}

private struct WeeklyEnergyFactorEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var factor: WeeklyEnergyFactor
    @State private var discard = false
    private let initial: WeeklyEnergyFactor
    let gives: Bool
    let onSave: (WeeklyEnergyFactor) -> Void
    init(factor: WeeklyEnergyFactor, gives: Bool, onSave: @escaping (WeeklyEnergyFactor) -> Void) { initial = factor; _factor = State(initialValue: factor); self.gives = gives; self.onSave = onSave }
    var body: some View {
        NavigationStack {
            Form {
                TextField("Was genau?", text: $factor.title, axis: .vertical).lineLimit(1...4)
                EnergyLevelButtons(value: $factor.impact, title: "Wie stark war der Einfluss?", color: gives ? .teal : .orange)
                Picker("Bereich", selection: $factor.category) { ForEach(BatteryCategory.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) } }
                TextField("Was war daran hilfreich oder anstrengend?", text: $factor.note, axis: .vertical).lineLimit(3...8)
            }.buttonStyle(.borderless).navigationTitle(gives ? "Gibt Energie" : "Nimmt Energie")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { if factor != initial { discard = true } else { dismiss() } } }
                    ToolbarItem(placement: .confirmationAction) { Button("Übernehmen") { factor.title = factor.title.trimmingCharacters(in: .whitespacesAndNewlines); onSave(factor); TherapyEffects.shared.light(); dismiss() }.disabled(factor.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                }
                .interactiveDismissDisabled(factor != initial)
                .alert("Änderungen verwerfen?", isPresented: $discard) { Button("Weiter bearbeiten", role: .cancel) {}; Button("Verwerfen", role: .destructive) { dismiss() } }
        }
    }
}

struct EnergyBalanceChart: View {
    let review: WeeklyEnergyReview
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Chart {
                BarMark(x: .value("Richtung", "Gegeben"), y: .value("Einfluss", review.gives.reduce(0) { $0 + $1.impact })).foregroundStyle(.teal)
                BarMark(x: .value("Richtung", "Gekostet"), y: .value("Einfluss", review.takes.reduce(0) { $0 + $1.impact })).foregroundStyle(.orange)
            }.frame(height: 160).accessibilityLabel("Einfluss von Energie-Gebern \(review.gives.reduce(0) { $0 + $1.impact }), von Energie-Nehmern \(review.takes.reduce(0) { $0 + $1.impact })")
            Text("Die Balken addieren deine persönlichen Einflusswerte. Dein Akku-Wert \(review.energy)/5 ist deine eigene Einschätzung.").font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct WeeklyEnergyHistory: View {
    @EnvironmentObject private var store: AppStore
    @State private var editing: WeeklyEnergyReview?
    @State private var deleting: WeeklyEnergyReview?
    @State private var confirmDelete = false
    var body: some View {
        VStack(spacing: 12) {
            ForEach(store.data.weeklyEnergyReviews.sorted { $0.periodEnd > $1.periodEnd }) { review in
                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Wochenenergie bis " + review.periodEnd.formatted(date: .abbreviated, time: .omitted)).font(.headline)
                        Text("Akku \(review.energy)/5 · \(review.gives.count) Geber · \(review.takes.count) Nehmer").font(.subheadline)
                        EnergyBalanceChart(review: review)
                        if !review.therapyQuestion.isEmpty { Label(review.therapyQuestion, systemImage: "bubble.left").font(.subheadline) }
                        ResponsiveButtonRow {
                            Button("Bearbeiten", systemImage: "pencil") { editing = review }
                            Button("Löschen", role: .destructive) { deleting = review; confirmDelete = true }
                        }
                    }
                }
            }
        }
        .sheet(item: $editing) { WeeklyEnergyEditorView(review: $0) }
        .alert("Wochenenergie löschen?", isPresented: $confirmDelete) {
            Button("Abbrechen", role: .cancel) {}
            Button("Löschen", role: .destructive) { if let deleting { store.data.weeklyEnergyReviews.removeAll { $0.id == deleting.id } } }
        } message: { Text("Dieser Rückblick und seine Wochenpunkte werden gelöscht. Einzelne Akku-Punkte bleiben erhalten.") }
    }
}
