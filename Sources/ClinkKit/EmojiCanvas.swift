import SwiftUI

/// The Clink emoji keyboard — a sibling of `KeyboardCanvas` that reads the very
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
    /// Return to the letter keyboard (the ABC tile). When the emoji keyboard is an
    /// internal mode of the merged keyboard, this just flips `showEmoji` back.
    private let onReturnToLetters: (() -> Void)?
    /// Report that a base emoji was just inserted, so the host can record it into
    /// `settings.recentEmoji` (the recents tab). Passed the neutral base glyph.
    private let onRecordRecent: (String) -> Void

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
    /// Drives the sliding accent highlight between category tabs.
    @Namespace private var tabSelection
    /// The category tab currently held down — drives its press bloom. Nil at rest.
    @State private var pressedTab: Int?
    /// When a hold-to-pick last committed an insert. UIKit still delivers a stray
    /// cell-`Button` tap on that same release (the long-press recogniser doesn't
    /// reliably cancel SwiftUI's own tap gesture), so the next tap right after a
    /// commit is swallowed — preventing the emoji from being inserted twice.
    @State private var holdCommitAt: Date?
    /// The in-flight press flash: which emoji fired and a tick to retrigger the
    /// morph even on a repeat tap. Nil at rest, so no glass layer is mounted.
    @State private var flash: EmojiFlash?
    @State private var flashTick = 0
    /// Clears `flash` after the morph completes, so the lone glass layer unmounts.
    @State private var flashClear: Task<Void, Never>?

    private struct EmojiFlash: Equatable { var emoji: String; var tick: Int }
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

    /// The categories shown right now: the static Unicode set, with a leading
    /// "Recently used" tab prepended when enabled and non-empty. Recents are base
    /// glyphs, so they render (and re-tone) exactly like any other category.
    private var displayCategories: [EmojiCategory] {
        guard settings.showRecentEmoji, !settings.recentEmoji.isEmpty else {
            return EmojiData.categories
        }
        let recents = EmojiCategory(id: "recents", icon: "clock", emoji: settings.recentEmoji)
        return [recents] + EmojiData.categories
    }

    /// `category` clamped into `displayCategories` — the recents tab appearing or
    /// vanishing shifts indices, so always index through this.
    private var safeCategory: Int {
        min(max(category, 0), displayCategories.count - 1)
    }

    public init(
        settings: KeyboardSettings,
        controller: KeyboardController? = nil,
        onInsert: @escaping (String) -> Void,
        onBackspace: @escaping () -> Void,
        onAnyTap: @escaping () -> Void = {},
        onNextKeyboard: (() -> Void)? = nil,
        onRequestHeight: @escaping (CGFloat) -> Void = { _ in },
        onSetSkinTone: @escaping (String, SkinTone) -> Void = { _, _ in },
        onReturnToLetters: (() -> Void)? = nil,
        onRecordRecent: @escaping (String) -> Void = { _ in }
    ) {
        self.settings = settings
        _controller = State(initialValue: controller ?? KeyboardController())
        self.onInsert = onInsert
        self.onBackspace = onBackspace
        self.onAnyTap = onAnyTap
        self.onNextKeyboard = onNextKeyboard
        self.onRequestHeight = onRequestHeight
        self.onSetSkinTone = onSetSkinTone
        self.onReturnToLetters = onReturnToLetters
        self.onRecordRecent = onRecordRecent
    }

    private var theme: Theme { settings.resolvedTheme(dark: colorScheme == .dark) }

    /// The tint for an emoji cell's press flash — a liquid-glass droplet that
    /// morphs in behind the tapped glyph as "which one fired" feedback. Nil off
    /// the glass themes (or pre-iOS 26), where the cell shows no flash.
    private var emojiFlashTint: Color? {
        if theme.material == .liquidGlass, #available(iOS 26.0, *) {
            return theme.accent.color
        }
        return nil
    }

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
                grid(displayCategories[safeCategory].emoji, scrollTarget: controller.pressedEmoji)
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

        let field = Group {
            if theme.material == .liquidGlass, #available(iOS 26.0, *) {
                content.glassEffect(.regular.tint(theme.specialKeyFill.color), in: shape)
            } else {
                content.background(theme.specialKeyFill.color, in: shape)
            }
        }

        // Tap *anywhere* on the field to begin searching. A UIKit touch surface
        // rather than a SwiftUI Button: standalone button taps are unreliable in
        // the keyboard extension (the same reason the grid and bar route touches
        // through bare UIViews). Only while idle — in search mode the trailing
        // clear button owns its own taps.
        return field
            .overlay {
                if !searching {
                    touchCatcher {
                        onAnyTap()
                        withAnimation(.snappy(duration: 0.28)) { searching = true }
                    }
                }
            }
            .padding(.horizontal, 8)
            .frame(height: Metrics.searchBarHeight)
    }

    // MARK: - Emoji grid

    /// A scrollable grid of emoji. `scrollTarget` keeps the showcase simulator's
    /// pressed emoji centred; a hidden top anchor lets a category switch snap back
    /// to the top. Cells render with the resolved skin tone; holding a tone-capable
    /// emoji raises the swatch bar, sliding moves the selection, and releasing
    /// commits it (the native press-slide-release flow, driven by `EmojiHoldGesture`).
    /// The emoji cells shared by both scroll axes — each publishes its on-screen
    /// frame so the hold gesture can resolve which emoji a touch landed on.
    @ViewBuilder private func cells(_ emoji: [String]) -> some View {
        ForEach(emoji, id: \.self) { e in
            EmojiCell(
                glyph: displayGlyph(for: e),
                simulatedPressed: controller.pressedEmoji == e || picking?.base == e,
                action: { insertFromTap(e) }
            )
            .id(e)
            .background(GeometryReader { g in
                Color.clear.preference(key: EmojiCellFramesKey.self,
                                       value: [e: g.frame(in: .global)])
            })
        }
    }

    private func grid(_ emoji: [String], scrollTarget: String?) -> some View {
        let horizontal = settings.emojiScrollDirection == .horizontal
        return ScrollViewReader { proxy in
            ScrollView(horizontal ? .horizontal : .vertical) {
                // Zero-size start anchor (works on either axis): a category switch
                // snaps the scroll back to here.
                Color.clear.frame(width: 0, height: 0).id("top")
                // The hold recogniser (scoped to the grid container). A quick tap
                // never reaches the hold threshold, so it falls through to the
                // cell Button; a hold raises the swatch bar.
                Group {
                    if horizontal {
                        // Columns fill top-to-bottom, then scroll sideways for more.
                        LazyHGrid(rows: columns, spacing: 4) { cells(emoji) }
                    } else {
                        // Rows wrap downward, then scroll down for more.
                        LazyVGrid(columns: columns, spacing: 4) { cells(emoji) }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
                .background(EmojiHoldGesture(onBegan: holdBegan,
                                             onChanged: holdMoved,
                                             onEnded: holdEnded))
            }
            // Freeze scrolling while picking so sliding moves the selection, not
            // the grid.
            .scrollDisabled(picking != nil)
            // Soft gutters at the scrolling edges so cells fade in/out rather than
            // hard-cutting against the search field and the tab bar.
            .mask(
                LinearGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.05),
                    .init(color: .black, location: 0.95),
                    .init(color: .clear, location: 1),
                ],
                startPoint: horizontal ? .leading : .top,
                endPoint: horizontal ? .trailing : .bottom)
            )
            .background(GeometryReader { g in
                Color.clear.preference(key: EmojiGridFrameKey.self, value: g.frame(in: .global))
            })
            .onChange(of: scrollTarget) { _, e in
                guard let e else { return }
                withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(e, anchor: .center) }
            }
            .onChange(of: category) { _, _ in
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo("top", anchor: horizontal ? .leading : .top)
                }
            }
        }
        .onPreferenceChange(EmojiCellFramesKey.self) { cellFrames = $0 }
        .onPreferenceChange(EmojiGridFrameKey.self) { gridFrame = $0 }
        .overlay { flashOverlay() }
        .overlay { tonePickerOverlay() }
    }

    /// The single glass press droplet, floated over the cell that last fired. Only
    /// mounted while `flash` is set (cleared shortly after the morph) so there's
    /// zero glass cost at rest — never one per cell.
    @ViewBuilder private func flashOverlay() -> some View {
        if let flash, let tint = emojiFlashTint, let cell = cellFrames[flash.emoji],
           #available(iOS 26.0, *) {
            GeometryReader { geo in
                let origin = geo.frame(in: .global).origin
                EmojiGlassFlashView(glyph: displayGlyph(for: flash.emoji), tint: tint, trigger: flash.tick)
                    .frame(width: cell.width, height: cell.height)
                    .position(x: cell.midX - origin.x, y: cell.midY - origin.y)
            }
            .allowsHitTesting(false)
        }
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

    /// Like `glyph(for:)`, but while holding an emoji its cell live-previews the
    /// tone currently under the finger — so the grid shows what a release commits.
    private func displayGlyph(for base: String) -> String {
        if let pick = picking, pick.base == base {
            return EmojiSkinTone.applied(pick.tone, to: base)
        }
        return glyph(for: base)
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
        onRecordRecent(base)
        holdCommitAt = Date()   // swallow the stray cell tap on this same release
        withAnimation(.snappy(duration: 0.16)) { picking = nil }
    }

    /// A cell tap fired. Insert the resolved glyph — unless it's the stray tap UIKit
    /// delivers right after a hold-to-pick commit, which we swallow (consume-once,
    /// time-bounded so a stale flag can't eat a later tap).
    private func insertFromTap(_ base: String) {
        if let at = holdCommitAt {
            holdCommitAt = nil
            if Date().timeIntervalSince(at) < 0.3 { return }
        }
        onAnyTap()
        onInsert(glyph(for: base))
        onRecordRecent(base)
        triggerFlash(base)
    }

    /// Fire the glass press flash over `base` (glass themes only). Bumps a tick so a
    /// repeat tap on the same emoji re-morphs, and schedules the layer to unmount.
    private func triggerFlash(_ base: String) {
        guard emojiFlashTint != nil else { return }
        flashTick &+= 1
        flash = EmojiFlash(emoji: base, tick: flashTick)
        flashClear?.cancel()
        flashClear = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(440))
            if !Task.isCancelled { flash = nil }
        }
    }

    /// The swatch bar, floating above the held cell and following the finger's
    /// selection. Purely visual — the hold gesture drives all interaction.
    @ViewBuilder private func tonePickerOverlay() -> some View {
        GeometryReader { geo in
            if let pick = picking, let cell = cellFrames[pick.base] {
                let origin = geo.frame(in: .global).origin
                let gap: CGFloat = 10
                // Prefer floating above the held cell. The bar may overlap the
                // search row, but it must stay below the keyboard's top edge or the
                // extension clips it — and the search field sits one row above the
                // grid, so the keyboard top is ~one search-row above the grid top.
                // For a top-row emoji there's no room above, so drop it below.
                let keyboardTop = gridFrame.minY - Metrics.searchBarHeight + 6
                let placeAbove = (cell.minY - SkinTonePicker.height - gap) >= keyboardTop
                let y = placeAbove
                    ? cell.minY - SkinTonePicker.height / 2 - gap
                    : cell.maxY + SkinTonePicker.height / 2 + gap
                SkinTonePicker(base: pick.base, highlighted: pick.tone, theme: theme)
                    .frame(width: SkinTonePicker.width, height: SkinTonePicker.height)
                    // Global → overlay-local.
                    .position(x: pick.centerX - origin.x, y: y - origin.y)
                    .transition(.scale(scale: 0.85, anchor: placeAbove ? .bottom : .top)
                        .combined(with: .opacity))
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
    // A horizontally scrollable strip of square (1:1) category tabs with a sliding
    // accent highlight, flanked by the fixed globe (extension only) and backspace
    // controls. The strip scrolls when the squares overflow; the flanking controls
    // never scroll and stay pinned.
    //
    // The tabs live in a `GlassEffectContainer` and bloom on press, so adjacent
    // tiles morph/merge as the finger lands and as the highlight slides — the same
    // liquid-glass deformation the letter keys do.
    //
    // Taps: the scrolling tabs are SwiftUI Buttons — reliable inside a ScrollView,
    // the same proven path as the emoji grid cells (a Button defers to the scroll,
    // so a drag scrolls and a tap selects) — while the fixed globe routes through a
    // UIKit touch surface and backspace through `DeleteTile`, since standalone
    // SwiftUI button taps are silently dropped in the keyboard extension.

    private var tabBar: some View {
        HStack(spacing: 8) {
            // ABC — return to the letter keyboard (merged-keyboard mode). Shown
            // only when the host wires it; falls back to the globe otherwise. The
            // "abc" glyph reads large at the icon default, so size it down a touch.
            if onReturnToLetters != nil {
                fixedTile(systemName: "abc", width: 44, fontSize: 13) { onAnyTap(); onReturnToLetters?() }
            }
            if onNextKeyboard != nil {
                fixedTile(systemName: "globe", width: 38) { onAnyTap(); onNextKeyboard?() }
            }
            categoryStrip
            // Backspace — pinned (never scrolls), twice as wide as it is tall, and
            // wired to the same hold-to-repeat behaviour as the letter keyboard.
            DeleteTile(theme: theme,
                       pressWarp: settings.keyPressWarp,
                       onBackspace: onBackspace,
                       onAnyTap: onAnyTap)
        }
        .padding(.horizontal, 6)
        .frame(height: Metrics.barHeight)
    }

    /// The scrolling category tabs. Each tab is a 1:1 square; the selected tab
    /// wears an accent highlight that glides between tabs via `matchedGeometryEffect`.
    ///
    /// Scrolling *and* tapping are handled by one UIKit surface riding inside the
    /// scroll content: it tells a drag (let the scroll view pan) from a tap
    /// (select), so the strip scrolls reliably where a SwiftUI Button would swallow
    /// the horizontal drag. The same surface drives each tile's press bloom.
    private var categoryStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                tabRow
                    .padding(.vertical, 5)
                    .padding(.horizontal, 2)
                    .overlayPreferenceValue(EmojiBarFrameKey.self) { anchors in
                        GeometryReader { geo in
                            let frames = anchors.mapValues { geo[$0] }
                            ZStack {
                                EmojiTabTapSurface(
                                    frames: frames,
                                    onPress: { pressedTab = $0 },
                                    onRelease: { pressedTab = nil },
                                    onCommit: { idx in
                                        onAnyTap()
                                        withAnimation(.snappy(duration: 0.26)) { category = idx }
                                    })
                                // Glyphs drawn last so they sit above both the glass
                                // and the tap surface (which is transparent + lets
                                // touches through the non-interactive glyphs).
                                tabGlyphLayer(frames: frames)
                            }
                        }
                    }
            }
            .frame(maxWidth: .infinity)
            // Fade the scroll edges instead of letting tabs hard-cut against the
            // ABC tile and the delete key — a soft gutter on both sides.
            .mask(
                LinearGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.05),
                    .init(color: .black, location: 0.95),
                    .init(color: .clear, location: 1),
                ], startPoint: .leading, endPoint: .trailing)
            )
            // Keep the active tab in view as it changes — whether tapped here or
            // driven externally (e.g. the showcase simulator).
            .onChange(of: category) { _, c in
                withAnimation(.snappy(duration: 0.24)) { proxy.scrollTo(c, anchor: .center) }
            }
        }
    }

    /// The row of category tiles, wrapped in a `GlassEffectContainer` on Liquid
    /// Glass themes so neighbouring tiles blend and morph as one blooms or the
    /// highlight slides past.
    @ViewBuilder private var tabRow: some View {
        let row = HStack(spacing: 6) {
            ForEach(displayCategories.indices, id: \.self) { idx in
                categoryTab(idx)
            }
        }
        if theme.material == .liquidGlass, #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 8) { row }
        } else {
            row
        }
    }

    /// One square (1:1) category tile — just the glass (the glyph rides in a
    /// separate top layer, see `tabGlyphLayer`). The selected tile carries the
    /// shared accent highlight (which slides over on selection); a held tile blooms
    /// so it morphs into its neighbours within the glass container.
    private func categoryTab(_ idx: Int) -> some View {
        let selected = idx == category
        let shape = Capsule(style: .continuous)
        return ZStack {
            // A faint glass base on every tile gives the container material to
            // morph between as the highlight passes.
            tabGlass(tint: theme.specialKeyFill.color, in: shape)
            if selected {
                tabGlass(tint: theme.accent.color, in: shape)
                    .matchedGeometryEffect(id: "tabHighlight", in: tabSelection)
            }
        }
        .frame(width: 38, height: 38)
        .scaleEffect(pressedTab == idx ? 1.18 : 1)
        .animation(.interactiveSpring(response: 0.26, dampingFraction: 0.6), value: pressedTab)
        .contentShape(shape)
        // Publish this tile's frame (in scroll-content space) for the tap surface
        // and the glyph layer.
        .anchorPreference(key: EmojiBarFrameKey.self, value: .bounds) { [idx: $0] }
        .id(idx)
    }

    /// The category glyphs, drawn ON TOP of the glass tiles and their container so
    /// the liquid glass can't frost them — the same separate-glyph-layer trick the
    /// letter keyboard uses to keep its key letters crisp. Each glyph sits over its
    /// tile's published frame and blooms / recolours in sync with the tile beneath.
    private func tabGlyphLayer(frames: [Int: CGRect]) -> some View {
        ForEach(displayCategories.indices, id: \.self) { idx in
            if let f = frames[idx] {
                Image(systemName: displayCategories[idx].icon)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(idx == category ? Color.white : theme.specialKeyText.color)
                    .scaleEffect(pressedTab == idx ? 1.18 : 1)
                    .animation(.interactiveSpring(response: 0.26, dampingFraction: 0.6), value: pressedTab)
                    .animation(.easeInOut(duration: 0.2), value: category)
                    .position(x: f.midX, y: f.midY)
            }
        }
        .allowsHitTesting(false)
    }

    /// A tinted glass capsule — a solid fill off the glass themes.
    @ViewBuilder private func tabGlass(tint: Color, in shape: Capsule) -> some View {
        if theme.material == .liquidGlass, #available(iOS 26.0, *) {
            Color.clear.glassEffect(.regular.tint(tint), in: shape)
        } else {
            shape.fill(tint)
        }
    }

    /// A fixed (non-scrolling) bar control — the globe / ABC. `width` sets the
    /// aspect against the 38pt height; `fontSize` sizes its glyph (ABC reads big at
    /// the icon default, so it passes a smaller size). Taps route through a UIKit
    /// surface for reliability.
    private func fixedTile(systemName: String, width: CGFloat, fontSize: CGFloat = 17,
                           action: @escaping () -> Void) -> some View {
        let shape = Capsule(style: .continuous)
        let label = Image(systemName: systemName)
            .font(.system(size: fontSize, weight: .medium))
            .foregroundStyle(theme.specialKeyText.color)
            .frame(width: width, height: 38)
        return Group {
            if theme.material == .liquidGlass, #available(iOS 26.0, *) {
                label.glassEffect(.regular.tint(theme.specialKeyFill.color), in: shape)
            } else {
                label.background(theme.specialKeyFill.color, in: shape)
            }
        }
        .overlay { touchCatcher(action) }
    }

    /// A full-bleed UIKit tap surface firing `action` on touch-down — reliable
    /// where SwiftUI's own button taps are dropped inside the keyboard extension.
    private func touchCatcher(_ action: @escaping () -> Void) -> some View {
        GeometryReader { proxy in
            EmojiBarTouchSurface(frames: [0: proxy.frame(in: .local)], onHit: { _ in action() })
        }
    }
}

