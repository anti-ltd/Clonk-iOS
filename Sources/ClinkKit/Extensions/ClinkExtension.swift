/**
 `ClinkExtension`: a user-authored keyboard action, powered by a PyMini script.
 Codable so it persists to the App Group (shared with the keyboard extension) and
 travels as a `.clinkext` file for sharing / importing.

 An extension declares where its input comes from (`input`), runs its `transform`
 script over that input, and the script's return value is inserted into the host
 document. See `PyEngine` for the script contract.
 

 Module: extensions · Target: ClinkKit
 Learn: docs/14-extensions-sdk.md
 */
import Foundation

/// Where an action's input text comes from when run inside the keyboard.
public enum ExtInputSource: String, Codable, Sendable, CaseIterable, Identifiable {
    /// No input — the script generates text from nothing (`transform("")`).
    case none
    /// The word currently being typed (before the cursor).
    case word
    /// The current clipboard contents (requires Full Access).
    case clipboard
    /// All text before the cursor in the host field.
    case before

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .none:      return "Nothing"
        case .word:      return "Current word"
        case .clipboard: return "Clipboard"
        case .before:    return "Text before cursor"
        }
    }

    public var detail: String {
        switch self {
        case .none:      return "Generates text from scratch — transform(\"\")."
        case .word:      return "Passes the word you're typing into transform(text)."
        case .clipboard: return "Passes the clipboard text in. Needs Full Access."
        case .before:    return "Passes everything before the cursor in."
        }
    }
}

/// A single user-authored keyboard action. Persisted in the App Group and
/// shareable as `.clinkext` JSON. The keyboard runs `source` through `PyEngine`
/// and inserts (or replaces with) the `transform(text)` return value.
public struct ClinkExtension: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var name: String
    /// SF Symbol shown in the keyboard panel and management list.
    public var icon: String
    /// One-line description shown under the name.
    public var summary: String
    /// The PyMini source — must define `transform(text)`.
    public var source: String
    /// Where the action's input comes from.
    public var input: ExtInputSource
    /// Replace the consumed input with the output (a true transform) rather than
    /// inserting at the cursor. Only applies to `.word` / `.before` inputs — for
    /// `.clipboard` / `.none` there's nothing in the document to replace, so the
    /// output is always inserted. Off = append (e.g. a word-count readout).
    public var replacesInput: Bool
    /// Whether the action appears in the keyboard panel.
    public var enabled: Bool

    public init(
        id: String = "ext-\(UUID().uuidString.prefix(8))",
        name: String,
        icon: String = "wand.and.stars",
        summary: String = "",
        source: String,
        input: ExtInputSource = .word,
        replacesInput: Bool = true,
        enabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.summary = summary
        self.source = source
        self.input = input
        self.replacesInput = replacesInput
        self.enabled = enabled
    }

    // Tolerant decode so older / hand-edited / shared files missing newer keys
    // still load, matching the rest of Clink's storage.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? "ext-\(UUID().uuidString.prefix(8))"
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Untitled"
        icon = try c.decodeIfPresent(String.self, forKey: .icon) ?? "wand.and.stars"
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? ""
        input = (try? c.decodeIfPresent(ExtInputSource.self, forKey: .input)) ?? .word
        replacesInput = try c.decodeIfPresent(Bool.self, forKey: .replacesInput) ?? true
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }
}

// MARK: - Starter & samples

public extension ClinkExtension {
    /// A blank starter script for the editor's "new" action.
    static var starterSource: String {
        """
        # Edit your action here. transform(text) is called with the
        # input you chose; whatever it returns is inserted.
        def transform(text):
            return text
        """
    }

    /// Seeded on first launch so the SDK ships with working examples to learn from.
    static let samples: [ClinkExtension] = [
        ClinkExtension(
            id: "ext-uppercase", name: "UPPERCASE", icon: "textformat.size.larger",
            summary: "Shout the current word",
            source: """
            def transform(text):
                return text.upper()
            """,
            input: .word),

        ClinkExtension(
            id: "ext-reverse", name: "Reverse", icon: "arrow.left.arrow.right",
            summary: "Flip the text backwards",
            source: """
            def transform(text):
                return text[::-1]
            """,
            input: .word),

        ClinkExtension(
            id: "ext-title", name: "Title Case", icon: "textformat",
            summary: "Capitalize Each Word",
            source: """
            def transform(text):
                words = text.split(" ")
                out = []
                for w in words:
                    if len(w) > 0:
                        out.append(w[0].upper() + w[1:].lower())
                    else:
                        out.append(w)
                return " ".join(out)
            """,
            input: .before),

        ClinkExtension(
            id: "ext-snake", name: "snake_case", icon: "lasso",
            summary: "Convert spaces to underscores",
            source: """
            def transform(text):
                return text.strip().lower().replace(" ", "_")
            """,
            input: .before),

        ClinkExtension(
            id: "ext-shrug", name: "Shrug", icon: "face.dashed",
            summary: "Insert a shrug emoticon",
            source: #"""
            def transform(text):
                return "¯\_(ツ)_/¯"
            """#,
            input: .none),

        ClinkExtension(
            id: "ext-wordcount", name: "Word Count", icon: "number",
            summary: "Count words before the cursor",
            source: """
            def transform(text):
                n = len(text.split())
                return f"{n} words"
            """,
            input: .before, replacesInput: false),
    ]
}
