/**
 `EmojiCanvas`: the emoji keyboard — a sibling of `KeyboardCanvas` that reads
 the same `KeyboardSettings`. Hosts the scrollable emoji grid, category tab bar,
 skin-tone picker, and delete tile.
 

 Module: emoji · Target: ClinkKit
 Learn: docs/05-emoji.md
 */
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

    /// The cross-axis grid tracks, each pinned to the measured square `side` (not
    /// `.flexible()`): a horizontal `ScrollView` hugs its content on the vertical
    /// axis, so flexible rows would collapse to glyph height and leave the bottom
    /// of the keyboard empty. Fixed tracks make the grid span the full cross extent
    /// for any row/column count.
    private func gridItems(_ metrics: CellMetrics) -> [GridItem] {
        let count = settings.emojiScrollDirection == .horizontal
            ? settings.emojiRowCount
            : settings.emojiColumnCount
        return Array(repeating: GridItem(.fixed(metrics.side), spacing: settings.emojiCellSpacing),
                     count: max(1, count))
    }

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
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
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
                        withAnimation(Motion.emojiSearchToggle.animation) { searching = false }
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
                        withAnimation(Motion.emojiSearchToggle.animation) { searching = true }
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
    @ViewBuilder private func cells(_ emoji: [String], metrics: CellMetrics) -> some View {
        ForEach(emoji, id: \.self) { e in
            EmojiCell(
                glyph: displayGlyph(for: e),
                simulatedPressed: controller.pressedEmoji == e,
                glyphSize: metrics.glyph,
                fixedWidth: metrics.side,
                fixedHeight: metrics.side,
                action: { insertFromTap(e) }
            )
            .id(e)
            .background(GeometryReader { g in
                Color.clear.preference(key: EmojiCellFramesKey.self,
                                       value: [e: g.frame(in: .global)])
            })
        }
    }

    /// Cell sizing for the current axis + count: the square side a cell occupies
    /// on the scroll axis and the glyph point size that fits inside it.
    private struct CellMetrics { var side: CGFloat; var glyph: CGFloat }

    /// Fit `count` cells across the fixed cross-axis extent (`cross`), accounting
    /// for the user's inter-cell spacing and the 6pt grid edge padding, then size
    /// the glyph to the user's fraction of that square so more rows/columns (or a
    /// wider gap) shrink emoji cleanly instead of overlapping.
    private func cellMetrics(cross: CGFloat) -> CellMetrics {
        let horizontal = settings.emojiScrollDirection == .horizontal
        let count = max(1, horizontal ? settings.emojiRowCount : settings.emojiColumnCount)
        // Layout square: shrinks with spacing so the cells still tile the row.
        let usable = cross - 12 - settings.emojiCellSpacing * CGFloat(count - 1)
        let side = max(16, usable / CGFloat(count))
        // Glyph size keys off a spacing-INDEPENDENT reference cell (padding only),
        // so dragging the spacing slider never resizes the emoji — it only changes
        // the gaps between them.
        let refSide = max(16, (cross - 12) / CGFloat(count))
        return CellMetrics(side: side, glyph: refSide * settings.emojiGlyphScale)
    }

    private func grid(_ emoji: [String], scrollTarget: String?) -> some View {
        GeometryReader { geo in
            let horizontal = settings.emojiScrollDirection == .horizontal
            let metrics = cellMetrics(cross: horizontal ? geo.size.height : geo.size.width)
            gridBody(emoji, scrollTarget: scrollTarget, metrics: metrics)
        }
    }

    private func gridBody(_ emoji: [String], scrollTarget: String?, metrics: CellMetrics) -> some View {
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
                        LazyHGrid(rows: gridItems(metrics), spacing: settings.emojiCellSpacing) { cells(emoji, metrics: metrics) }
                    } else {
                        // Rows wrap downward, then scroll down for more.
                        LazyVGrid(columns: gridItems(metrics), spacing: settings.emojiCellSpacing) { cells(emoji, metrics: metrics) }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
                .background(EmojiHoldGesture(onBegan: holdBegan,
                                             onChanged: holdMoved,
                                             onEnded: holdEnded,
                                             holdDelay: settings.emojiToneHoldDelay / 1000))
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
                withAnimation(Motion.emojiScroll.animation) { proxy.scrollTo(e, anchor: .center) }
            }
            .onChange(of: category) { _, _ in
                withAnimation(Motion.emojiScroll.animation) {
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
        // Gated on the motion profile: the glass droplet is the kind of
        // GPU-expensive layer that rests under power/thermal pressure.
        if let flash, let tint = emojiFlashTint, let cell = cellFrames[flash.emoji],
           MotionProfile.shared.allowsExpensiveEffects,
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
        withAnimation(Motion.skinTonePick.animation) {
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
        withAnimation(Motion.skinTonePick.animation) { picking = nil }
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
                SkinTonePicker(base: pick.base, highlighted: pick.tone, theme: theme,
                               cornerRadius: cornerRadius)
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
                    withAnimation(Motion.emojiSearchToggle.animation) { searching = false }
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

    private var cornerRadius: CGFloat { CGFloat(settings.keyCornerRadius) }

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
                       cornerRadius: cornerRadius,
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
                                        withAnimation(Motion.emojiTabSelect.animation) { category = idx }
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
                withAnimation(Motion.emojiTabScroll.animation) { proxy.scrollTo(c, anchor: .center) }
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
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
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
        .animation(Motion.emojiTabPress.animation, value: pressedTab)
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
                    .animation(Motion.emojiTabPress.animation, value: pressedTab)
                    .animation(Motion.emojiScroll.animation, value: category)
                    .position(x: f.midX, y: f.midY)
            }
        }
        .allowsHitTesting(false)
    }

    /// A tinted glass tile — solid fill off glass themes; shape follows theme rounding.
    @ViewBuilder private func tabGlass<S: InsettableShape>(tint: Color, in shape: S) -> some View {
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
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
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
