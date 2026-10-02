import SwiftUI
import QuickLook
import PhotosUI
import UIKit

struct TherapyEditorSheet<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    @State private var confirmDiscard = false
    let title: String
    let dirty: Bool
    let canSave: Bool
    let save: () -> Void
    var draftID: UUID?
    var saveDraft: (() -> Void)?
    let content: Content
    init(title: String, dirty: Bool, canSave: Bool = true, draftID: UUID? = nil, saveDraft: (() -> Void)? = nil, save: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.title = title; self.dirty = dirty; self.canSave = canSave; self.save = save; self.draftID = draftID; self.saveDraft = saveDraft; self.content = content()
    }
    var body: some View {
        NavigationStack {
            Form { content }
                // Form's automatic row action must never activate sibling buttons together.
                .buttonStyle(.borderless)
                .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Abbrechen") { if dirty { confirmDiscard = true } else { dismiss() } }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Speichern") { save(); if store.lastSaveError == nil { if let draftID { store.removeEditorDraft(draftID) }; if store.lastSaveError == nil { dismiss() } } }.disabled(!canSave)
                    }
                }
                .safeAreaInset(edge: .bottom) { WellnessSaveErrorView() }
                .interactiveDismissDisabled(dirty)
                .alert("Änderungen verwerfen?", isPresented: $confirmDiscard) {
                    Button("Weiter bearbeiten", role: .cancel) {}
                    if let saveDraft { Button("Als Entwurf speichern") { saveDraft(); if store.lastSaveError == nil { dismiss() } } }
                    Button("Verwerfen", role: .destructive) { if let draftID { store.removeEditorDraft(draftID) }; if store.lastSaveError == nil { dismiss() } }
                }
        }
    }
}

struct TherapyLinkFields: View {
    @EnvironmentObject private var store: AppStore
    @Binding var folder: UUID?
    @Binding var topic: UUID?
    var body: some View {
        Picker("Ordner", selection: $folder) {
            Text("Ohne Ordner").tag(Optional<UUID>.none)
            ForEach(store.data.therapyFolders) {
                Text(TherapyHierarchy.path(for: $0.id, folders: store.data.therapyFolders)).tag(Optional($0.id))
            }
        }
        Picker("Therapiethema", selection: $topic) {
            Text("Ohne Zuordnung").tag(Optional<UUID>.none)
            ForEach(store.data.therapyTopics) { Text($0.title).tag(Optional($0.id)) }
        }
    }
}

struct FolderEditorView: View {
    @EnvironmentObject private var store: AppStore
    @State private var folder: TherapyFolder
    private let initial: TherapyFolder
    init(folder: TherapyFolder) { initial = folder; _folder = State(initialValue: folder) }
    private var unavailable: Set<UUID> { TherapyHierarchy.descendants(of: folder.id, folders: store.data.therapyFolders).union([folder.id]) }
    var body: some View {
        TherapyEditorSheet(title: "Themenordner", dirty: folder != initial, canSave: !folder.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, draftID: folder.id, saveDraft: { store.saveEditorDraft(folder, id: folder.id, kind: "folder", title: folder.title) }, save: { store.saveFolder(folder) }) {
            Section("Dein Ordner") {
                TextField("Zum Beispiel: Alltag & Arbeit", text: $folder.title)
                Picker("Übergeordneter Ordner", selection: $folder.parentID) {
                    Text("Hauptebene").tag(Optional<UUID>.none)
                    ForEach(store.data.therapyFolders.filter { !unavailable.contains($0.id) }) {
                        Text(TherapyHierarchy.path(for: $0.id, folders: store.data.therapyFolders)).tag(Optional($0.id))
                    }
                }
                Picker("Symbol", selection: $folder.symbol) {
                    ForEach(["folder", "heart", "leaf", "star", "briefcase", "person.2", "ear", "house", "bubble.left", "brain.head.profile"], id: \.self) { symbol in
                        Image(systemName: symbol).tag(symbol)
                    }
                }
            }
        }
    }
}

