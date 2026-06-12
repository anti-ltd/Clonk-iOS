/**
 `ClipboardEntry`: one saved item in the clipboard history. Also defines
 `Date.clipboardRelative` — the relative-time label shown in the UI.
 

 Module: settings · Target: ClinkKit
 Learn: docs/01-settings-and-storage.md
 */
import Foundation

/// One item in the clipboard history FIFO. Pinned entries float to the top and
/// survive trimming and "clear" — they are preference markers, not permanent locks
/// unless `clipboardIgnorePinsOnDelete` is off.
public struct ClipboardEntry: Codable, Equatable, Sendable {
    public var text: String
    /// When the clip was captured — drives the relative-time label in overlay/grid UI.
    public var date: Date
    /// Pinned clips sort first and are exempt from FIFO trimming.
    public var pinned: Bool

    public init(text: String, date: Date = .now, pinned: Bool = false) {
        self.text = text
        self.date = date
        self.pinned = pinned
    }

    // Custom decode so older persisted entries (no `pinned` key) still load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = try c.decode(String.self, forKey: .text)
        date = try c.decode(Date.self, forKey: .date)
        pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
    }
}

extension Date {
    /// Compact relative label for clipboard cards ("Just now", "5m ago", "2d ago").
    public var clipboardRelative: String {
        let seconds = Int(Date.now.timeIntervalSince(self))
        if seconds < 60 { return "Just now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        return "\(hours / 24)d ago"
    }
}
