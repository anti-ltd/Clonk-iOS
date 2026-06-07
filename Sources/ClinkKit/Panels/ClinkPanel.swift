/**
 `ClinkPanel`: a user-authored keyboard *panel* — a custom UI rendered inside the
 keyboard from a PyMini script (vs. `ClinkExtension`, which is a one-shot text
 action). The script defines `view(state)` (and optionally `initial()`); buttons
 drive an MVU loop (`set` updates state, `insert` types into the document). See
 `PanelRuntime`. Codable for App Group persistence and `.clinkpanel` sharing.
 */
import Foundation

public struct ClinkPanel: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var name: String
    public var icon: String
    public var summary: String
    /// PyMini source — must define `view(state)`; may define `initial()`.
    public var source: String
    public var enabled: Bool

    public init(
        id: String = "panel-\(UUID().uuidString.prefix(8))",
        name: String,
        icon: String = "square.grid.2x2",
        summary: String = "",
        source: String,
        enabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.summary = summary
        self.source = source
        self.enabled = enabled
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? "panel-\(UUID().uuidString.prefix(8))"
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Untitled"
        icon = try c.decodeIfPresent(String.self, forKey: .icon) ?? "square.grid.2x2"
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? ""
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }
}

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
            id: "panel-calc", name: "Calculator", icon: "plusminus",
            summary: "A worked-example calculator panel",
            source: """
            def initial():
                return {"acc": "", "op": "", "cur": "0"}

            def fmt(x):
                if x == int(x):
                    return str(int(x))
                return str(x)

            def calc(a, op, b):
                a = float(a)
                b = float(b)
                if op == "+": return fmt(a + b)
                if op == "-": return fmt(a - b)
                if op == "*": return fmt(a * b)
                if op == "/": return fmt(a / b) if b != 0 else "0"
                return fmt(b)

            def digit(state, d):
                cur = state["cur"]
                cur = d if cur == "0" else cur + d
                return {"cur": cur}

            def view(state):
                cur = state["cur"]
                # Compute the "=" result only when there's a pending operation.
                eqv = cur
                if state["acc"] != "" and state["op"] != "":
                    eqv = calc(state["acc"], state["op"], cur)
                rows = [["7","8","9","/"], ["4","5","6","*"],
                        ["1","2","3","-"], ["0",".","C","+"]]
                cells = []
                for r in rows:
                    for c in r:
                        if c in "0123456789.":
                            cells.append(button(c, set=digit(state, c)))
                        elif c == "C":
                            cells.append(button("C", set={"acc": "", "op": "", "cur": "0"}))
                        else:
                            cells.append(button(c, set={"acc": cur, "op": c, "cur": "0"}))
                return vstack([
                    text(cur, size=30, weight="bold"),
                    grid(cells, columns=4),
                    hstack([
                        button("=", set={"cur": eqv, "acc": "", "op": ""}, style="primary"),
                        button("Insert", insert=cur, style="primary"),
                    ]),
                ])
            """),

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