struct TopicEditorView: View {
    @EnvironmentObject private var store: AppStore
    @State private var topic: TherapyTopic
    private let initial: TherapyTopic
    init(topic: TherapyTopic) { initial = topic; _topic = State(initialValue: topic) }
    var body: some View {
        TherapyEditorSheet(title: "Therapiethema", dirty: topic != initial, canSave: !topic.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, draftID: topic.id, saveDraft: { store.saveEditorDraft(topic, id: topic.id, kind: "topic", title: topic.title) }, save: { store.saveTopic(topic) }) {
            Section("Thema & Stand") {
                TextField("Worum geht es?", text: $topic.title, axis: .vertical).lineLimit(2...4)
                Picker("Bereich", selection: $topic.category) { ForEach(TherapyCategory.allCases) { Label($0.rawValue, systemImage: $0.symbol).tag($0) } }
                Picker("Status", selection: $topic.status) { ForEach(TherapyWorkStatus.allCases) { Text($0.rawValue).tag($0) } }
                Toggle("Aktuelles Thema für meine Stunde", isOn: $topic.isCurrent).disabled(topic.status == .completed)
                Picker("Priorität", selection: $topic.priority) { Text("Niedrig").tag(1); Text("Normal").tag(2); Text("Wichtig").tag(3) }
                Picker("Ordner", selection: $topic.folderID) {
                    Text("Ohne Ordner").tag(Optional<UUID>.none)
                    ForEach(store.data.therapyFolders) { Text(TherapyHierarchy.path(for: $0.id, folders: store.data.therapyFolders)).tag(Optional($0.id)) }
                }
            }
            Section("Deine Perspektive") {
                field("Was ist mir daran wichtig?", $topic.description)
                field("Was hilft mir bereits?", $topic.helps)
                field("Was macht es schwierig?", $topic.barriers)
                field("Was möchten wir als Nächstes besprechen?", $topic.nextStep)
            }
        }
    }
    private func field(_ label: String, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading) { Text(label).font(.caption).foregroundStyle(.secondary); TextField("Freiwillig", text: text, axis: .vertical).lineLimit(2...6) }
    }
}

struct GoalEditorView: View {
    @EnvironmentObject private var store: AppStore
    @State private var goal: TherapyGoal
    private let initial: TherapyGoal
    init(goal: TherapyGoal) { initial = goal; _goal = State(initialValue: goal) }
    var body: some View {
        TherapyEditorSheet(title: "Mein Therapieziel", dirty: goal != initial, canSave: !goal.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, draftID: goal.id, saveDraft: { store.saveEditorDraft(goal, id: goal.id, kind: "goal", title: goal.title) }, save: { store.saveGoal(goal) }) {
            Section("Ein Ziel, das zu mir passt") {
                TextField("Was möchte ich erreichen?", text: $goal.title, axis: .vertical).lineLimit(2...5)
                Picker("Thema", selection: $goal.topicID) {
                    Text("Ohne Zuordnung").tag(Optional<UUID>.none)
                    ForEach(store.data.therapyTopics) { Text($0.title).tag(Optional($0.id)) }
                }
                Picker("Priorität", selection: Binding(get: { goal.priority ?? "normal" }, set: { goal.priority = $0 })) { Text("Ruhig").tag("low"); Text("Normal").tag("normal"); Text("Dringend").tag("high") }
                Picker("Status", selection: $goal.status) { ForEach(TherapyWorkStatus.allCases) { Text($0.rawValue).tag($0) } }
                Stepper("Fortschritt: \(goal.progress) %", value: $goal.progress, in: 0...100, step: 5)
                ProgressView(value: Double(goal.progress), total: 100)
            }
            Section("Kleine, konkrete Schritte") {
                field("Warum ist mir das wichtig?", $goal.why)
                field("Woran merke ich einen Fortschritt?", $goal.measure)
                field("Mein kleinster nächster Schritt", $goal.smallStep)
                field("Diese Unterstützung brauche ich", $goal.support)
                Toggle("Wunschtermin festhalten", isOn: Binding(get: { goal.dueDate != nil }, set: { goal.dueDate = $0 ? Date().addingTimeInterval(7 * 86400) : nil }))
                if goal.dueDate != nil { DatePicker("Wunschtermin", selection: Binding(get: { goal.dueDate ?? Date() }, set: { goal.dueDate = $0 }), displayedComponents: .date) }
            }
        }
    }
    private func field(_ title: String, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading) { Text(title).font(.caption).foregroundStyle(.secondary); TextField("Freiwillig", text: text, axis: .vertical).lineLimit(2...6) }
    }
}

