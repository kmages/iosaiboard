import SwiftUI
import UIKit

/// A text box that brings up the iOSAIBoard panel itself, so it can be tried without switching keyboards.
struct TryItField: UIViewRepresentable {
    @Binding var text: String
    var useBoard: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeUIView(context: Context) -> BoardTextView {
        let view = BoardTextView()
        view.font = .preferredFont(forTextStyle: .body)
        view.backgroundColor = .clear
        view.delegate = context.coordinator
        view.text = text
        view.useBoard = useBoard
        return view
    }

    func updateUIView(_ view: BoardTextView, context: Context) {
        if view.text != text { view.text = text }
        view.useBoard = useBoard
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        private let text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textViewDidChange(_ textView: UITextView) {
            text.wrappedValue = textView.text
        }
    }
}

final class BoardTextView: UITextView {
    /// True shows the iOSAIBoard panel as this box's keyboard; false shows the normal keyboard.
    var useBoard = true {
        didSet {
            if oldValue != useBoard { reloadInputViews() }
        }
    }

    private lazy var board: KeyboardViewController = {
        let controller = KeyboardViewController()
        controller.isEmbedded = true
        return controller
    }()

    override var inputViewController: UIInputViewController? {
        useBoard ? board : nil
    }
}
