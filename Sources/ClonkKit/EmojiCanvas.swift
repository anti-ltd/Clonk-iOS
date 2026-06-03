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
    /// Persist a per-emoji skin-tone choice (base emoji → tone). The host writes
    /// it to the shared settings; we also keep `localTones` for instant feedback.
    private let onSetSkinTone: (String, SkinTone) -> Void

    @State private var controller: KeyboardController
    @State private var searching = false
    @State private var query = ""
    /// Skin-tone choices made this session, shown immediately while the host's
    /// persisted write propagates back. Overlaid on `settings.emojiSkinTones`.
    @State private var localTones: [String: SkinTone] = [:]
    /// The in-progress hold-to-pick interaction, if a tone-capable emoji is
    /// being held. Nil when idle.
    @State private var picking: TonePicking?
    /// Visible emoji cell frames in `.global` space, kept current so the hold
    /// gesture (which reports window coordinates) can map a touch to a cell.
    @State private var cellFrames: [String: CGRect] = [:]
    /// The grid viewport's frame in `.global` space — used to clamp the popup
    /// on-screen and to map a finger position to a swatch.
    @State private var gridFrame: CGRect = .zero
    @Environment(\.colorScheme) private var colorScheme

    /// A live "hold an emoji and slide to a skin tone" gesture. `centerX` is the
    /// bar's fixed on-screen centre (anchored at press so the current tone sits
    /// under the finger, then held steady while sliding); `tone` is the swatch
    /// currently under the finger.
    private struct TonePicking: Equatable {
        var base: String
        var centerX: CGFloat
        var tone: SkinTone
    }

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
        onRequestHeight: @escaping (CGFloat) -> Void = { _ in },
        onSetSkinTone: @escaping (String, SkinTone) -> Void = { _, _ in }
    ) {
        self.settings = settings
        _controller = State(initialValue: controller ?? KeyboardController())
        self.onInsert = onInsert
        self.onBackspace = onBackspace
        self.onAnyTap = onAnyTap
        self.onNextKeyboard = onNextKeyboard
        self.onRequestHeight = onRequestHeight
        self.onSetSkinTone = onSetSkinTone
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
    /// to the top. Cells render with the resolved skin tone; holding a tone-capable
    /// emoji raises the swatch bar, sliding moves the selection, and releasing
    /// commits it (the native press-slide-release flow, driven by `EmojiHoldGesture`).
    private func grid(_ emoji: [String], scrollTarget: String?) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                Color.clear.frame(height: 0).id("top")
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(emoji, id: \.self) { e in
                        EmojiCell(
                            glyph: glyph(for: e),
                            simulatedPressed: controller.pressedEmoji == e || picking?.base == e,
                            action: { onAnyTap(); onInsert(glyph(for: e)) }
                        )
                        .id(e)
                        // Publish each visible cell's on-screen frame so the hold
                        // gesture can resolve which emoji a touch landed on.
                        .background(GeometryReader { g in
                            Color.clear.preference(key: EmojiCellFramesKey.self,
                                                   value: [e: g.frame(in: .global)])
                        })
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
                // The hold recogniser (scoped to the grid container). A quick tap
                // never reaches the hold threshold, so it falls through to the
                // cell Button; a hold raises the swatch bar.
                .background(EmojiHoldGesture(onBegan: holdBegan,
                                             onChanged: holdMoved,
                                             onEnded: holdEnded))
            }
            // Freeze scrolling while picking so sliding moves the selection, not
            // the grid.
            .scrollDisabled(picking != nil)
            .background(GeometryReader { g in
                Color.clear.preference(key: EmojiGridFrameKey.self, value: g.frame(in: .global))
            })
            .onChange(of: scrollTarget) { _, e in
                guard let e else { return }
                withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(e, anchor: .center) }
            }
            .onChange(of: category) { _, _ in
                withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo("top", anchor: .top) }
            }
        }
        .onPreferenceChange(EmojiCellFramesKey.self) { cellFrames = $0 }
        .onPreferenceChange(EmojiGridFrameKey.self) { gridFrame = $0 }
        .overlay { tonePickerOverlay() }
    }

    // MARK: - Skin tones

    /// The tone to use for `base`: this session's pick, else the persisted
    /// per-emoji choice, else the global default.
    private func resolvedTone(_ base: String) -> SkinTone {
        localTones[base] ?? settings.skinTone(for: base)
    }

    /// The glyph to display/insert for `base` with its resolved tone applied.
    private func glyph(for base: String) -> String {
        guard EmojiSkinTone.supportsSkinTone(base) else { return base }
        return EmojiSkinTone.applied(resolvedTone(base), to: base)
    }

    // MARK: Hold-to-pick gesture

    /// Convert a gesture point (host-container local space) into SwiftUI `.global`
    /// space by offsetting by the grid's global origin — matches `cellFrames` and
    /// `gridFrame`, which are both captured in `.global`.
    private func toGlobal(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x + gridFrame.minX, y: p.y + gridFrame.minY)
    }

    /// The base emoji whose visible frame contains the global point `p`.
    private func emoji(at p: CGPoint) -> String? {
        cellFrames.first { $0.value.contains(p) }?.key
    }

    /// The swatch the finger at global x `px` sits over, given the bar centred at
    /// `centerX`. Clamped to the swatch range.
    private func tone(forFingerX px: CGFloat, centerX: CGFloat) -> SkinTone {
        let left = centerX - SkinTonePicker.width / 2 + SkinTonePicker.hPadding
        let idx = Int((px - left) / SkinTonePicker.swatch)
        return SkinTone.allCases[max(0, min(SkinTone.allCases.count - 1, idx))]
    }

    /// Hold recognised: if it landed on a tone-capable emoji, raise the bar with
    /// its current tone under the finger.
    private func holdBegan(_ raw: CGPoint) {
        let p = toGlobal(raw)
        guard let base = emoji(at: p), EmojiSkinTone.supportsSkinTone(base),
              let cell = cellFrames[base] else { return }
        onAnyTap()
        let current = resolvedTone(base)
        let anchorIndex = SkinTone.allCases.firstIndex(of: current) ?? 0
        let centerX = SkinTonePicker.center(cellMidX: cell.midX, anchorIndex: anchorIndex, in: gridFrame)
        withAnimation(.snappy(duration: 0.16)) {
            picking = TonePicking(base: base, centerX: centerX, tone: current)
        }
    }

    /// Finger slid while holding: move the highlighted swatch to follow it.
    private func holdMoved(_ raw: CGPoint) {
        guard var pick = picking else { return }
        let t = tone(forFingerX: toGlobal(raw).x, centerX: pick.centerX)
        if t != pick.tone { onAnyTap() }
        pick.tone = t
        picking = pick
    }

    /// Released: commit the highlighted swatch — remember it, persist it, insert
    /// the toned glyph — and lower the bar.
    private func holdEnded(_ p: CGPoint) {
        guard let pick = picking else { return }
        let base = pick.base, tone = pick.tone
        localTones[base] = tone
        onSetSkinTone(base, tone)
        onInsert(EmojiSkinTone.applied(tone, to: base))
        withAnimation(.snappy(duration: 0.16)) { picking = nil }
    }

    /// The swatch bar, floating above the held cell and following the finger's
    /// selection. Purely visual — the hold gesture drives all interaction.
    @ViewBuilder private func tonePickerOverlay() -> some View {
        GeometryReader { geo in
            if let pick = picking, let cell = cellFrames[pick.base] {
                let origin = geo.frame(in: .global).origin
                let y = cell.minY - SkinTonePicker.height / 2 - 10
                SkinTonePicker(base: pick.base, highlighted: pick.tone, theme: theme)
                    .frame(width: SkinTonePicker.width, height: SkinTonePicker.height)
                    // Global → overlay-local.
                    .position(x: pick.centerX - origin.x, y: y - origin.y)
                    .transition(.scale(scale: 0.85, anchor: .bottom).combined(with: .opacity))
            }
        }
        .allowsHitTesting(false)
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
    let glyph: String
    var simulatedPressed: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(glyph)
                .font(.system(size: 30))
                .frame(maxWidth: .infinity, minHeight: 40)
                .scaleEffect(simulatedPressed ? 1.3 : 1)
                .animation(.interactiveSpring(response: 0.22, dampingFraction: 0.6), value: simulatedPressed)
                .contentShape(Rectangle())
        }
        .buttonStyle(EmojiBloomStyle())
        // Hold-to-pick is handled at the grid level by `EmojiHoldGesture`, which
        // suppresses this Button's tap once a hold is recognised — so a quick tap
        // inserts, a hold raises the swatch bar.
    }
}