struct TherapyNoteEditorView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showAI = false
    @State private var note: TherapyNote
    @State private var tags: String
    @State private var initial: TherapyNote
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var attachment: NoteAttachmentDestination?
    @State private var importing = false
    @State private var attachmentError: String?
    init(note: TherapyNote = TherapyNote(title: "", text: "", tags: [])) {
        _initial = State(initialValue: note); _note = State(initialValue: note); _tags = State(initialValue: note.tags.joined(separator: ", "))
    }
    private var canSave: Bool { !note.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !note.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !(note.mediaIDs ?? []).isEmpty }
    var body: some View {
        TherapyEditorSheet(title: note.author == NoteAuthor.therapist.rawValue ? "Beitrag für die Therapie" : "Therapie-Notiz", dirty: note != initial || tags != initial.tags.joined(separator: ", "), canSave: canSave && !importing, draftID: note.id, saveDraft: {
            var clean = note; clean.tags = AppHashtags.clean(tags.split(separator: ",").map(String.init), known: AppHashtags.catalog(store.data))
            store.saveEditorDraft(clean, id: clean.id, kind: "note", title: clean.title)
        }, save: {
            var clean = note
            if clean.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { clean.title = "Notiz" }
            clean.tags = AppHashtags.clean(tags.split(separator: ",").map(String.init), known: AppHashtags.catalog(store.data))
            store.saveNote(clean)
        }) {
            Section("Festhalten") {
                TherapyInputField(title: "Titel", prompt: "Deine Notiz benennen", multiline: false, text: $note.title)
                VStack(alignment: .leading, spacing: 10) {
                    Label("Deine Gedanken", systemImage: "text.alignleft").font(.subheadline).foregroundStyle(.secondary)
                    TextEditor(text: $note.text).frame(minHeight: 220).scrollContentBackground(.hidden)
                        .padding(10).background(Color.accentColor.opacity(0.04), in: RoundedRectangle(cornerRadius: 16)).accessibilityLabel("Notiztext")
                    HStack {
                        Button("Liste", systemImage: "list.bullet") { note.text += (note.text.isEmpty ? "" : "\n") + "• " }
                        Button("Checkliste", systemImage: "checklist") { note.text += (note.text.isEmpty ? "" : "\n") + "☐ " }
                    }.buttonStyle(.bordered)
                }
                if store.data.aiSettings.enabled { Button("Mit KI schreiben & sortieren", systemImage: "sparkles") { dismissKeyboard(); showAI = true }.accessibilityIdentifier("note.ai") }
                Toggle("Wichtig · oben anheften", isOn: Binding(get: { note.isImportant ?? false }, set: { note.isImportant = $0 }))
                Picker("Verfasst von", selection: Binding(get: { note.author ?? NoteAuthor.me.rawValue }, set: { note.author = $0 })) {
                    ForEach(NoteAuthor.allCases) { Text($0.rawValue).tag($0.rawValue) }
                }
                DatePicker("Datum", selection: $note.createdAt, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
            }
            NoteAttachmentsSection(note: $note, photo: $selectedPhoto, importing: importing, error: attachmentError, record: { dismissKeyboard(); attachment = .record }, choose: { dismissKeyboard(); attachment = .archive }, open: { dismissKeyboard(); attachment = .media($0.id) })
            Section("Einordnen") {
                TherapyLinkFields(folder: $note.folderID, topic: $note.topicID)
                Picker("Bereich", selection: Binding(get: { note.category ?? TherapyCategory.other.rawValue }, set: { note.category = $0 })) {
                    ForEach(TherapyCategory.allCases) { Text($0.rawValue).tag($0.rawValue) }
                }
                TextField("Hashtags, mit Komma trennen", text: $tags)
                HashtagChips(tags: AppHashtags.clean(tags.split(separator: ",").map(String.init)))
                ScrollView(.horizontal) { HStack { ForEach(AppHashtags.catalog(store.data).prefix(20), id: \.self) { tag in Button("#" + tag) { let all = AppHashtags.clean(tags.split(separator: ",").map(String.init) + [tag]); tags = all.joined(separator: ", ") }.buttonStyle(.bordered) } } }
            }
        }
        .accessibilityIdentifier("note.editor")
        .presentationDetents([.large])
        .sheet(isPresented: $showAI) { AIBuddyEntryView(note: note, onNoteProposal: { proposal in note = proposal; tags = proposal.tags.joined(separator: ", "); showAI = false }) }
        .sheet(item: $attachment) { route in
            switch route {
            case .record: AudioRecordingView(onSaved: link)
            case .archive: NoteArchivePicker(choose: link)
            case .media(let id): TherapyMediaDetailView(itemID: id)
            }
        }
        .onChange(of: selectedPhoto) { _, selected in
            guard let selected else { return }; importing = true
            Task { @MainActor in
                defer { importing = false; selectedPhoto = nil }
                do {
                    guard let bytes = try await selected.loadTransferable(type: Data.self), let image = UIImage(data: bytes), let jpeg = image.jpegData(compressionQuality: 0.85) else { throw CocoaError(.fileReadCorruptFile) }
                    try store.importPhoto(bytes: jpeg, fileExtension: "jpg", title: note.title.isEmpty ? "Notizfoto" : note.title, note: "", tags: [], location: nil)
                    if let failure = store.lastSaveError { attachmentError = failure; return }
                    if let item = store.data.media.first { link(item.id) }; attachmentError = nil
                } catch { attachmentError = error.localizedDescription }
            }
        }
    }
    private func link(_ id: UUID) { if !(note.mediaIDs ?? []).contains(id) { note.mediaIDs = (note.mediaIDs ?? []) + [id] } }
    private func dismissKeyboard() { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
}

struct TherapyMediaEditorView: View {
    @EnvironmentObject private var store: AppStore
    @State private var item: MediaItem
    @State private var tags: String
    private let initial: MediaItem
    init(item: MediaItem) { initial = item; _item = State(initialValue: item); _tags = State(initialValue: item.tags.joined(separator: ", ")) }
    var body: some View {
        TherapyEditorSheet(title: "Therapiematerial", dirty: item != initial || tags != initial.tags.joined(separator: ", "), canSave: !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, draftID: item.id, saveDraft: { var clean = item; clean.tags = AppHashtags.clean(tags.split(separator: ",").map(String.init)); store.saveEditorDraft(clean, id: clean.id, kind: "media", title: clean.title) }, save: {
            var clean = item; clean.tags = tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }; store.saveMediaDetails(clean)
        }) {
            Section("Material & Informationen") {
                if item.attachmentOmitted == true {
                    Label("Die Datei wurde beim Export ausgelassen. Ihre Informationen bleiben bearbeitbar.", systemImage: "doc.badge.ellipsis").font(.footnote).foregroundStyle(.secondary)
                }
                TextField("Titel", text: $item.title)
                TextField("Beschreibung, Verwendung oder Hinweis", text: $item.note, axis: .vertical).lineLimit(3...10)
                TextField("Quelle / erhalten von", text: Binding(get: { item.source ?? "" }, set: { item.source = $0 }))
                Picker("Materialart", selection: Binding(get: { item.category ?? MaterialCategory.other.rawValue }, set: { item.category = $0 })) {
                    ForEach(MaterialCategory.allCases) { Text($0.rawValue).tag($0.rawValue) }
                }
                TherapyLinkFields(folder: $item.folderID, topic: $item.topicID)
                TextField("Tags, mit Komma trennen", text: $tags)
            }
        }
    }
}