// MARK: - UIKit tap surface for the bar
//
// Mirrors the letter keyboard's `MultiTouchSurface`: SwiftUI publishes each
// tile's frame, and this bare UIView hit-tests a touch to the nearest tile and
// fires on touch-down — reliable where SwiftUI's own button taps are not.

/// Publishes each category tile's frame (in scroll-content space) so the tab tap
/// surface can resolve which tile a touch landed on.
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

// MARK: - Scrollable tab tap surface
//
// Rides *inside* the horizontal scroll content (so its frames stay valid as the
// strip scrolls) and tells a tap from a drag: a quick touch-up with little
// movement selects the tile under it, while any real drag is left to the scroll
// view's pan (which cancels our touch). This is why the strip scrolls where a
// SwiftUI Button — which claims the horizontal drag — would not.

@MainActor
private final class EmojiTabTapView: UIView {
    var frames: [Int: CGRect] = [:]
    var onPress: (Int) -> Void = { _ in }
    var onRelease: () -> Void = {}
    var onCommit: (Int) -> Void = { _ in }

    private var startPoint: CGPoint = .zero
    private var moved = false
    private var pressedID: Int?

    init() {
        super.init(frame: .zero)
        backgroundColor = .clear
        isMultipleTouchEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func tile(at p: CGPoint) -> Int? {
        frames.first { $0.value.contains(p) }?.key
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let p = touches.first?.location(in: self) else { return }
        moved = false
        startPoint = p
        pressedID = tile(at: p)
        if let id = pressedID { onPress(id) }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !moved, let p = touches.first?.location(in: self) else { return }
        // Past the slop it's a scroll, not a tap — drop the press and let the
        // scroll view's pan take over.
        if abs(p.x - startPoint.x) > 10 || abs(p.y - startPoint.y) > 10 {
            moved = true
            pressedID = nil
            onRelease()
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if !moved, let id = pressedID { onCommit(id) }
        pressedID = nil
        onRelease()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        moved = true
        pressedID = nil
        onRelease()
    }
}

private struct EmojiTabTapSurface: UIViewRepresentable {
    let frames: [Int: CGRect]
    let onPress: (Int) -> Void
    let onRelease: () -> Void
    let onCommit: (Int) -> Void

    func makeUIView(context: Context) -> EmojiTabTapView {
        let v = EmojiTabTapView()
        apply(to: v)
        return v
    }

    func updateUIView(_ uiView: EmojiTabTapView, context: Context) { apply(to: uiView) }

    private func apply(to v: EmojiTabTapView) {
        v.frames = frames
        v.onPress = onPress
        v.onRelease = onRelease
        v.onCommit = onCommit
    }
}

// MARK: - Backspace tile (mirrors the letter keyboard's delete key)

/// The emoji bar's backspace, built to feel exactly like the letter keyboard's
/// delete key: tap to delete one, hold to auto-repeat with the same 450ms delay
/// and accelerating cadence, the glyph bouncing on each repeat, a destructive-red
/// press tint, the press bloom, and the additive tap pulse. A bare UIView reports
/// touch-down / -up (SwiftUI button taps are dropped in the extension); the repeat
/// is a cancellable Task, torn down on release.
private struct DeleteTile: View {
    let theme: Theme
    let pressWarp: Bool
    let onBackspace: () -> Void
    let onAnyTap: () -> Void

    /// iOS-style destructive red for the pressed backspace — matches the letter
    /// keyboard's delete key.
    private static let destructiveTint = Color(.sRGB, red: 0.91, green: 0.22, blue: 0.18)

    @State private var pressed = false
    @State private var tapTick = 0
    @State private var deleteTick = 0
    @State private var repeatTask: Task<Void, Never>?

    var body: some View {
        let shape = Capsule(style: .continuous)
        let tint = pressed ? Self.destructiveTint : theme.specialKeyFill.color
        let label = Image(systemName: "delete.left")
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(pressed ? Color.white : theme.specialKeyText.color)
            // Bounce on each held-delete repeat, just like the letter keyboard.
            .symbolEffect(.bounce, value: deleteTick)
            .frame(width: 76, height: 38)

        return Group {
            if theme.material == .liquidGlass, #available(iOS 26.0, *) {
                label.glassEffect(.regular.tint(tint), in: shape)
            } else {
                label.background(tint, in: shape)
            }
        }
        .scaleEffect(pressWarp && pressed ? 1.12 : 1)
        .animation(.interactiveSpring(response: 0.26, dampingFraction: 0.6), value: pressed)
        .modifier(EmojiTapPulse(trigger: tapTick, shape: shape, enabled: pressWarp))
        .overlay { HoldRepeatSurface(onDown: down, onUp: up) }
    }

    private func down() {
        onAnyTap()
        tapTick &+= 1
        pressed = true
        startRepeating()
    }

    private func up() {
        stopRepeating()
        pressed = false
    }

    /// Delete once now, wait out the hold delay, then auto-repeat with an
    /// accelerating cadence — the exact timing of `KeyTouchRouter.startRepeating`.
    private func startRepeating() {
        stopRepeating()
        repeatTask = Task { @MainActor in
            onBackspace()                                  // first delete now
            try? await Task.sleep(for: .milliseconds(450)) // hold delay
            var interval = 110
            while !Task.isCancelled {
                onAnyTap()                                 // clink on each repeat
                onBackspace()
                deleteTick &+= 1                           // bounce the glyph
                interval = max(40, interval - 6)           // accelerate
                try? await Task.sleep(for: .milliseconds(interval))
            }
        }
    }

    private func stopRepeating() {
        repeatTask?.cancel()
        repeatTask = nil
    }
}

/// An additive white flash played on each press — the emoji-bar twin of the
/// letter keyboard's `TapPulse`, generic over the tile shape.
private struct EmojiTapPulse<S: Shape>: ViewModifier {
    let trigger: Int
    let shape: S
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.keyframeAnimator(initialValue: 0.0, trigger: trigger) { view, flash in
                view.overlay {
                    shape.fill(.white)
                        .opacity(flash)
                        .blendMode(.plusLighter)
                        .allowsHitTesting(false)
                }
            } keyframes: { _ in
                KeyframeTrack {
                    CubicKeyframe(0.0, duration: 0.001)
                    CubicKeyframe(0.34, duration: 0.05)   // snap bright
                    CubicKeyframe(0.0, duration: 0.20)    // ease back out
                }
            }
        } else {
            content
        }
    }
}

