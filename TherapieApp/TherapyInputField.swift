import SwiftUI

/// The fallback lets a disappearing row finish rendering. Removed values never get reinserted.
func identifiedEditorBinding<Value: Identifiable>(_ values: Binding<[Value]>, to initial: Value) -> Binding<Value> {
    let id = initial.id
    return Binding(get: {
        IdentifiedDraftAccess.read(id: id, fallback: initial, from: values.wrappedValue)
    }, set: { updated in
        var snapshot = values.wrappedValue
        if IdentifiedDraftAccess.replace(updated, id: id, in: &snapshot) { values.wrappedValue = snapshot }
    })
}

struct TherapyInputField: View {
    let title: String
    var prompt = "Optional – hier schreiben"
    var symbol = "square.and.pencil"
    var multiline = true
    var identifier: String?
    @Binding var text: String
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(title, systemImage: symbol).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            TextField(prompt, text: $text, axis: multiline ? .vertical : .horizontal)
                .textFieldStyle(.plain).font(.body).lineLimit(multiline ? 3...7 : 1...1)
                .focused($focused).submitLabel(multiline ? .return : .done)
                .onSubmit { if !multiline { focused = false } }
                .padding(.horizontal, 14).padding(.vertical, 13)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(focused ? Color.accentColor.opacity(0.65) : Color.primary.opacity(0.12), lineWidth: focused ? 1.5 : 1) }
                .accessibilityLabel(title).accessibilityIdentifier(identifier ?? title)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: focused)
        }
    }
}

struct CheckInTaskEditor: View {
    @Binding var task: CheckInTaskDraft
    let remove: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                Label("Dein kleiner Schritt", systemImage: "checklist").font(.headline)
                Spacer(minLength: 8)
                Button("Entfernen", systemImage: "trash", role: .destructive, action: remove)
                    .labelStyle(.iconOnly).frame(width: 44, height: 44)
                    .accessibilityLabel("Aufgabe entfernen").accessibilityIdentifier("checkin.task.remove." + task.id.uuidString)
            }
            TherapyInputField(title: "Was möchtest du tun?", prompt: "Aufgabe benennen", symbol: "checkmark.circle", multiline: false, identifier: "checkin.task.title." + task.id.uuidString, text: $task.title)
            Picker("Von wem kommt die Aufgabe?", selection: $task.source) {
                ForEach(["Von mir", "Aus der Therapie", "Gemeinsam"], id: \.self) { Text($0).tag($0) }
            }.pickerStyle(.menu)
            TherapyInputField(title: "Der kleinste machbare Schritt", symbol: "figure.walk", text: $task.smallStep)
            TherapyInputField(title: "Details oder Unterstützung", symbol: "text.bubble", text: $task.details)
            Toggle("Zieltermin festlegen", isOn: Binding(get: { task.dueDate != nil }, set: { task.dueDate = $0 ? Date() : nil }))
            if task.dueDate != nil {
                DatePicker("Bis wann?", selection: Binding(get: { task.dueDate ?? Date() }, set: { task.dueDate = $0 }), displayedComponents: .date)
            }
        }.padding(16)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 22))
            .overlay { RoundedRectangle(cornerRadius: 22).strokeBorder(Color.primary.opacity(0.07), lineWidth: 1) }
    }
}