/// The skin-tone swatch bar raised while holding an emoji: that emoji in neutral
/// + the five Fitzpatrick tones, with the `highlighted` swatch lifted to show the
/// current selection. Purely presentational — `EmojiHoldGesture` drives the
/// selection and commit. Styled like the key popups (glass on glass themes).
private struct SkinTonePicker: View {
    let base: String
    let highlighted: SkinTone
    let theme: Theme

    static let swatch: CGFloat = 44
    static let hPadding: CGFloat = 8
    static let width: CGFloat = swatch * CGFloat(SkinTone.allCases.count) + hPadding * 2
    static let height: CGFloat = 56

    /// The bar's centre x (in `.global`), placed so the swatch at `anchorIndex`
    /// (the emoji's current tone) sits directly above the held cell, then clamped
    /// so the whole bar stays on-screen.
    static func center(cellMidX: CGFloat, anchorIndex: Int, in grid: CGRect) -> CGFloat {
        // Offset of the anchor swatch's centre from the bar's left edge.
        let anchorOffset = hPadding + swatch * (CGFloat(anchorIndex) + 0.5)
        let desired = cellMidX - anchorOffset + width / 2
        guard grid.width > width else { return grid.midX }
        return min(max(desired, grid.minX + width / 2 + 6), grid.maxX - width / 2 - 6)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        HStack(spacing: 0) {
            ForEach(SkinTone.allCases) { tone in
                let on = tone == highlighted
                Text(EmojiSkinTone.applied(tone, to: base))
                    .font(.system(size: 28))
                    .scaleEffect(on ? 1.25 : 1)
                    .frame(width: Self.swatch, height: 44)
                    .background(
                        Circle()
                            .fill(theme.accent.color.opacity(on ? 0.35 : 0))
                            .padding(2)
                    )
                    .offset(y: on ? -2 : 0)
                    .animation(.snappy(duration: 0.14), value: on)
            }
        }
        .padding(.horizontal, Self.hPadding)
        .frame(height: Self.height)
        .background {
            if theme.material == .liquidGlass, #available(iOS 26.0, *) {
                Color.clear.glassEffect(.regular.tint(theme.keyFill.color), in: shape)
            } else {
                shape.fill(theme.keyFill.color)
            }
        }
        .overlay(shape.strokeBorder(theme.specialKeyText.color.opacity(0.12)))
        .shadow(color: .black.opacity(0.28), radius: 10, y: 5)
    }
}