/// A bare UIView reporting touch-down and touch-up (release or cancel) — drives
/// the backspace's press state and hold-to-repeat where SwiftUI button taps are
/// unreliable inside the keyboard extension.
private struct HoldRepeatSurface: UIViewRepresentable {
    let onDown: () -> Void
    let onUp: () -> Void

    func makeUIView(context: Context) -> HoldRepeatView {
        let v = HoldRepeatView()
        v.onDown = onDown
        v.onUp = onUp
        return v
    }

    func updateUIView(_ uiView: HoldRepeatView, context: Context) {
        uiView.onDown = onDown
        uiView.onUp = onUp
    }
}

@MainActor
private final class HoldRepeatView: UIView {
    var onDown: () -> Void = {}
    var onUp: () -> Void = {}

    init() {
        super.init(frame: .zero)
        backgroundColor = .clear
        isMultipleTouchEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) { onDown() }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { onUp() }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { onUp() }
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
        // inserts, a hold raises the swatch bar. The press flash is drawn once at
        // the grid level (see `flashOverlay`), never per-cell — a `glassEffect` on
        // every cell would be ruinously expensive in the extension.
    }
}

/// The glass press indicator: a single tinted liquid-glass droplet that morphs in
/// over the just-tapped emoji and settles away, using the same `.glassEffect`
/// material as the keys so it reads as the surface itself deforming. The tapped
/// glyph is redrawn crisp on top so the glass sits *behind* it. Exactly one of
/// these is ever mounted, and only while a flash is in flight.
@available(iOS 26.0, *)
private struct EmojiGlassFlashView: View {
    let glyph: String
    let tint: Color
    let trigger: Int

