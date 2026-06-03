import SwiftUI

/// The Clonk emoji keyboard — a sibling of `KeyboardCanvas` that reads the very
/// same `KeyboardSettings` (theme, sound) so configuring once styles both.
///
/// Three layers, top to bottom: a **search field**, a **scrollable emoji grid**,
/// and a **category tab bar** (globe, tabs, backspace) styled like the letter
/// keyboard's special keys. Tapping search swaps the grid + tabs for a live
/// results grid over a real QWERTY (the shared `KeyboardCanvas`, wired to a local
/// query buffer rather than the document) — exactly the native search flow.
///
/// The cells are plain `Button`s, not gestures: a `Button` inside a `ScrollView`
/// defers to the scroll, so dragging the grid scrolls instead of firing an emoji
/// (the old `DragGesture(minimumDistance: 0)` claimed the touch on contact and
/// made scrolling impossible without inserting).
public struct EmojiCanvas: View {
    private let settings: KeyboardSettings
    private let onInsert: (String) -> Void
    private let onBackspace: () -> Void
    private let onAnyTap: () -> Void
    private let onNextKeyboard: (() -> Void)?
    /// Asks the host to resize the keyboard — search mode is taller (it shows a
    /// QWERTY). The host pins its height constraint to the value passed back.
    private let onRequestHeight: (CGFloat) -> Void

    @State private var controller: KeyboardController
    @State private var searching = false
    @State private var query = ""
    @Environment(\.colorScheme) private var colorScheme

    /// Selected category — proxied onto the controller so an external simulator
    /// can switch tabs. `nonmutating set` works because `controller` is a class.
    private var category: Int {
        get { controller.emojiCategory }
        nonmutating set { controller.emojiCategory = newValue }
    }

    public init(
        settings: KeyboardSettings,
        controller: KeyboardController? = nil,
        onInsert: @escaping (String) -> Void,
        onBackspace: @escaping () -> Void,
        onAnyTap: @escaping () -> Void = {},
        onNextKeyboard: (() -> Void)? = nil,
        onRequestHeight: @escaping (CGFloat) -> Void = { _ in }
    ) {
        self.settings = settings
        _controller = State(initialValue: controller ?? KeyboardController())
        self.onInsert = onInsert
        self.onBackspace = onBackspace
        self.onAnyTap = onAnyTap
        self.onNextKeyboard = onNextKeyboard
        self.onRequestHeight = onRequestHeight
    }

    private var theme: Theme { settings.resolvedTheme(dark: colorScheme == .dark) }

    public enum Metrics {
        public static let barHeight: CGFloat = 48
        public static let searchBarHeight: CGFloat = 44
        /// The results strip shown above the QWERTY while searching.
        public static let searchResultsHeight: CGFloat = 132
    }

    /// A trimmed-down keyboard config for the in-search QWERTY: no predictive bar
    /// and no number row, so the search keyboard stays compact.
    private static func searchKeyboardSettings(_ s: KeyboardSettings) -> KeyboardSettings {
        var s = s
        s.suggestionsEnabled = false
        s.showNumberRow = false
        return s
    }

    /// Match the letter keyboard's height so switching keyboards doesn't jump —
    /// the search field reuses the space the predictive bar would occupy.
    public static func preferredHeight(for settings: KeyboardSettings) -> CGFloat {
        KeyboardCanvas.preferredHeight(for: settings)
    }

    /// Taller layout while searching: search field + results strip + QWERTY.
    public static func searchingHeight(for settings: KeyboardSettings) -> CGFloat {
        Metrics.searchBarHeight
            + Metrics.searchResultsHeight
            + KeyboardCanvas.preferredHeight(for: searchKeyboardSettings(settings))
    }

    private let columns = [GridItem(.adaptive(minimum: 40), spacing: 4)]

    public var body: some View {
        VStack(spacing: 0) {
            searchField

            if searching {
                searchResults
                searchKeyboard
            } else {
                grid(EmojiData.categories[category].emoji, scrollTarget: controller.pressedEmoji)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                tabBar
            }
        }
        .background(Color.clear)
        .onChange(of: searching) { _, on in
            onRequestHeight(on ? Self.searchingHeight(for: settings)
                               : Self.preferredHeight(for: settings))
        }
    }

    // MARK: - Search field (always visible)