/// Publishes each visible emoji cell's on-screen (`.global`) frame, keyed by base
/// emoji, so the hold gesture can map a window-space touch back to an emoji and
/// the swatch bar can anchor above it.
struct EmojiCellFramesKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// Publishes the grid viewport's `.global` frame — used to clamp the swatch bar
/// on-screen and to map a finger position to a swatch.
struct EmojiGridFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

// MARK: - Hold-to-pick gesture bridge
//
// The skin-tone interaction is "press an emoji, the swatch bar rises, slide to a
// tone, release to commit" — one continuous touch. A `UILongPressGestureRecognizer`
// is the exact primitive: it fires `.began` after a short still hold, streams
// `.changed` as the finger slides, and `.ended` on release. SwiftUI's own
// gestures are unreliable inside a keyboard extension (the same reason the letter
// keyboard and emoji tab bar route touches through bare UIViews), so we bridge to
// UIKit here.
//
// The recogniser is attached to the scroll view's container (an ancestor of the
// cell Buttons) so it sees every touch without blocking taps: a quick tap never
// reaches the hold threshold and flows to the Button, while `cancelsTouchesInView`
// cancels that Button once a hold is recognised — so committing a tone never also
// fires a plain insert. Touch points are read in window space to match SwiftUI's
// `.global` cell frames.

private struct EmojiHoldGesture: UIViewRepresentable {
    var onBegan: (CGPoint) -> Void
    var onChanged: (CGPoint) -> Void
    var onEnded: (CGPoint) -> Void

    func makeUIView(context: Context) -> HoldHostView {
        let v = HoldHostView()
        v.coordinator = context.coordinator
        return v
    }

    func updateUIView(_ uiView: HoldHostView, context: Context) {
        context.coordinator.onBegan = onBegan
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
    }

    static func dismantleUIView(_ uiView: HoldHostView, coordinator: Coordinator) {
        if let lp = coordinator.recognizer { lp.view?.removeGestureRecognizer(lp) }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// A zero-size, non-interactive handle that attaches the hold recogniser once
    /// it lands in a window — to the scroll container (an ancestor of the cell
    /// Buttons) so the gesture spans the grid without blocking taps or scrolling
    /// the rest of the app.
    @MainActor
    final class HoldHostView: UIView {
        weak var coordinator: Coordinator?

        init() {
            super.init(frame: .zero)
            backgroundColor = .clear
            isUserInteractionEnabled = false
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil, let coordinator, coordinator.recognizer == nil else { return }
            var scrollView: UIScrollView?
            var node: UIView? = self
            while let n = node {
                if let s = n as? UIScrollView { scrollView = s; break }
                node = n.superview
            }
            guard let host = scrollView?.superview ?? window else { return }
            let lp = UILongPressGestureRecognizer(target: coordinator,
                                                  action: #selector(Coordinator.handle(_:)))
            lp.minimumPressDuration = 0.28
            lp.cancelsTouchesInView = true
            lp.delegate = coordinator
            host.addGestureRecognizer(lp)
            coordinator.recognizer = lp
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var recognizer: UILongPressGestureRecognizer?
        var onBegan: (CGPoint) -> Void = { _ in }
        var onChanged: (CGPoint) -> Void = { _ in }
        var onEnded: (CGPoint) -> Void = { _ in }

        @objc func handle(_ g: UILongPressGestureRecognizer) {
            // Report in the host (grid-container) local space. The SwiftUI side
            // adds the grid's `.global` origin to land in `.global` exactly —
            // independent of any window / safe-area offset.
            let p = g.location(in: g.view)
            switch g.state {
            case .began:                    onBegan(p)
            case .changed:                  onChanged(p)
            case .ended, .cancelled, .failed: onEnded(p)
            default:                        break
            }
        }

        // Coexist with the scroll view's pan: the hold only recognises after a
        // still ~0.28s, by which point a real scroll would already have moved and
        // failed it. Scrolling is frozen by the view once a pick is in progress.
        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
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

