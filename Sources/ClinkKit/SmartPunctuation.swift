/**
 Smart-punctuation rules applied after each insertion: curly-quote substitution,
 double-space to period, and contraction apostrophes. Mirrors the native
 keyboard's typographic niceties that iOS won't expose to third-party keyboards.
 

 Module: keyboard-core · Target: ClinkKit
 Learn: docs/02-keyboard-core.md
 */
import Foundation

/// Smart-punctuation rules that mirror the native keyboard's typographic touches:
/// straight quotes → curly, `--` → em-dash, and double-space → ". ". These are
/// the parts of "auto-punctuation" Apple won't do for a third-party keyboard, so
/// we apply them ourselves on the insert path. Pure (context in, edit out) so the
/// keyboard extension can drive it off `textDocumentProxy` and it stays testable.
///
/// All of this is gated by the user's `autoPunctuationEnabled` setting — the same
/// switch that governs contraction apostrophes — since it's the same flavour of
/// "tidy my typing for me" behaviour.
public enum SmartPunctuation {

    /// Characters that count as part of a word for partial-word / contraction
    /// detection: letters plus straight *and* curly apostrophes, so a smart quote
    /// inside "don't" / "y'all" never splits the word out from under the
    /// suggestion engine.
    public static func isWordChar(_ c: Character) -> Bool {
        c.isLetter || c == "'" || c == "\u{2019}" || c == "\u{2018}"
    }

    /// The trailing partial word immediately before the cursor (used by the
    /// suggestion engine and autocorrect to know what's being typed).
    public static func trailingPartialWord(in context: String) -> String {
        String(context.reversed().prefix(while: isWordChar).reversed())
    }

    /// What to substitute when `inserted` is typed, given the text before the
    /// cursor. `deleteBackward` chars are removed first, then `insert` is inserted
    /// in place of the original character. Returns nil to insert `inserted` as-is.
    /// A single smart-punctuation substitution: delete N chars behind the cursor,
    /// then insert the replacement string.
    public struct Edit: Equatable {
        public var deleteBackward: Int
        public var insert: String
        public init(deleteBackward: Int, insert: String) {
            self.deleteBackward = deleteBackward
            self.insert = insert
        }
    }

    /// Returns a substitution edit for `inserted`, or nil to insert as-is.
    public static func edit(for inserted: String, before: String) -> Edit? {
        switch inserted {
        case " ":
            // Double-space → ". " — only after a word char followed by a single
            // space (so "word " + space → "word. "). Guarding on an alphanumeric
            // before the space stops it firing after existing punctuation, which
            // also makes it self-limiting: once we've written ". " a further
            // space sees "." before the space and does nothing.
            guard before.last == " " else { return nil }
            let prior = before.dropLast().last
            guard let prior, prior.isLetter || prior.isNumber else { return nil }
            return Edit(deleteBackward: 1, insert: ". ")

        case "-":
            // `--` → em-dash. (A third "-" after "—" just inserts normally.)
            guard before.last == "-" else { return nil }
            return Edit(deleteBackward: 1, insert: "\u{2014}")

        case "\"":
            return Edit(deleteBackward: 0,
                        insert: opensDouble(before: before) ? "\u{201C}" : "\u{201D}")

        case "'":
            return Edit(deleteBackward: 0,
                        insert: opensSingle(before: before) ? "\u{2018}" : "\u{2019}")

        default:
            return nil
        }
    }

    /// Opening “ at a boundary (start, after whitespace or an opening bracket),
    /// closing ” otherwise.
    private static func opensDouble(before: String) -> Bool {
        guard let last = before.last else { return true }
        return last.isWhitespace || "([{".contains(last) || last == "\u{201C}"
    }

    /// An apostrophe after a letter/number is a closing ’ (contraction or
    /// possessive — "don't", "James'"); at a boundary it's an opening ‘.
    private static func opensSingle(before: String) -> Bool {
        guard let last = before.last else { return true }
        if last.isLetter || last.isNumber { return false }
        return last.isWhitespace || "([{".contains(last)
    }
}