    private var searchField: some View {
        let shape = Capsule(style: .continuous)
        let content = HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.specialKeyText.color.opacity(0.6))
            if searching && !query.isEmpty {
                Text(query)
                    .font(.system(size: 16))
                    .foregroundStyle(theme.keyText.color)
                    .lineLimit(1)
            } else {
                Text("Search Emoji")
                    .font(.system(size: 16))
                    .foregroundStyle(theme.specialKeyText.color.opacity(0.5))
            }
            Spacer(minLength: 0)
            if searching {
                Button {
                    onAnyTap()
                    if query.isEmpty {
                        withAnimation(.snappy(duration: 0.28)) { searching = false }
                    } else {
                        query = ""
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(theme.specialKeyText.color.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .frame(height: 34)

        return Button {
            onAnyTap()
            if !searching { withAnimation(.snappy(duration: 0.28)) { searching = true } }
        } label: {
            Group {
                if theme.material == .liquidGlass, #available(iOS 26.0, *) {
                    content.glassEffect(.regular.tint(theme.specialKeyFill.color), in: shape)
                } else {
                    content.background(theme.specialKeyFill.color, in: shape)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .frame(height: Metrics.searchBarHeight)
    }

    // MARK: - Emoji grid

    /// A scrollable grid of emoji. `scrollTarget` keeps the showcase simulator's
    /// pressed emoji centred; a hidden top anchor lets a category switch snap back
    /// to the top.
    private func grid(_ emoji: [String], scrollTarget: String?) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                Color.clear.frame(height: 0).id("top")
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(emoji, id: \.self) { e in
                        EmojiCell(emoji: e, simulatedPressed: controller.pressedEmoji == e) {
                            onAnyTap()
                            onInsert(e)
                        }
                        .id(e)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
            }
            .onChange(of: scrollTarget) { _, e in
                guard let e else { return }
                withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(e, anchor: .center) }
            }
            .onChange(of: category) { _, _ in
                withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo("top", anchor: .top) }
            }
        }
    }

    // MARK: - Search mode

    @ViewBuilder private var searchResults: some View {
        let results = EmojiData.search(query)
        Group {
            if query.isEmpty {
                hint("Type to search emoji")
            } else if results.isEmpty {
                hint("No emoji for “\(query)”")
            } else {
                grid(results, scrollTarget: nil)
            }
        }
        .frame(height: Metrics.searchResultsHeight)
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15))
            .foregroundStyle(theme.specialKeyText.color.opacity(0.5))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The shared letter keyboard, retargeted: keystrokes edit the local `query`
    /// instead of the document. Return dismisses search.
    private var searchKeyboard: some View {
        KeyboardCanvas(
            settings: Self.searchKeyboardSettings(settings),
            onInsert: { s in
                if s == "\n" {
                    withAnimation(.snappy(duration: 0.28)) { searching = false }
                } else {
                    query += s
                }
            },
            onBackspace: { if !query.isEmpty { query.removeLast() } },
            onAnyTap: onAnyTap,
            onNextKeyboard: onNextKeyboard
        )
        .frame(height: KeyboardCanvas.preferredHeight(for: Self.searchKeyboardSettings(settings)))
    }

    // MARK: - Category tab bar
    //
    // SwiftUI *draws* the bar (Liquid Glass tiles); a UIKit surface *handles the
    // taps*. SwiftUI's own Button/gesture taps are unreliable inside a keyboard
    // extension — the very reason the letter keyboard routes touches through
    // `KeyTouchRouter` rather than per-key gestures. The category tabs hit the
    // same wall (taps were silently dropped), so we mirror that split here: the
    // glass renders in SwiftUI, while an overlaid `EmojiBarTouchView` hit-tests
    // each touch to the tile under it and fires its action on touch-down.

    /// The ordered tiles: globe (extension only), the eight category tabs, then
    /// backspace. Rebuilt each pass so `selected` + the actions stay current; the
    /// touch surface resolves a tapped index back through `barTiles`.
    private var barTiles: [BarTile] {
        var tiles: [BarTile] = []
        if onNextKeyboard != nil {
            tiles.append(BarTile(icon: "globe", role: .wide, selected: false))
        }
        for (idx, cat) in EmojiData.categories.enumerated() {
            tiles.append(BarTile(icon: cat.icon, role: .tab, selected: idx == category))
        }
        tiles.append(BarTile(icon: "delete.left", role: .wide, selected: false))
        return tiles
    }

    /// Fire the action for the tile at `index` (the touch surface's hit result).
    private func activateTile(_ index: Int) {
        onAnyTap()
        let hasGlobe = onNextKeyboard != nil
        let lead = hasGlobe ? 1 : 0
        if hasGlobe, index == 0 { onNextKeyboard?(); return }
        if index == barTiles.count - 1 { onBackspace(); return }
        let cat = index - lead
        guard cat >= 0, cat < EmojiData.categories.count else { return }
        withAnimation(.snappy(duration: 0.22)) { category = cat }
    }

    private var tabBar: some View {
        let tiles = barTiles
        return tabBarVisual(tiles)
            // The UIKit tap surface, sized to the bar, mapping each touch to the
            // tile beneath it. Sits on top of the (decorative) glass.
            .overlayPreferenceValue(EmojiBarFrameKey.self) { anchors in
                GeometryReader { proxy in
                    EmojiBarTouchSurface(
                        frames: anchors.mapValues { proxy[$0] },
                        onHit: { activateTile($0) })
                }
            }
            .padding(.horizontal, 6)
            .frame(height: Metrics.barHeight)
    }

