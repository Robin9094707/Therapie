import SwiftUI
import UIKit

/// Holds the actual editor so Send reads committed text, including marked keyboard input.
@MainActor final class ChatComposerHandle: ObservableObject {
    weak var editor: UITextView?
    var currentText: String? { editor?.text }
    func finishEditing() { editor?.unmarkText(); editor?.resignFirstResponder() }
    func clearIfUnchanged(_ sent: String) -> Bool {
        guard let editor, editor.text == sent else { return false }
        editor.text = ""
        return true
    }
}
@MainActor struct ChatComposerInput: UIViewRepresentable {
    @Binding var text: String
    let handle: ChatComposerHandle
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UITextView {
        let editor = UITextView()
        editor.backgroundColor = .clear
        editor.font = .preferredFont(forTextStyle: .body)
        editor.adjustsFontForContentSizeCategory = true
        editor.textColor = .label
        editor.textContainerInset = UIEdgeInsets(top: 11, left: 9, bottom: 11, right: 9)
        editor.textContainer.lineFragmentPadding = 0
        editor.isScrollEnabled = true
        editor.delegate = context.coordinator
        editor.text = text
        editor.accessibilityLabel = "Deine Nachricht"
        editor.accessibilityIdentifier = "ai.composer"
        editor.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        handle.editor = editor
        return editor
    }
    func updateUIView(_ editor: UITextView, context: Context) {
        context.coordinator.parent = self
        handle.editor = editor
        // Never replace active or marked input with an older SwiftUI render value.
        if !editor.isFirstResponder && editor.markedTextRange == nil && editor.text != text { editor.text = text }
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 280
        let measured = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: min(130, max(44, measured.height)))
    }
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: ChatComposerInput
        init(_ parent: ChatComposerInput) { self.parent = parent }
        func textViewDidChange(_ textView: UITextView) { parent.text = textView.text }
        func textViewDidEndEditing(_ textView: UITextView) { parent.text = textView.text }
    }
}
