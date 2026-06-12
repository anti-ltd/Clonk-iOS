/**
 `ClinkPanel`: a user-authored keyboard *panel* — a custom UI rendered inside the
 keyboard from a PyMini script (vs. `ClinkExtension`, which is a one-shot text
 action). The script defines `view(state)` (and optionally `initial()`); buttons
 drive an MVU loop (`set` updates state, `insert` types into the document). See
 `PanelRuntime`. Codable for App Group persistence and `.clinkpanel` sharing.
 

 Module: custom-panels · Target: ClinkKit
 Learn: docs/07-custom-panels.md
 */
import Foundation

/// Where a custom panel appears in the keyboard's panel picker.
public enum PanelPlacement: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Follow the global "show custom panels alongside built-ins" setting.
    case `default`
    /// Always its own top-level entry, next to Clipboard / Notepad / etc.
    case standalone
    /// Always grouped behind the single "Panels" entry.
    case grouped

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .default:    return "Default"
        case .standalone: return "Standalone"
        case .grouped:    return "Grouped"
        }
    }
    public var detail: String {
        switch self {
        case .default:    return "Follows the global setting above."
        case .standalone: return "Its own button in the panel picker."
        case .grouped:    return "Nested behind the Panels button."
        }
    }
}

/// A user-authored keyboard panel — a custom UI rendered from a PyMini script
/// (`view(state)` MVU loop) rather than a one-shot text transform. Persisted in
/// the App Group and shareable as `.clinkpanel` JSON.
public struct ClinkPanel: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var name: String
    /// SF Symbol shown in the panel picker and management list.
    public var icon: String
    /// One-line description shown under the name.
    public var summary: String
    /// PyMini source — must define `view(state)`; may define `initial()`.
    public var source: String
    /// Per-panel override of where it appears in the picker.
    public var placement: PanelPlacement
    /// Whether the panel appears in the keyboard picker.
    public var enabled: Bool

    public init(
        id: String = "panel-\(UUID().uuidString.prefix(8))",
        name: String,
        icon: String = "square.grid.2x2",
        summary: String = "",
        source: String,
        placement: PanelPlacement = .default,
        enabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.summary = summary
        self.source = source
        self.placement = placement
        self.enabled = enabled
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? "panel-\(UUID().uuidString.prefix(8))"
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Untitled"
        icon = try c.decodeIfPresent(String.self, forKey: .icon) ?? "square.grid.2x2"
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? ""
        placement = (try? c.decodeIfPresent(PanelPlacement.self, forKey: .placement)) ?? .default
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }

    /// Resolve whether this panel is standalone, given the global default.
    public func isStandalone(globalDefault: Bool) -> Bool {
        switch placement {
        case .standalone: return true
        case .grouped:    return false
        case .default:    return globalDefault
        }
    }
}

// MARK: - Starter & samples

public extension ClinkPanel {
    /// Starter for a new panel: a small counter demonstrating the MVU loop.
    static var starterSource: String {
        """
        # A custom panel. view(state) returns the UI; buttons either
        # `set` new state (re-renders) or `insert` text into the field.
        def initial():
            return {"count": 0}

        def view(state):
            return vstack([
                text("Count: " + str(state["count"]), size=22, weight="bold"),
                hstack([
                    button("-", set={"count": state["count"] - 1}),
                    button("+", set={"count": state["count"] + 1}),
                ]),
                button("Insert", insert=str(state["count"]), style="primary"),
            ])
        """
    }

    static let samples: [ClinkPanel] = [
        ClinkPanel(
            id: "panel-kaomoji", name: "Kaomoji", icon: "face.smiling",
            summary: "Tap to insert a kaomoji",
            source: #"""
            def view(state):
                faces = ["(╯°□°)╯︵ ┻━┻", "¯\_(ツ)_/¯", "(づ｡◕‿‿◕｡)づ",
                         "ಠ_ಠ", "(╥﹏╥)", "ᕕ( ᐛ )ᕗ", "(◕‿◕)", "(ノ◕ヮ◕)ノ*:･ﾟ✧"]
                rows = []
                for f in faces:
                    rows.append(button(f, insert=f))
                return vstack([
                    text("Kaomoji", size=16, weight="bold"),
                    grid(rows, columns=2),
                ])
            """#),

        ClinkPanel(
            id: "panel-snippets", name: "Snippets", icon: "text.badge.plus",
            summary: "Quick canned phrases",
            source: """
            def view(state):
                snippets = [
                    "On my way!",
                    "Sounds good 👍",
                    "Let me check and get back to you.",
                    "Thanks so much!",
                    "Running 5 min late.",
                ]
                rows = []
                for s in snippets:
                    rows.append(button(s, insert=s))
                return vstack(rows, spacing=8)
            """),
    ]
}
