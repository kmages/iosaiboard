import UIKit

/// A keyboard with no letter keys: type with your usual keyboard, switch here, tap Check.
/// It lists each correction; skip any you don't want, then tap Fix all.
/// Works on the selected text if there is a selection, otherwise the text before the cursor.
final class KeyboardViewController: UIInputViewController, UITableViewDataSource, UITableViewDelegate {
    private struct Applied: Codable {
        let original: String
        let fixed: String
    }

    /// A correction waiting for the person to accept or skip its changes.
    private struct Review {
        let original: String
        let usingSelection: Bool
        let diff: TextDiff
        /// A short label for each change, such as "Spelling", in the same order as `diff.changes`.
        let reasons: [String]
        var accepted: Set<Int>
        /// Set for a tone rewrite: the whole new text, shown as one piece to take or leave.
        var rewrite: String? = nil
        var toneName: String? = nil
    }

    private static let tones = ["Professional", "Friendly", "Direct", "Shorter"]

    /// The last fix, kept on disk so Undo still works after switching keyboards and back.
    private static let appliedKey = "lastApplied"
    private static let idleHeight: CGFloat = 216
    private static let reviewHeight: CGFloat = 330

    private let mainButton = UIButton(type: .system)
    private let undoButton = UIButton(type: .system)
    private let globeButton = UIButton(type: .system)
    private let statusLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let toneRow = UIStackView()
    private var heightConstraint: NSLayoutConstraint?
    private var lastApplied: Applied?
    private var review: Review?
    private var task: Task<Void, Never>?

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        if let data = UserDefaults.standard.data(forKey: Self.appliedKey),
           let applied = try? JSONDecoder().decode(Applied.self, from: data) {
            lastApplied = applied
        }
        refreshButtons()
        setStatus(hasFullAccess ? "Put the cursor at the end of your text, then tap Check."
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
        let height = view.heightAnchor.constraint(equalToConstant: Self.idleHeight)
        height.priority = .defaultHigh
        height.isActive = true
        heightConstraint = height

        mainButton.addTarget(self, action: #selector(mainTapped), for: .touchUpInside)
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

        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "change")
        tableView.backgroundColor = .clear
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 44
        tableView.isHidden = true
        tableView.layer.cornerRadius = 10

        let buttons = UIStackView(arrangedSubviews: [globeButton, undoButton, mainButton])
        buttons.axis = .horizontal
        buttons.spacing = 10
        buttons.distribution = .fill
        globeButton.widthAnchor.constraint(equalToConstant: 52).isActive = true
        undoButton.widthAnchor.constraint(equalToConstant: 112).isActive = true
        // Buttons are a normal height while the list is showing, and grow to fill when it is not.
        let buttonHeight = buttons.heightAnchor.constraint(equalToConstant: 56)
        buttonHeight.priority = .defaultHigh
        buttonHeight.isActive = true

        toneRow.axis = .horizontal
        toneRow.spacing = 8
        toneRow.distribution = .fillEqually
        for (index, tone) in Self.tones.enumerated() {
            var config = UIButton.Configuration.gray()
            config.title = tone
            config.cornerStyle = .large
            config.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 2, bottom: 4, trailing: 2)
            config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attrs in
                var attrs = attrs
                attrs.font = .systemFont(ofSize: 13, weight: .medium)
                return attrs
            }
            let button = UIButton(configuration: config)
            button.tag = index
            button.titleLabel?.adjustsFontSizeToFitWidth = true
            button.addTarget(self, action: #selector(toneTapped(_:)), for: .touchUpInside)
            toneRow.addArrangedSubview(button)
        }
        toneRow.heightAnchor.constraint(equalToConstant: 36).isActive = true

        let statusRow = UIStackView(arrangedSubviews: [spinner, statusLabel])
        statusRow.axis = .horizontal
        statusRow.spacing = 8
        statusRow.alignment = .center

