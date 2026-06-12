/**
 `NotepadNote`: a single saved entry in the notepad archive.
 

 Module: settings · Target: ClinkKit
 Learn: docs/01-settings-and-storage.md
 */
import Foundation

/// A saved note in the quick-notepad archive (`NotepadMode.notes`). The compose
/// buffer itself is a plain `String` on `NotepadManager`; these are the snippets
/// the user has deliberately stored away for re-insertion.
public struct NotepadNote: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var text: String
    /// When the note was saved — shown in the browse list.
    public var date: Date

    public init(id: UUID = UUID(), text: String, date: Date = .now) {
        self.id = id
        self.text = text
        self.date = date
    }

    /// First non-empty line, for the row's title; falls back to a placeholder.
    public var title: String {
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Empty note" : trimmed
    }
}