    /// Animated state: the droplet's scale (the morph) and its opacity (in/out).
    private struct Flash { var scale: CGFloat = 0.55; var opacity: Double = 0 }

    /// `keyframeAnimator` only fires when its trigger *changes while mounted*. This
    /// view is freshly mounted per flash (the overlay unmounts at rest), so the
    /// external `trigger` never changes within one lifetime — the morph would never
    /// play. Bumping a local tick on appear gives the animator the change it needs;
    /// also bumping on `trigger` re-morphs a repeat tap that lands before unmount.
    @State private var tick = 0

    var body: some View {
        let shape = Capsule(style: .continuous)
        ZStack {
            Color.clear.keyframeAnimator(initialValue: Flash(), trigger: tick) { _, f in
                Color.clear
                    .glassEffect(.regular.tint(tint), in: shape)
                    .scaleEffect(f.scale)
                    .opacity(f.opacity)
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    CubicKeyframe(0.55, duration: 0.001)
                    CubicKeyframe(1.08, duration: 0.15)   // morph out past full
                    CubicKeyframe(0.97, duration: 0.23)   // settle back in
                }
                KeyframeTrack(\.opacity) {
                    CubicKeyframe(0.0, duration: 0.001)
                    CubicKeyframe(0.85, duration: 0.06)   // bloom in
                    CubicKeyframe(0.0, duration: 0.32)    // ease away
                }
            }
            // The glyph, crisp on top of the glass droplet.
            Text(glyph).font(.system(size: 30))
        }
        .allowsHitTesting(false)
        .onAppear { tick &+= 1 }
        .onChange(of: trigger) { _, _ in tick &+= 1 }
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
        let swatchShape = RoundedRectangle(cornerRadius: 11, style: .continuous)
        let hlIndex = SkinTone.allCases.firstIndex(of: highlighted) ?? 0
        // Centre of the highlighted swatch, measured from the bar's left edge.
        let hlCenterX = Self.hPadding + Self.swatch * (CGFloat(hlIndex) + 0.5)
        let box = Self.swatch - 6