        let column = UIStackView(arrangedSubviews: [statusRow, tableView, toneRow, buttons])
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
        mainButton.isEnabled = !busy
        toneRow.isUserInteractionEnabled = !busy
        toneRow.alpha = busy ? 0.5 : 1
        if busy { spinner.startAnimating() } else { spinner.stopAnimating() }
    }

    /// Sets both buttons' labels for the current state: idle, or reviewing changes.
    private func refreshButtons() {
        var main = UIButton.Configuration.filled()
        main.cornerStyle = .large
        main.imagePadding = 8
        main.image = UIImage(systemName: "checkmark.circle.fill")
        main.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attrs in
            var attrs = attrs
            attrs.font = .systemFont(ofSize: 20, weight: .semibold)
            return attrs
        }
        var undo = UIButton.Configuration.gray()
        undo.cornerStyle = .large
        undo.imagePadding = 6

        if let review, review.rewrite != nil {
            main.title = "Use this"
            undo.title = "Cancel"
            undoButton.isEnabled = true
        } else if let review {
            let total = review.diff.changes.count
            let chosen = review.accepted.count
            if chosen == total {
                main.title = "Fix all \(total)"
            } else if chosen == 0 {
                main.title = "Fix none"
                main.image = UIImage(systemName: "xmark.circle.fill")
            } else {
                main.title = "Fix \(chosen) of \(total)"
            }
            undo.title = "Cancel"
            undoButton.isEnabled = true
        } else {
            main.title = "Check"
            undo.title = "Undo"
            undo.image = UIImage(systemName: "arrow.uturn.backward")
            undoButton.isEnabled = lastApplied != nil
        }
        mainButton.configuration = main
        undoButton.configuration = undo
    }

    private func showReview(_ newReview: Review?) {
        review = newReview
        tableView.isHidden = newReview == nil
        toneRow.isHidden = newReview != nil
        heightConstraint?.constant = newReview == nil ? Self.idleHeight : Self.reviewHeight
        tableView.reloadData()
        refreshButtons()
    }

    private func remember(_ applied: Applied?) {
        lastApplied = applied
        let data = applied.flatMap { try? JSONEncoder().encode($0) }
        UserDefaults.standard.set(data, forKey: Self.appliedKey)
        refreshButtons()
    }

    // MARK: - Check

    @objc private func mainTapped() {
        if review != nil {
            applyReview()
        } else {
            startCheck()
        }
    }

    @objc private func toneTapped(_ sender: UIButton) {
        startCheck(tone: Self.tones[sender.tag])
    }

    private func startCheck(tone: String? = nil) {
        guard hasFullAccess else {
            setStatus("Turn on Allow Full Access for iOSAIBoard in Settings.")
            return
        }
        let selection = textDocumentProxy.selectedText ?? ""
        let usingSelection = !selection.isEmpty
        let source = usingSelection ? selection : (textDocumentProxy.documentContextBeforeInput ?? "")
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            setStatus("Nothing to check. Put the cursor at the end of your text, or select it.")
            return
        }

        setBusy(true)
        setStatus(tone.map { "Rewriting, \($0.lowercased())..." }
                  ?? "Checking \(source.split(whereSeparator: \.isWhitespace).count) words...")
        task = Task { [weak self] in
            do {
                let result = try await FixClient.check(source, tone: tone?.lowercased())
                guard let self, !Task.isCancelled else { return }
                if let tone {
                    self.presentRewrite(original: source, rewrite: result.fixed, tone: tone,
                                        usingSelection: usingSelection)
                } else {
                    self.present(original: source, result: result, usingSelection: usingSelection)
                }
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.setStatus((error as? LocalizedError)?.errorDescription ?? "Could not reach the server.")
            }
            self?.setBusy(false)
        }
    }

    /// Shows the changes for review. Nothing in the text is touched yet.
    private func present(original: String, result: FixResult, usingSelection: Bool) {
        let fixed = result.fixed
        let diff = TextDiff(original: original, fixed: fixed)
        guard fixed != original, !diff.changes.isEmpty else {
            setStatus("Looks good. Nothing to fix.")
            switchBackSoon()
            return
        }
        let count = diff.changes.count
        setStatus(count == 1 ? "1 change. Tap it to skip it, or tap Fix all."
                             : "\(count) changes. Tap any you want to skip, then Fix all.")
        showReview(Review(original: original, usingSelection: usingSelection, diff: diff,
                          reasons: diff.changes.map { Self.reason(for: $0, saved: result.saved) },
                          accepted: Set(diff.changes.indices)))
    }

    /// Shows a tone rewrite as one piece to take or leave. Nothing in the text is touched yet.
    private func presentRewrite(original: String, rewrite: String, tone: String, usingSelection: Bool) {
        setStatus("\(tone) version below. Tap Use this, or Cancel to keep yours.")
        showReview(Review(original: original, usingSelection: usingSelection,
                          diff: TextDiff(original: original, fixed: original), reasons: [],
                          accepted: [], rewrite: rewrite, toneName: tone))
    }

    private func applyReview() {
        guard let review else { return }
        showReview(nil)
        guard review.rewrite != nil || !review.accepted.isEmpty else {
            setStatus("Left as it was.")
            return
        }
        let proxy = textDocumentProxy
        // Only touch the text if it is still exactly what was checked.
        let current = review.usingSelection ? (proxy.selectedText ?? "") : (proxy.documentContextBeforeInput ?? "")
        guard current == review.original else {
            setStatus("The text changed since the check. Tap Check again.")
            return
        }
        let result = review.rewrite ?? review.diff.result(accepting: review.accepted)
        if review.usingSelection {
            proxy.insertText(result)
        } else {
            replaceTail(of: review.original, with: result)
        }
        remember(Applied(original: review.original, fixed: result))
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
        if review != nil {
            showReview(nil)
            setStatus("Left as it was.")
            return
        }
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

    // MARK: - Change list

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let review else { return 0 }
        return review.rewrite == nil ? review.diff.changes.count : 1
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "change", for: indexPath)
        guard let review else { return cell }
        if let rewrite = review.rewrite {
            var content = cell.defaultContentConfiguration()
            content.text = rewrite
            content.textProperties.numberOfLines = 0
            content.secondaryText = review.toneName.map { "\($0) rewrite" }
            content.secondaryTextProperties.color = .secondaryLabel
            cell.contentConfiguration = content
            cell.accessoryType = .none
            cell.backgroundColor = .secondarySystemBackground
            cell.selectionStyle = .none
            return cell
        }
        let change = review.diff.changes[indexPath.row]
        let accepted = review.accepted.contains(indexPath.row)

        var content = cell.defaultContentConfiguration()
        content.attributedText = Self.describe(change, accepted: accepted)
        content.textProperties.numberOfLines = 2
        content.secondaryText = review.reasons[indexPath.row]
        content.secondaryTextProperties.color = accepted ? .secondaryLabel : .tertiaryLabel
        cell.contentConfiguration = content
        cell.accessoryType = accepted ? .checkmark : .none
        cell.backgroundColor = .secondarySystemBackground
        cell.selectionStyle = .none
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard var current = review, current.rewrite == nil else { return }
        if current.accepted.contains(indexPath.row) {
            current.accepted.remove(indexPath.row)
        } else {
            current.accepted.insert(indexPath.row)
        }
        review = current
        tableView.reloadRows(at: [indexPath], with: .none)
        refreshButtons()
    }

    /// Names the kind of mistake, worked out on the phone so it costs no extra wait.
    private static func reason(for change: TextChange, saved: [SavedSwap]) -> String {
        let old = change.old.trimmingCharacters(in: .whitespacesAndNewlines)
        let new = change.new.trimmingCharacters(in: .whitespacesAndNewlines)
        if old.isEmpty && new.isEmpty { return "Spacing" }
        if saved.contains(where: {
            old.range(of: $0.from, options: .caseInsensitive) != nil
                && new.range(of: $0.to, options: .caseInsensitive) != nil
        }) {
            return "Your saved correction"
        }

        let lettersOnly: (String) -> String = { text in
            String(text.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
        }
        let oldLetters = lettersOnly(old), newLetters = lettersOnly(new)
        if old.isEmpty { return newLetters.isEmpty ? "Missing punctuation" : "Missing word" }
        if new.isEmpty { return oldLetters.isEmpty ? "Extra punctuation" : "Extra word" }
        if old.lowercased() == new.lowercased() { return "Capitalization" }

        if oldLetters.lowercased() == newLetters.lowercased() {
            let apostrophes: (String) -> Int = { text in text.filter { $0 == "'" || $0 == "\u{2019}" }.count }
            if apostrophes(old) != apostrophes(new) { return "Apostrophe" }
            if old.contains(" ") != new.contains(" ") { return "Spelling" }
            return oldLetters == newLetters ? "Punctuation" : "Capitalization and punctuation"
        }

        let checker = UITextChecker()
        let misspelled = old.split(separator: " ").contains { word in
            let text = String(word)
            let range = NSRange(location: 0, length: (text as NSString).length)
            return checker.rangeOfMisspelledWord(in: text, range: range, startingAt: 0,
                                                 wrap: false, language: "en_US").location != NSNotFound
        }
        return misspelled ? "Spelling" : "Grammar"
    }

    /// "their → they're", with the old text struck through. Skipped changes are greyed out.
    private static func describe(_ change: TextChange, accepted: Bool) -> NSAttributedString {
        let old = change.old.trimmingCharacters(in: .whitespacesAndNewlines)
        let new = change.new.trimmingCharacters(in: .whitespacesAndNewlines)
        let font = UIFont.preferredFont(forTextStyle: .body)
        let oldColor: UIColor = accepted ? .systemRed : .tertiaryLabel
        let newColor: UIColor = accepted ? .systemGreen : .tertiaryLabel
        let plainColor: UIColor = accepted ? .secondaryLabel : .tertiaryLabel
        let text = NSMutableAttributedString()

        func add(_ string: String, _ color: UIColor, struck: Bool = false) {
            var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
            if struck { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            text.append(NSAttributedString(string: string, attributes: attributes))
        }

        if old.isEmpty && new.isEmpty {
            add("Fix spacing", plainColor)
        } else if old.isEmpty {
            add("Add ", plainColor)
            add(new, newColor)
        } else if new.isEmpty {
            add("Remove ", plainColor)
            add(old, oldColor, struck: true)
        } else {
            add(old, oldColor, struck: true)
            add("  →  ", plainColor)
            add(new, newColor)
        }
        return text
    }
}