struct TherapyHubView: View {
    @State private var section = 0
    var body: some View {
        NavigationStack {
            TherapyScreen {
                VStack(spacing: 16) {
                    GlassCard(emphasized: true) {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "Dein Therapieraum", icon: "leaf", subtitle: "Themen, Ziele und Materialien in deinem Tempo.")
                            NavigationLink { SessionConductorView() } label: { Label("Therapiestunde begleiten", systemImage: "timer").font(.headline) }
                            NavigationLink { TherapyCalendarView() } label: { Label("Kalender & Termine", systemImage: "calendar") }
                            NavigationLink { TasksView() } label: { Label("Wochenaufgaben", systemImage: "checklist") }
                        }
                    }
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            sectionButton("Themen", "folder", 0)
                            sectionButton("Ziele", "scope", 1)
                            sectionButton("Materialien", "doc.on.doc", 2)
                            sectionButton("Therapeutin", "person.text.rectangle", 3)
                            sectionButton("Wichtige Notizen", "pin", 4)
                        }
                    }.scrollIndicators(.hidden)
                    switch section {
                    case 0: TherapyFolderContentView(folderID: nil)
                    case 1: TherapyGoalsView()
                    case 2: TherapyMaterialsView()
                    case 3: TherapistAreaView()
                    default: TherapyNotesCollectionView(importantOnly: true)
                    }
                }
            }
            .navigationTitle("Therapie")
        }
    }
    private func sectionButton(_ title: String, _ symbol: String, _ value: Int) -> some View {
        Button {
            TherapyEffects.shared.light()
            withAnimation(.easeInOut(duration: 0.16)) { section = value }
        } label: {
            Label(title, systemImage: symbol).font(.subheadline.bold()).padding(.horizontal, 13).padding(.vertical, 12)
                .background(section == value ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.08), in: Capsule())
        }.buttonStyle(.plain).accessibilityAddTraits(section == value ? .isSelected : [])
    }
}

