import UIKit

/// A keyboard with no letter keys: type with your usual keyboard, switch here, tap Fix.
/// Fixes the selected text if there is a selection, otherwise the text before the cursor.
final class KeyboardViewController: UIInputViewController {
    private struct Applied: Codable {
        let original: String
        let fixed: String
    }

    /// The last fix, kept on disk so Undo still works after switching keyboards and back.
    private static let appliedKey = "lastApplied"

    private func remember(_ applied: Applied?) {
        lastApplied = applied
        undoButton.isEnabled = applied != nil
        let data = applied.flatMap { try? JSONEncoder().encode($0) }
        UserDefaults.standard.set(data, forKey: Self.appliedKey)
    }

    private let fixButton = UIButton(type: .system)
    private let undoButton = UIButton(type: .system)
    private let globeButton = UIButton(type: .system)
    private let statusLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private var lastApplied: Applied?
    private var task: Task<Void, Never>?

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        if let data = UserDefaults.standard.data(forKey: Self.appliedKey),
           let applied = try? JSONDecoder().decode(Applied.self, from: data) {
            lastApplied = applied
            undoButton.isEnabled = true
        }
        setStatus(hasFullAccess ? "Put the cursor at the end of your text, then tap Fix."
                                : "Turn on Allow Full Access for iOSAIBoard in Settings.")
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        globeButton.isHidden = !needsInputModeSwitchKey
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        task?.cancel()
        setBusy(false)
    }

    // MARK: - UI

    private func buildUI() {
        let height = view.heightAnchor.constraint(equalToConstant: 170)
        height.priority = .defaultHigh
        height.isActive = true

        var fixConfig = UIButton.Configuration.filled()
        fixConfig.title = "Fix"
        fixConfig.image = UIImage(systemName: "checkmark.circle.fill")
        fixConfig.imagePadding = 8
        fixConfig.cornerStyle = .large
        fixConfig.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attrs in
            var attrs = attrs
            attrs.font = .systemFont(ofSize: 22, weight: .semibold)
            return attrs
        }
        fixButton.configuration = fixConfig
        fixButton.addTarget(self, action: #selector(fixTapped), for: .touchUpInside)

        var undoConfig = UIButton.Configuration.gray()
        undoConfig.title = "Undo"
        undoConfig.image = UIImage(systemName: "arrow.uturn.backward")
        undoConfig.imagePadding = 6
        undoConfig.cornerStyle = .large
        undoButton.configuration = undoConfig
        undoButton.isEnabled = false
        undoButton.addTarget(self, action: #selector(undoTapped), for: .touchUpInside)

        var globeConfig = UIButton.Configuration.gray()
        globeConfig.image = UIImage(systemName: "globe")
        globeConfig.cornerStyle = .large
        globeButton.configuration = globeConfig
        globeButton.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)

        statusLabel.font = .preferredFont(forTextStyle: .footnote)
        statusLabel.textColor = .secondaryLabel
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 2
        statusLabel.adjustsFontSizeToFitWidth = true
        statusLabel.minimumScaleFactor = 0.8

        spinner.hidesWhenStopped = true

        let buttons = UIStackView(arrangedSubviews: [globeButton, undoButton, fixButton])
        buttons.axis = .horizontal
        buttons.spacing = 10
        buttons.distribution = .fill
        globeButton.widthAnchor.constraint(equalToConstant: 52).isActive = true
        undoButton.widthAnchor.constraint(equalToConstant: 104).isActive = true

        let statusRow = UIStackView(arrangedSubviews: [spinner, statusLabel])
        statusRow.axis = .horizontal
        statusRow.spacing = 8
        statusRow.alignment = .center

        let column = UIStackView(arrangedSubviews: [statusRow, buttons])
        column.axis = .vertical
        column.spacing = 10
        column.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(column)

        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            column.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            column.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            column.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
            statusRow.heightAnchor.constraint(equalToConstant: 40),
        ])
    }

    private func setStatus(_ text: String) {
        statusLabel.text = text
    }

    private func setBusy(_ busy: Bool) {
        fixButton.isEnabled = !busy
        if busy { spinner.startAnimating() } else { spinner.stopAnimating() }
    }

    // MARK: - Fix

    @objc private func fixTapped() {
        guard hasFullAccess else {
            setStatus("Turn on Allow Full Access for iOSAIBoard in Settings.")
            return
        }
        let selection = textDocumentProxy.selectedText ?? ""
        let usingSelection = !selection.isEmpty
        let source = usingSelection ? selection : (textDocumentProxy.documentContextBeforeInput ?? "")
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            setStatus("Nothing to fix. Put the cursor at the end of your text, or select it.")
            return
        }

        setBusy(true)
        setStatus("Checking \(source.split(whereSeparator: \.isWhitespace).count) words...")
        task = Task { [weak self] in
            do {
                let fixed = try await FixClient.fix(source)
                guard let self, !Task.isCancelled else { return }
                self.apply(original: source, fixed: fixed, usingSelection: usingSelection)
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.setStatus((error as? LocalizedError)?.errorDescription ?? "Could not reach the server.")
            }
            self?.setBusy(false)
        }
    }

    private func apply(original: String, fixed: String, usingSelection: Bool) {
        let proxy = textDocumentProxy
        // Only touch the text if it is still exactly what was sent.
        let current = usingSelection ? (proxy.selectedText ?? "") : (proxy.documentContextBeforeInput ?? "")
        guard current == original else {
            setStatus("The text changed while checking. Tap Fix again.")
            return
        }
        guard fixed != original else {
            setStatus("Looks good. Nothing to fix.")
            switchBackSoon()
            return
        }

        if usingSelection {
            proxy.insertText(fixed)
        } else {
            replaceTail(of: original, with: fixed)
        }
        remember(Applied(original: original, fixed: fixed))
        setStatus("Fixed. Come back here to undo.")
        switchBackSoon()
    }

    /// Returns to the keyboard you were typing on, after a beat so the result is visible.
    private func switchBackSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.advanceToNextInputMode()
        }
    }

    @objc private func undoTapped() {
        guard let applied = lastApplied else { return }
        // The fixed text must still sit right before the cursor.
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        let overlap = min(before.count, applied.fixed.count)
        guard overlap > 0, before.suffix(overlap) == applied.fixed.suffix(overlap) else {
            setStatus("Can't undo: the text has changed since the fix.")
            remember(nil)
            return
        }
        replaceTail(of: applied.fixed, with: applied.original)
        remember(nil)
        setStatus("Put back the way it was.")
    }

    /// Swaps the text before the cursor from `old` to `new`, leaving their shared beginning alone.
    private func replaceTail(of old: String, with new: String) {
        let shared = zip(old, new).prefix { $0 == $1 }.count
        for _ in 0..<(old.count - shared) {
            textDocumentProxy.deleteBackward()
        }
        let tail = String(new.dropFirst(shared))
        if !tail.isEmpty {
            textDocumentProxy.insertText(tail)
        }
    }
}