    @ViewBuilder private func tabBarVisual(_ tiles: [BarTile]) -> some View {
        let row = HStack(spacing: 6) {
            ForEach(Array(tiles.enumerated()), id: \.offset) { idx, tile in
                tabTile(tile)
                    .frame(maxWidth: tile.role == .wide ? 46 : .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    // Publish this tile's full-height frame for the touch surface.
                    .anchorPreference(key: EmojiBarFrameKey.self, value: .bounds) { [idx: $0] }
            }
        }
        if theme.material == .liquidGlass, #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 6) { row }
        } else {
            row
        }
    }

    /// One bar tile's glass surface. Selected category tiles glow with the accent;
    /// the rest take a faint glass tint matching the letter keyboard's special keys.
    @ViewBuilder private func tabTile(_ tile: BarTile) -> some View {
        let shape = Capsule(style: .continuous)
        let icon = Image(systemName: tile.icon)
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(tile.selected ? Color.white : theme.specialKeyText.color)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        let body = Group {
            if theme.material == .liquidGlass, #available(iOS 26.0, *) {
                let tint = tile.selected ? theme.accent.color : theme.specialKeyFill.color
                icon.glassEffect(.regular.tint(tint).interactive(), in: shape)
            } else {
                icon.background(tile.selected ? theme.accent.color : theme.specialKeyFill.color, in: shape)
            }
        }
        body
            .frame(height: 38)
            .frame(maxHeight: .infinity)   // glass pill centred in the taller tap cell
            .animation(.snappy(duration: 0.22), value: tile.selected)
    }
}

/// A bar tile's appearance. The action is resolved by index at tap time (see
/// `activateTile`), so this stays a cheap, value-type description.
private struct BarTile {
    enum Role { case tab, wide }   // wide = fixed-width globe / backspace
    let icon: String
    let role: Role
    let selected: Bool
}

// MARK: - UIKit tap surface for the bar
//
// Mirrors the letter keyboard's `MultiTouchSurface`: SwiftUI publishes each
// tile's frame, and this bare UIView hit-tests a touch to the nearest tile and
// fires on touch-down — reliable where SwiftUI's own button taps are not.

struct EmojiBarFrameKey: PreferenceKey {
    static let defaultValue: [Int: Anchor<CGRect>] = [:]
    static func reduce(value: inout [Int: Anchor<CGRect>], nextValue: () -> [Int: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

@MainActor
private final class EmojiBarTouchView: UIView {
    var frames: [Int: CGRect] = [:]
    var onHit: (Int) -> Void = { _ in }

    init() {
        super.init(frame: .zero)
        backgroundColor = .clear
        isMultipleTouchEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        let p = t.location(in: self)
        var best: Int?
        var bestDist = CGFloat.greatestFiniteMagnitude
        for (id, f) in frames {
            if f.contains(p) { onHit(id); return }
            let dx = p.x - f.midX, dy = p.y - f.midY
            let d = dx * dx + dy * dy
            if d < bestDist { bestDist = d; best = id }
        }
        if let best { onHit(best) }
    }
}

private struct EmojiBarTouchSurface: UIViewRepresentable {
    let frames: [Int: CGRect]
    let onHit: (Int) -> Void

    func makeUIView(context: Context) -> EmojiBarTouchView {
        let v = EmojiBarTouchView()
        v.frames = frames
        v.onHit = onHit
        return v
    }

    func updateUIView(_ uiView: EmojiBarTouchView, context: Context) {
        uiView.frames = frames
        uiView.onHit = onHit
    }
}

/// One tappable emoji. A `Button` (not a gesture) so it cooperates with the
/// enclosing `ScrollView` — drags scroll, taps insert. The press bloom comes from
/// the button style; the showcase simulator drives `simulatedPressed` to bloom a
/// cell with no finger on it.
private struct EmojiCell: View {
    let emoji: String
    var simulatedPressed: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(emoji)
                .font(.system(size: 30))
                .frame(maxWidth: .infinity, minHeight: 40)
                .scaleEffect(simulatedPressed ? 1.3 : 1)
                .animation(.interactiveSpring(response: 0.22, dampingFraction: 0.6), value: simulatedPressed)
                .contentShape(Rectangle())
        }
        .buttonStyle(EmojiBloomStyle())
    }
}

/// Blooms an emoji while the finger is down, springs back on release.
private struct EmojiBloomStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 1.3 : 1)
            .animation(.interactiveSpring(response: 0.22, dampingFraction: 0.6),
                       value: configuration.isPressed)
    }
}