struct TherapyFolderContentView: View {
    @EnvironmentObject private var store: AppStore
    let folderID: UUID?
    @State private var folderDraft: TherapyFolder?
    @State private var topicDraft: TherapyTopic?
    @State private var topicDetail: TherapyTopic?
    @State private var query = ""
    @State private var status: TherapyWorkStatus?
    @State private var currentOnly = false
    @State private var deletingFolder: TherapyFolder?
    @State private var deletingTopic: TherapyTopic?
    @State private var confirmDelete = false
    private var folders: [TherapyFolder] { store.data.therapyFolders.filter { $0.parentID == folderID }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending } }
    private var topics: [TherapyTopic] {
        store.data.therapyTopics.filter {
            ($0.folderID == folderID || (folderID == nil && currentOnly)) && (status == nil || status == $0.status) && (!currentOnly || $0.isCurrent)
                && (query.isEmpty || [$0.title, $0.description, $0.nextStep, $0.category.rawValue].contains { $0.localizedCaseInsensitiveContains(query) })
        }.sorted { $0.isCurrent == $1.isCurrent ? $0.priority > $1.priority : $0.isCurrent }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(folderID == nil ? "Themen & Ordner" : TherapyHierarchy.path(for: folderID, folders: store.data.therapyFolders)).font(.headline)
                Spacer()
                Menu {
                    Button("Ordner anlegen", systemImage: "folder.badge.plus") { folderDraft = TherapyFolder(parentID: folderID) }
                    Button("Thema anlegen", systemImage: "plus.circle") { topicDraft = TherapyTopic(folderID: folderID) }
                } label: { Image(systemName: "plus.circle.fill").font(.title2).frame(width: 44, height: 44) }
            }
            ForEach(folders) { folder in
                GlassCard {
                    HStack {
                        NavigationLink {
                            TherapyScreen { TherapyFolderContentView(folderID: folder.id) }.buttonStyle(.borderless).navigationTitle(folder.title)
                        } label: { Label(folder.title, systemImage: folder.symbol).font(.headline) }
                        Spacer()
                        Menu {
                            Button("Ordner bearbeiten", systemImage: "pencil") { folderDraft = folder }
                            Button("Ordner löschen", systemImage: "trash", role: .destructive) { deletingFolder = folder; deletingTopic = nil; confirmDelete = true }
                        } label: { Image(systemName: "ellipsis.circle").frame(width: 44, height: 44) }
                    }
                }
            }
            TextField("Themen hier suchen", text: $query).textFieldStyle(.roundedBorder)
            HStack {
                Toggle("Aktuelle Themen", isOn: $currentOnly).font(.subheadline)
                Picker("Status", selection: $status) {
                    Text("Alle").tag(Optional<TherapyWorkStatus>.none)
                    ForEach(TherapyWorkStatus.allCases) { Text($0.rawValue).tag(Optional($0)) }
                }.labelsHidden()
            }
            if topics.isEmpty {
                GlassCard {
                    VStack(spacing: 12) {
                        ContentUnavailableView("Platz für deine Themen", systemImage: "folder", description: Text("Lege ein Thema an oder sortiere es über Bearbeiten in diesen Ordner ein."))
                        Button("Mein erstes Thema", systemImage: "plus") { topicDraft = TherapyTopic(folderID: folderID) }
                    }
                }
            }
            ForEach(topics) { topic in
                GlassCard(emphasized: topic.isCurrent) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top) {
                            Label(topic.title, systemImage: topic.category.symbol).font(.headline)
                            Spacer()
                            Menu {
                                Button("Bearbeiten", systemImage: "pencil") { topicDraft = topic }
                                Button(topic.isCurrent ? "Aus aktuellen Themen nehmen" : "Als aktuelles Thema wählen", systemImage: "pin") {
                                    var copy = topic; copy.isCurrent.toggle(); if copy.isCurrent && copy.status == .completed { copy.status = .active }; store.saveTopic(copy)
                                }
                                Button(topic.status == .completed ? "Wieder aufnehmen" : "Abschließen", systemImage: "checkmark.circle") {
                                    var copy = topic; copy.status = topic.status == .completed ? .active : .completed; store.saveTopic(copy)
                                }
                                Button("Löschen", systemImage: "trash", role: .destructive) { deletingTopic = topic; deletingFolder = nil; confirmDelete = true }
                            } label: { Image(systemName: "ellipsis.circle").frame(width: 44, height: 44) }
                        }
                        Label(topic.status.rawValue, systemImage: topic.status.symbol).font(.caption.bold()).foregroundStyle(.secondary)
                        if topic.isCurrent { Label("Für die nächste Stunde", systemImage: "pin.fill").font(.caption.bold()).foregroundStyle(Color.accentColor) }
                        if !topic.description.isEmpty { Text(topic.description).font(.subheadline).lineLimit(3) }
                        if !topic.nextStep.isEmpty { Label(topic.nextStep, systemImage: "arrow.right.circle").font(.subheadline) }
                        Button("Thema öffnen") { topicDetail = topic }.font(.subheadline.bold())
                    }
                }
            }
            if folderID != nil {
                TherapyNotesCollectionView(folderID: folderID)
                TherapyMaterialsView(folderID: folderID)
            }
            DisclosureGroup("Ideen für eigene Themen") {
                ForEach(TherapyCategory.allCases) { category in
                    Button { topicDraft = TherapyTopic(title: category.rawValue, folderID: folderID, category: category) } label: { Label(category.rawValue, systemImage: category.symbol) }.padding(.vertical, 4)
                }
            }.font(.subheadline)
        }
        .sheet(item: $folderDraft) { FolderEditorView(folder: $0) }
        .sheet(item: $topicDraft) { TopicEditorView(topic: $0) }
        .sheet(item: $topicDetail) { TherapyTopicDetailView(topicID: $0.id) }
        .alert(deletingFolder != nil ? "Ordner löschen?" : "Thema löschen?", isPresented: $confirmDelete) {
            Button("Abbrechen", role: .cancel) {}
            Button("Löschen", role: .destructive) {
                var snapshot = store.data
                if let folder = deletingFolder { TherapyHierarchy.removeFolder(folder.id, data: &snapshot) }
                if let topic = deletingTopic { TherapyHierarchy.removeTopic(topic.id, data: &snapshot) }
                store.data = snapshot
                deletingFolder = nil; deletingTopic = nil
            }
        } message: {
            Text(deletingFolder != nil ? "Der Ordner wird gelöscht. Seine Unterordner und Inhalte werden eine Ebene nach oben verschoben und bleiben erhalten." : "Das Thema wird gelöscht. Verknüpfte Ziele, Notizen und Materialien bleiben ohne diese Zuordnung erhalten.")
        }
    }
}