        // Swatches: a fixed-size row whose only variable is which one is picked.
        // Apple's emoji font renders the Fitzpatrick-modified glyphs with slightly
        // different metrics than the neutral base, so an unscaled row *looks* like a
        // jumble of sizes. To cut through that, the currently-picked swatch blows up
        // to one consistent large size — and stays there for the whole hold. It only
        // shrinks back when the finger lifts (the bar dismisses), never mid-slide, so
        // there's no flicker or shrink-as-you-go between tones.
        return HStack(spacing: 0) {
            ForEach(SkinTone.allCases) { tone in
                let isPicked = tone == highlighted
                Text(EmojiSkinTone.applied(tone, to: base))
                    .font(.system(size: 28))
                    .scaleEffect(isPicked ? 1.5 : 1, anchor: .center)
                    .zIndex(isPicked ? 1 : 0)
                    .frame(width: Self.swatch, height: Self.swatch)
            }
        }
        .animation(.snappy(duration: 0.16), value: highlighted)
        .padding(.horizontal, Self.hPadding)
        .frame(height: Self.height)
        // The selection highlight sits *behind* the swatches — positioned by exact
        // swatch maths so it's always perfectly centred and slides cleanly between
        // them (fully decoupled from the swatches, which never move) — so the chosen
        // emoji stays crisp and in front of the accent chip, not frosted under it.
        .background(alignment: .leading) {
            swatchShape
                .fill(theme.accent.color.opacity(0.3))
                .overlay(swatchShape.strokeBorder(theme.accent.color, lineWidth: 2.5))
                .frame(width: box, height: box)
                .offset(x: hlCenterX - box / 2)
                .animation(.snappy(duration: 0.16), value: highlighted)
        }
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

