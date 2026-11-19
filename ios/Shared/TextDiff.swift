import Foundation

/// One difference between what was typed and the corrected text.
struct TextChange {
    /// Positions in the original's token list that this change replaces. Empty for a pure addition.
    let range: Range<Int>
    let old: String
    let new: String
}

/// Splits a correction into separate changes so each one can be accepted or skipped.
struct TextDiff {
    private let tokens: [String]
    let changes: [TextChange]

    init(original: String, fixed: String) {
        let a = Self.tokenize(original)
        let b = Self.tokenize(fixed)
        tokens = a

        var removed = Set<Int>()
        var inserted = Set<Int>()
        for step in b.difference(from: a) {
            switch step {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }

        var found: [TextChange] = []
        var i = 0, j = 0
        while i < a.count || j < b.count {
            if removed.contains(i) || inserted.contains(j) {
                let start = i
                var new = ""
                while removed.contains(i) || inserted.contains(j) {
                    if removed.contains(i) { i += 1 }
                    if inserted.contains(j) { new += b[j]; j += 1 }
                }
                found.append(TextChange(range: start..<i, old: a[start..<i].joined(), new: new))
            } else {
                i += 1
                j += 1
            }
        }
        changes = found
    }

    /// The text with only the chosen changes made.
    func result(accepting accepted: Set<Int>) -> String {
        var out = ""
        var position = 0
        for (index, change) in changes.enumerated() {
            out += tokens[position..<change.range.lowerBound].joined()
            out += accepted.contains(index) ? change.new : change.old
            position = change.range.upperBound
        }
        out += tokens[position...].joined()
        return out
    }

    /// Alternating runs of words (with their punctuation) and whitespace.
    private static func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var currentIsSpace = false
        for character in text {
            let isSpace = character.isWhitespace
            if !current.isEmpty && isSpace != currentIsSpace {
                tokens.append(current)
                current = ""
            }
            current.append(character)
            currentIsSpace = isSpace
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }
}