struct TherapyTopicDetailView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let topicID: UUID
    @State private var edit: TherapyTopic?
    private var topic: TherapyTopic? { store.data.therapyTopics.first { $0.id == topicID } }
    var body: some View {
        NavigationStack {
            TherapyScreen {
                VStack(alignment: .leading, spacing: 16) {
                    if let topic {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Label(topic.status.rawValue, systemImage: topic.status.symbol).font(.headline)
                                Text(topic.description)
                                if !topic.helps.isEmpty { Label("Hilft mir: " + topic.helps, systemImage: "leaf") }
                                if !topic.barriers.isEmpty { Label("Schwierig: " + topic.barriers, systemImage: "cloud") }
                                if !topic.nextStep.isEmpty { Label("Nächster Schritt: " + topic.nextStep, systemImage: "arrow.right.circle") }
                            }
                        }
                        TherapyGoalsView(topicID: topicID)
                        TherapyNotesCollectionView(topicID: topicID)
                        TherapyMaterialsView(topicID: topicID)
                    }
                }
            }
            .navigationTitle(topic?.title ?? "Thema")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fertig") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Bearbeiten") { edit = topic } }
            }
            .sheet(item: $edit) { TopicEditorView(topic: $0) }
        }
    }
}

struct TherapyGoalsView: View {
    @EnvironmentObject private var store: AppStore
    var topicID: UUID? = nil
    @State private var draft: TherapyGoal?
    @State private var deleting: TherapyGoal?
    @State private var confirmDelete = false
    @State private var showCompleted = true
    private var goals: [TherapyGoal] {
        store.data.therapyGoals.filter { (topicID == nil || $0.topicID == topicID) && (showCompleted || $0.status != .completed) }
            .sorted { $0.createdAt > $1.createdAt }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionHeader(title: "Meine Therapieziele", icon: "scope", subtitle: "Du bestimmst, was für dich ein Fortschritt ist.")
                Spacer()
                Button { draft = TherapyGoal(topicID: topicID) } label: { Image(systemName: "plus.circle.fill").font(.title2).frame(width: 44, height: 44) }.accessibilityLabel("Neues Therapieziel")
            }
            Toggle("Abgeschlossene Ziele anzeigen", isOn: $showCompleted).font(.subheadline)
            if goals.isEmpty { GlassCard { ContentUnavailableView("Deine Ziele dürfen klein sein", systemImage: "scope", description: Text("Formuliere ein eigenes Ziel und einen machbaren nächsten Schritt.")) } }
            ForEach(goals) { goal in
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(goal.title).font(.headline)
                            Spacer()
                            Menu {
                                Button("Bearbeiten", systemImage: "pencil") { draft = goal }
                                Button(goal.status == .completed ? "Wieder aufnehmen" : "Als erreicht markieren", systemImage: "checkmark.circle") {
                                    var copy = goal; copy.status = goal.status == .completed ? .active : .completed
                                    if goal.status == .completed { copy.progress = 0 }
                                    store.saveGoal(copy)
                                }
                                Button("Löschen", systemImage: "trash", role: .destructive) { deleting = goal; confirmDelete = true }
                            } label: { Image(systemName: "ellipsis.circle").frame(width: 44, height: 44) }
                        }
                        Label(goal.status.rawValue, systemImage: goal.status.symbol).font(.caption).foregroundStyle(.secondary)
                        ProgressView(value: Double(goal.progress), total: 100)
                        Text("\(goal.progress) % · selbst eingeschätzt").font(.caption).foregroundStyle(.secondary)
                        if !goal.smallStep.isEmpty { Label(goal.smallStep, systemImage: "arrow.right.circle").font(.subheadline) }
                        if !goal.measure.isEmpty { Text("Daran merke ich es: " + goal.measure).font(.subheadline).foregroundStyle(.secondary) }
                        if let date = goal.dueDate { Label(date.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar").font(.caption) }
                    }
                }
            }
        }
        .sheet(item: $draft) { GoalEditorView(goal: $0) }
        .alert("Therapieziel löschen?", isPresented: $confirmDelete) {
            Button("Abbrechen", role: .cancel) {}
            Button("Löschen", role: .destructive) {
                if let deleting {
                    var snapshot = store.data
                    snapshot.therapyGoals.removeAll { $0.id == deleting.id }
                    for i in snapshot.weeklyTasks.indices where snapshot.weeklyTasks[i].goalID == deleting.id { snapshot.weeklyTasks[i].goalID = nil }
                    store.data = snapshot
                }
            }
        } message: { Text("Dieses Ziel und seine Beschreibung werden endgültig gelöscht.") }
    }
}

struct TherapyNotesCollectionView: View {
    var searchText = ""
    @EnvironmentObject private var store: AppStore
    var folderID: UUID? = nil
    var topicID: UUID? = nil
    var importantOnly = false
    var therapistOnly = false
    var sessionID: UUID? = nil
    @State private var draft: TherapyNote?
    @State private var viewing: TherapyNote?
    @State private var deleting: TherapyNote?
    @State private var confirmDelete = false
    private var notes: [TherapyNote] {
        store.data.notes.filter {
            (searchText.isEmpty || ([$0.title, $0.text] + $0.tags).joined(separator: " ").localizedCaseInsensitiveContains(searchText)) && (folderID == nil || $0.folderID == folderID) && (topicID == nil || $0.topicID == topicID)
                && (!importantOnly || $0.isImportant == true) && (!therapistOnly || $0.author == NoteAuthor.therapist.rawValue || $0.author == NoteAuthor.together.rawValue)
                && (sessionID == nil || $0.sessionID == sessionID)
        }.sorted { ($0.isImportant ?? false) == ($1.isImportant ?? false) ? $0.createdAt > $1.createdAt : $0.isImportant == true }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionHeader(title: therapistOnly ? "Beiträge aus der Therapie" : importantOnly ? "Wichtige Notizen" : "Notizen", icon: therapistOnly ? "person.text.rectangle" : "pin")
                Spacer()
                Button {
                    draft = TherapyNote(title: "", text: "", tags: [], folderID: folderID, topicID: topicID, sessionID: sessionID, author: therapistOnly ? NoteAuthor.therapist.rawValue : NoteAuthor.me.rawValue, isImportant: importantOnly)
                } label: { Image(systemName: "plus.circle.fill").font(.title2).frame(width: 44, height: 44) }.accessibilityLabel("Neue Notiz")
            }
            if notes.isEmpty { GlassCard { Text(therapistOnly ? "Hier kann deine Therapeutin direkt auf deinem Handy etwas festhalten – oder du schreibst einen Beitrag für sie auf." : "Hier ist Platz für Dinge, die du festhalten möchtest.").font(.subheadline).foregroundStyle(.secondary) } }
            ForEach(notes) { note in
                GlassCard(emphasized: note.isImportant == true) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label(note.title, systemImage: note.isImportant == true ? "pin.fill" : "note.text").font(.headline)
                            Spacer()
                            Menu {
                                Button("Bearbeiten", systemImage: "pencil") { draft = note }
                                Button(note.isImportant == true ? "Nicht mehr anheften" : "Als wichtig anheften", systemImage: "pin") {
                                    var copy = note; copy.isImportant = !(note.isImportant ?? false); store.saveNote(copy)
                                }
                                Button("Löschen", systemImage: "trash", role: .destructive) { deleting = note; confirmDelete = true }
                            } label: { Image(systemName: "ellipsis.circle").frame(width: 44, height: 44) }
                        }
                        Text(note.text).font(.subheadline).lineLimit(6)
                        if let ids = note.mediaIDs, !ids.isEmpty { Label("\(ids.count) Anhänge · Foto / Audio / Dokument", systemImage: "paperclip").font(.caption).foregroundStyle(.secondary) }
                        Text("\(note.author ?? NoteAuthor.me.rawValue) · \(note.createdAt.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                        Button("Ganze Notiz öffnen") { viewing = note }.font(.caption.bold())
                    }
                }
            }
        }
        .sheet(item: $draft) { TherapyNoteEditorView(note: $0) }
        .sheet(item: $viewing) { TherapyNoteDetailView(noteID: $0.id) }
        .alert("Notiz löschen?", isPresented: $confirmDelete) {
            Button("Abbrechen", role: .cancel) {}
            Button("Löschen", role: .destructive) { if let deleting { store.data.notes.removeAll { $0.id == deleting.id } } }
        } message: { Text("Diese Notiz wird endgültig gelöscht.") }
    }
}

struct TherapistAreaView: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GlassCard(emphasized: true) {
                VStack(alignment: .leading, spacing: 8) {
                    Label(store.data.profile.therapistName.isEmpty ? "Gemeinsam festhalten" : "Bereich für " + store.data.profile.therapistName, systemImage: "person.text.rectangle").font(.headline)
                    Text("Beobachtungen, Vereinbarungen oder wichtige Hinweise direkt hier eintragen. Bei jeder Notiz lässt sich auswählen, wer sie verfasst hat.").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            TherapyNotesCollectionView(therapistOnly: true)
            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Aktuell besprechen").font(.headline)
                    ForEach(store.data.therapyTopics.filter(\.isCurrent)) { topic in Label(topic.title, systemImage: topic.category.symbol).font(.subheadline) }
                    if !store.data.therapyTopics.contains(where: \.isCurrent) { Text("Wähle Themen über „Aktuelles Thema“ aus.").font(.subheadline).foregroundStyle(.secondary) }
                }
            }
        }
    }
}

struct TherapyMaterialsView: View {
    @EnvironmentObject private var store: AppStore
    var folderID: UUID? = nil
    var topicID: UUID? = nil
    @State private var category: String?
    @State private var query = ""
    @State private var edit: MediaItem?
    @State private var deleting: MediaItem?
    @State private var confirmDelete = false
    @State private var preview: MediaItem?
    @State private var photo = false
    @State private var document = false
    @State private var audio = false
    @State private var knownMediaIDs: Set<UUID> = []
    private var items: [MediaItem] {
        store.data.media.filter {
            (folderID == nil || $0.folderID == folderID) && (topicID == nil || $0.topicID == topicID)
                && (category == nil || $0.category == category)
                && (query.isEmpty || ([$0.title, $0.note, $0.source ?? ""] + $0.tags).contains { $0.localizedCaseInsensitiveContains(query) })
        }.sorted { $0.createdAt > $1.createdAt }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionHeader(title: "Therapiematerialien", icon: "doc.on.doc", subtitle: "Arbeitsblätter, Pläne, Fotos und Aufnahmen.")
                Spacer()
                Menu {
                    Button("Foto", systemImage: "photo") { knownMediaIDs = Set(store.data.media.map(\.id)); photo = true }
                    Button("Dokument", systemImage: "doc") { knownMediaIDs = Set(store.data.media.map(\.id)); document = true }
                    Button("Sprachaufnahme", systemImage: "mic") { knownMediaIDs = Set(store.data.media.map(\.id)); audio = true }
                } label: { Image(systemName: "plus.circle.fill").font(.title2).frame(width: 44, height: 44) }
            }
            TextField("Materialien suchen", text: $query).textFieldStyle(.roundedBorder)
            Picker("Materialart", selection: $category) {
                Text("Alle Materialarten").tag(Optional<String>.none)
                ForEach(MaterialCategory.allCases) { Text($0.rawValue).tag(Optional($0.rawValue)) }
            }
            if items.isEmpty { GlassCard { Text("Importiere ein Material. Über Bearbeiten kannst du Informationen, Kategorie, Thema und Ordner ergänzen.").font(.subheadline).foregroundStyle(.secondary) } }
            ForEach(items) { item in
                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label(item.title, systemImage: item.kind.symbol).font(.headline)
                            Spacer()
                            Menu {
                                Button("Informationen bearbeiten", systemImage: "pencil") { edit = item }
                                Button("Löschen", systemImage: "trash", role: .destructive) { deleting = item; confirmDelete = true }
                            } label: { Image(systemName: "ellipsis.circle").frame(width: 44, height: 44) }
                        }
                        Text(item.category ?? item.kind.displayName).font(.caption).foregroundStyle(.secondary)
                        if !item.note.isEmpty { Text(item.note).font(.subheadline).lineLimit(4) }
                        if let source = item.source, !source.isEmpty { Text("Quelle: " + source).font(.caption).foregroundStyle(.secondary) }
                        if item.attachmentOmitted == true {
                            Label("Anhang beim Export ausgelassen", systemImage: "doc.badge.ellipsis").font(.footnote).foregroundStyle(.secondary)
                            Text("Informationen und Notizen kannst du weiterhin bearbeiten. Die Datei ist in dieser Sicherung nicht enthalten.").font(.caption).foregroundStyle(.secondary)
                        } else {
                            Button("Material öffnen", systemImage: "arrow.up.right.square") { preview = item }
                        }
                        if item.folderID != nil { Text(TherapyHierarchy.path(for: item.folderID, folders: store.data.therapyFolders)).font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
        }
        .sheet(item: $preview) { TherapyMediaDetailView(itemID: $0.id) }
        .sheet(item: $edit) { TherapyMediaEditorView(item: $0) }
        .sheet(isPresented: $photo, onDismiss: assignImported) { AddPhotoView() }
        .sheet(isPresented: $document, onDismiss: assignImported) { ImportDocumentView() }
        .sheet(isPresented: $audio, onDismiss: assignImported) { AudioRecordingView() }
        .alert("Material löschen?", isPresented: $confirmDelete) {
            Button("Abbrechen", role: .cancel) {}
            Button("Löschen", role: .destructive) { if let deleting { store.deleteMedia(deleting) } }
        } message: { Text("Das Material und seine lokale Datei werden endgültig gelöscht.") }
    }
    private func assignImported() {
        guard folderID != nil || topicID != nil else { return }
        var snapshot = store.data
        for i in snapshot.media.indices where !knownMediaIDs.contains(snapshot.media[i].id) {
            snapshot.media[i].folderID = folderID
            snapshot.media[i].topicID = topicID
        }
        if snapshot != store.data { store.data = snapshot }
    }
}
