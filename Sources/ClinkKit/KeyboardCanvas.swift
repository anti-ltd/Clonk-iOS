import SwiftUI

/// The Clink keyboard, as a pure SwiftUI view. Lives in ClinkKit so that the
/// keyboard *extension* renders it live (wired to the document proxy + sound)
/// and the container *app* renders the very same view as a true-to-life
/// preview — there is no second, drifting "preview" implementation.
///
/// The canvas owns transient UI state (shift, which symbol plane is showing)
/// and reports only two document-affecting actions back to its host —
/// `onInsert` and `onBackspace` — plus `onAnyTap` (fired on every key-down so
/// the host can clink + haptic) and an optional `onNextKeyboard` (the globe
/// key; the app preview passes nil to hide it).
public struct KeyboardCanvas: View {
    private let settings: KeyboardSettings
    private let onInsert: (String) -> Void
    private let onBackspace: () -> Void
    private let onAnyTap: () -> Void
    private let onNextKeyboard: (() -> Void)?
    private let onSuggestion: (String) -> Void
    /// Fired when the user taps an emoji chip in the bar — inserts that emoji
    /// (replacing the word being typed). Distinct from `onSuggestion` so it never
    /// gets the word+space treatment.
    private let onEmojiSuggestion: (String) -> Void
    /// Fired when the user taps their literal word to reject the pending
    /// auto-correction (the quoted "keep what I typed" chip).
    private let onCancelAutocorrect: () -> Void
    /// Fired while dragging the space bar — a signed character delta to move the
    /// cursor by (the native space-bar trackpad).
    private let onCursorMove: (Int) -> Void

    /// Live typing state (autocomplete suggestions). The extension feeds it;
    /// the in-app preview can pass sample words. Observed so the bar updates
    /// without rebuilding the keyboard.
    private var live: KeyboardLiveState

    public init(
        settings: KeyboardSettings,
        live: KeyboardLiveState = KeyboardLiveState(),
        controller: KeyboardController? = nil,
        onInsert: @escaping (String) -> Void,
        onBackspace: @escaping () -> Void,
        onAnyTap: @escaping () -> Void = {},
        onNextKeyboard: (() -> Void)? = nil,
        onSuggestion: @escaping (String) -> Void = { _ in },
        onEmojiSuggestion: @escaping (String) -> Void = { _ in },
        onCancelAutocorrect: @escaping () -> Void = {},
        onCursorMove: @escaping (Int) -> Void = { _ in }
    ) {
        self.settings = settings
        self.live = live
        // Use the injected controller (the showcase simulator drives a shared
        // one) or spin up a private one for ordinary finger-driven use.
        _controller = State(initialValue: controller ?? KeyboardController())
        self.onInsert = onInsert
        self.onBackspace = onBackspace
        self.onAnyTap = onAnyTap
        self.onNextKeyboard = onNextKeyboard
        self.onSuggestion = onSuggestion
        self.onEmojiSuggestion = onEmojiSuggestion
        self.onCancelAutocorrect = onCancelAutocorrect
        self.onCursorMove = onCursorMove
    }

    private typealias Plane = KeyboardController.Plane
    private typealias Shift = KeyboardController.Shift

    /// Transient keyboard state (plane / shift / simulated press). Held as a
    /// reference type so it can be shared with an external typing simulator.
    @State private var controller: KeyboardController

    /// Routes raw multitouch from a single UIKit surface to the keys, so fast
    /// overlapping presses register independently (see `KeyTouchRouter`). Each
    /// `KeyView` reads its pressed / warp state back out of this.
    @State private var touch = KeyTouchRouter()

    // Proxy the canvas's existing `plane` / `shift` reads & writes onto the
    // controller, so the rest of the view is untouched. `nonmutating set` works
    // because `controller` is a class — mutating it doesn't mutate the struct.
    private var plane: Plane {
        get { controller.plane }
        nonmutating set { controller.plane = newValue }
    }
    private var shift: Shift {
        get { controller.shift }
        nonmutating set { controller.shift = newValue }
    }

    /// The system appearance, so a "match system" setting can flip the theme
    /// live between its light and dark choice. In the extension this tracks the
    /// host app's appearance; in the app preview it tracks the app's.
    @Environment(\.colorScheme) private var colorScheme

    private var theme: Theme { settings.resolvedTheme(dark: colorScheme == .dark) }

    /// Shared vertical metrics — also used by the extension to size the keyboard
    /// to its content (no dead space above / below the keys).
    public enum Metrics {
        public static let vPadding: CGFloat = 4
        public static let suggestionBarHeight: CGFloat = 44
        /// The default row height, used when a settings value isn't supplied.
        public static let defaultRowHeight: CGFloat = 46
    }

    /// The exact content height for a given configuration, so the host can pin
    /// the keyboard to it instead of guessing and centering.
    public static func preferredHeight(for settings: KeyboardSettings) -> CGFloat {
        let key = CGFloat(settings.keyHeight)
        var rows = settings.layout.rows.count + 1   // letter rows + bottom row
        // The number row carries its own (possibly reduced) height; every other
        // row is a full key tall.
        var h = CGFloat(rows) * key
        if settings.showNumberRow {
            rows += 1
            h += key * CGFloat(settings.numberRowHeightScale)
        }
        h += CGFloat(rows - 1) * CGFloat(settings.rowSpacing) + Metrics.vPadding * 2
        if settings.suggestionsEnabled { h += Metrics.suggestionBarHeight }
        return h
    }

    public var body: some View {
        VStack(spacing: 0) {
            if settings.suggestionsEnabled {
                SuggestionBar(suggestions: live.suggestions, autocorrection: live.autocorrection,
                              emoji: live.emojiSuggestions, theme: theme,
                              onTap: onSuggestion, onKeepTyped: onCancelAutocorrect,
                              onEmoji: onEmojiSuggestion)
                    .frame(height: Metrics.suggestionBarHeight)
            }
            keys
                .padding(.vertical, Metrics.vPadding)
                // Fill the remaining height so rows divide it evenly — no gap.
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // A single multitouch surface over the whole key region. It owns
                // every touch (so simultaneous presses register independently),
                // hit-tests each to the nearest key from the published frames, and
                // drives `touch`. Sits only over the keys — the suggestion bar's
                // buttons keep their own taps. The glyph/popup overlays above are
                // hit-test-transparent, so touches fall straight through to here.
                .overlayPreferenceValue(KeyFrameKey.self) { anchors in
                    GeometryReader { proxy in
                        MultiTouchSurface(
                            router: touch,
                            frames: anchors.mapValues { proxy[$0] },
                            resolveSpec: { currentKeySpecs()[$0] },
                            onPressDown: onAnyTap,
                            lingerDuration: settings.keyPressLinger)
                    }
                }
        }
        // Transparent backdrop: the keyboard blends with whatever sits behind it
        // — iOS's own keyboard surface in the extension, the preview's backdrop
        // in-app. Only the keys carry colour (their fills), so the keyboard reads
        // as floating keys rather than an opaque slab that fights the system.
        .background(Color.clear)
        // Glyph layer: every key's letter, drawn ON TOP of the glass container so
        // the morph (which blends a bloomed key into its neighbours) can't drag
        // the glyph off-centre. Each glyph blooms in place with its key.
        .overlayPreferenceValue(KeyGlyphKey.self) { glyphs in
            GeometryReader { proxy in
                ForEach(glyphs) { g in
                    glyphLabel(g)
                        .scaleEffect(x: g.scaleX, y: g.scaleY, anchor: .center)
                        .offset(x: g.offsetX)
                        .position(x: proxy[g.anchor].midX, y: proxy[g.anchor].midY)
                        .animation(.interactiveSpring(response: 0.26, dampingFraction: 0.6), value: g.scaleX)
                        .animation(.interactiveSpring(response: 0.28, dampingFraction: 0.72), value: g.offsetX)
                }
            }
            .allowsHitTesting(false)
        }
        // Single popup layer above every key — its shape follows the chosen style.
        .overlayPreferenceValue(KeyPopupKey.self) { popup in
            GeometryReader { proxy in
                if let popup {
                    popup_view(popup.glyph, keyRect: proxy[popup.anchor], bounds: proxy.size)
                }
            }
            .allowsHitTesting(false)
        }
    }

    /// One key's glyph for the on-top glyph layer (text or animated symbol).
    @ViewBuilder private func glyphLabel(_ g: KeyGlyphInfo) -> some View {
        Group {
            if g.isSystem {
                Image(systemName: g.glyph)
                    .font(.system(size: 18, weight: .medium))
                    // Animate symbol swaps both ways — e.g. the return glyph
                    // tracking the host field (return ⇄ go ⇄ send …).
                    .contentTransition(.symbolEffect(.replace))
                    // Bounce on each held-delete repeat (no-op elsewhere).
                    .symbolEffect(.bounce, value: g.deleteTick)
                    // Pin identity to the symbol name. A press re-renders the
                    // same identity (name unchanged) → the replace transition
                    // has nothing to cross-fade, so it can't mis-fire and drop
                    // the glyph (the intermittent delete-icon vanish). A real
                    // name swap changes identity and still animates below.
                    .id(g.glyph)
                    .animation(.snappy(duration: 0.25), value: g.glyph)
            } else {
                Text(g.glyph)
                    .font(.system(size: g.fontSize ?? (g.multiChar ? 16 : 22), weight: .regular))
            }
        }
        .foregroundStyle(g.color)
        .opacity(g.hidden ? 0 : 1)
    }

    /// Corner radius shared by the popup chrome — tracks the key roundness, a
    /// touch tighter so the larger popup doesn't read as rounder than the keys.
    private var popupCorner: CGFloat { max(CGFloat(settings.keyCornerRadius) - 2, 0) }

    @ViewBuilder private func popup_view(_ glyph: String, keyRect: CGRect, bounds: CGSize) -> some View {
        switch settings.keyPopupStyle {
        case .floating:
            positioned(tilePopup(glyph, width: 48, height: 56, fontSize: 30),
                       height: 56, centerY: keyRect.minY - 30, midX: keyRect.midX, bounds: bounds)
        case .balloon:
            balloonPopup(glyph, keyRect: keyRect, bounds: bounds)
        }
    }

    /// Place a popup, clamping it inside the keyboard so the top row's bubble is
    /// never cut off by the keyboard's top edge (an extension can't draw past it).
    private func positioned<V: View>(_ content: V, height: CGFloat,
                                     centerY: CGFloat, midX: CGFloat, bounds: CGSize) -> some View {
        let clamped = max(centerY, height / 2 + 2)
        return content.position(x: midX, y: clamped)
    }

    /// A rounded-rectangle popup (the floating style).
    private func tilePopup(_ glyph: String, width: CGFloat, height: CGFloat, fontSize: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: popupCorner, style: .continuous)
        return Text(glyph)
            .font(.system(size: fontSize, weight: .regular))
            .foregroundStyle(theme.keyText.color)
            .frame(width: width, height: height)
            .modifier(PopupChrome(shape: shape, theme: theme,
                                  glass: theme.material == .liquidGlass && settings.liquidGlassPopup))
    }

    /// A balloon drawn as one continuous shape over the whole pressed key: the
    /// bulb swells up out of the key, sharing its width / corner radius / accent
    /// tint, so there is no seam between popup and key. The magnified glyph rides
    /// in the bulb; the key's own footprint is covered by the balloon's foot. The
    /// bulb is bottom-anchored to the key (so it always lines up) and rises above
    /// — clamped so the top row's bulb doesn't poke past the keyboard's top edge.
    private func balloonPopup(_ glyph: String, keyRect: CGRect, bounds: CGSize) -> some View {
        // Wide rounded-rect head (~1.4× the key) on a short neck above the key.
        let headWidth = max(keyRect.width * 1.4, 48)
        let headHeight: CGFloat = 40
        let neck: CGFloat = 16
        let bulbRise = headHeight + neck                 // head + neck above the key top
        let top = max(2, keyRect.minY - bulbRise)
        let bottom = keyRect.maxY
        let totalHeight = bottom - top
        let shoulderY = keyRect.minY - top               // key's top edge within the frame
        let keyCorner = CGFloat(settings.keyCornerRadius)
        let shape = BalloonPopupShape(keyWidth: keyRect.width, headHeight: headHeight,
                                      shoulderY: shoulderY, topCorner: max(popupCorner, 14),
                                      bottomCorner: keyCorner)
        // Magnified glyph centred in the head.
        let glyphOffset = headHeight * 0.5 - totalHeight / 2
        // Full accent — the balloon covers the key, so it reads as the active key.
        let tint = theme.accent.color
        return BalloonPopup(glyph: glyph, bulbWidth: headWidth, totalHeight: totalHeight,
                            glyphOffset: glyphOffset, shape: shape, tint: tint, theme: theme,
                            glass: theme.material == .liquidGlass && settings.liquidGlassPopup)
            .position(x: keyRect.midX, y: (top + bottom) / 2)
    }

    /// The stack of rows, wrapped in a `GlassEffectContainer` for Liquid Glass
    /// themes (iOS 26+) so adjacent keys blend / morph correctly.
    @ViewBuilder private var keys: some View {
        // The keys occupy `keyWidthFraction` of the width; the rest splits into
        // symmetric side margins (atop a 4pt base inset so keys never touch the
        // edges). Measured here so the per-row geometry sees the reduced width.
        GeometryReader { geo in
            let sideInset = 4 + geo.size.width * (1 - CGFloat(settings.keyWidthFraction)) / 2
            rowStack(usableWidth: geo.size.width - sideInset * 2)
                .padding(.horizontal, sideInset)
        }
    }

    @ViewBuilder private func rowStack(usableWidth: CGFloat) -> some View {
        let rows = currentRows
        // ~half a key per side, so the home row's keys line up under the gaps of
        // the row above — the native keyboard's signature middle-row indent.
        let homeInset = usableWidth * CGFloat(settings.homeRowInsetAmount)
        let stack = VStack(spacing: CGFloat(settings.rowSpacing)) {
            if settings.showNumberRow, plane == .letters {
                row(KeyboardLayout.numberRows[0].map { plainKey($0, fontSize: CGFloat(settings.numberRowFontSize)) },
                    rowID: "num",
                    fixedHeight: CGFloat(settings.keyHeight) * CGFloat(settings.numberRowHeightScale))
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { idx, r in
                // The middle letter row (index 1 of a 3-row letter layout) is
                // the home row — the only one iOS indents.
                let isHomeRow = plane == .letters && rows.count == 3 && idx == 1
                row(r, rowID: "r\(idx)")
                    .padding(.horizontal, isHomeRow && settings.homeRowInset ? homeInset : 0)
            }
            bottomRow
        }
        // The glass *backgrounds* live in the container so a bloomed key blends
        // into its neighbours (the liquid merge). The glyphs are drawn in a
        // separate layer on top of this (see `glyphLayer`), out of the morph's
        // reach, so they stay centred.
        if theme.material == .liquidGlass, #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: CGFloat(settings.keySpacing)) { stack }
        } else {
            stack
        }
    }

    // MARK: - Plane → rows

    private var currentRows: [[KeySpec]] {
        switch plane {
        case .letters:
            let rows = settings.layout.rows
            return rows.enumerated().map { idx, keys in
                if idx == rows.count - 1 {
                    // Last letter row gets shift (lead) + backspace (trail).
                    return [shiftKey] + keys.map { letterKey($0) } + [backspaceKey]
                }
                return keys.map { letterKey($0) }
            }
        case .numbers:
            return symbolPlaneRows(KeyboardLayout.numberRows)
        case .symbols:
            return symbolPlaneRows(KeyboardLayout.symbolRows)
        }
    }

    private func symbolPlaneRows(_ source: [[String]]) -> [[KeySpec]] {
        source.enumerated().map { idx, keys in
            if idx == source.count - 1 {
                let switchGlyph = plane == .numbers ? "#+=" : "123"
                let toPlane: Plane = plane == .numbers ? .symbols : .numbers
                return [planeKey(switchGlyph, to: toPlane, weight: 1.4)]
                    + keys.map { plainKey($0) }
                    + [backspaceKey]
            }
            return keys.map { plainKey($0) }
        }
    }

    // MARK: - Bottom function row

    private var bottomRow: some View {
        row(bottomRowSpecs, rowID: "bottom")
    }

    private var bottomRowSpecs: [KeySpec] {
        var specs: [KeySpec] = []
        // 123 / ABC plane toggle.
        if plane == .letters {
            specs.append(planeKey("123", to: .numbers, weight: 1.4))
        } else {
            specs.append(planeKey("ABC", to: .letters, weight: 1.4))
        }
        // Globe — only in the extension (host passes a handler).
        if onNextKeyboard != nil {
            specs.append(.init(kind: .function, label: .system("globe"), weight: 1.2) {
                onNextKeyboard?()
            })
        }
        // Blank space bar, like the system keyboard — no "space" caption. Taps
        // type a space; press-and-drag slides the cursor (trackpad mode).
        specs.append(.init(kind: .character, label: .text(""), weight: settings.spaceWidth,
                           isSpace: true, onCursorMove: onCursorMove) {
            insert(" ")
        })
        // Return key follows the host field: a ⏎ glyph for a plain return, the
        // action word ("Go", "Search", "Send", …) otherwise — prominent (accent)
        // for action types, exactly like the system keyboard.
        let returnLabel: KeySpec.Label = live.returnKeySymbol.map { .system($0) }
            ?? .text(live.returnKeyTitle)
        specs.append(.init(kind: .function, label: returnLabel,
                           weight: 1.8, highlighted: live.returnKeyProminent) {
            onInsert("\n")
        })
        return specs
    }

    /// Every on-screen key, keyed by the same `"\(rowID)-\(index)"` ID the rows
    /// render with — so the multitouch router can resolve a hit-tested key back to
    /// its current spec (action + behaviour). Rebuilt on demand at touch time, so
    /// it always reflects the live plane / shift. Mirrors `rowStack` exactly.
    private func currentKeySpecs() -> [String: KeySpec] {
        var map: [String: KeySpec] = [:]
        func add(_ specs: [KeySpec], _ rowID: String) {
            for (i, s) in specs.enumerated() { map["\(rowID)-\(i)"] = s }
        }
        if settings.showNumberRow, plane == .letters {
            add(KeyboardLayout.numberRows[0].map { plainKey($0) }, "num")
        }
        for (idx, r) in currentRows.enumerated() { add(r, "r\(idx)") }
        add(bottomRowSpecs, "bottom")
        return map
    }

    // MARK: - Key specs

    private var shiftKey: KeySpec {
        let glyph = shift == .locked ? "capslock.fill" : (shift == .on ? "shift.fill" : "shift")
        return KeySpec(kind: .function, label: .system(glyph), weight: settings.funcKeyWidth,
                       highlighted: shift != .off, isShift: true) {
            switch shift {
            case .off:    shift = .on
            case .on:     shift = .locked
            case .locked: shift = .off
            }
        }
    }

    private var backspaceKey: KeySpec {
        KeySpec(kind: .function, label: .system("delete.left"), weight: settings.funcKeyWidth,
                isDestructive: true, isRepeatable: true) {
            onBackspace()
        }
    }

    private func letterKey(_ base: String) -> KeySpec {
        let shifted = shift != .off
        let glyph = shifted ? base.uppercased() : base
        return KeySpec(kind: .character, label: .text(glyph), weight: 1) {
            insert(glyph)
            if shift == .on { shift = .off }  // sticky shift releases after one key
        }
    }

    /// A symbol/number key with no shift behaviour.
    private func plainKey(_ glyph: String, fontSize: CGFloat? = nil) -> KeySpec {
        KeySpec(kind: .character, label: .text(glyph), weight: 1, fontSize: fontSize) {
            insert(glyph)
            // Pop back to letters after sentence punctuation, so a quick
            // "123 → , → keep typing" doesn't strand you on the symbols page.
            // Mirrors the one-shot-shift convention (act, then auto-revert).
            if settings.autoReturnToLetters,
               plane != .letters,
               Self.autoReturnPunctuation.contains(glyph) {
                plane = .letters
                // Drop you mid-sentence with the gap already typed, matching the
                // "punctuation → space → next word" rhythm. Opt-out via settings.
                // Limited to marks that always take a following space — quotes and
                // apostrophes don't (an opening quote hugs the next word).
                if settings.autoSpaceAfterReturn,
                   Self.autoSpacePunctuation.contains(glyph) {
                    insert(" ")
                }
            }
        }
    }

    /// Sentence/prose punctuation that returns the keyboard to letters when
    /// `autoReturnToLetters` is on. Deliberately excludes digits, math, currency,
    /// and brackets — there you usually keep entering symbols/numbers.
    private static let autoReturnPunctuation: Set<String> = [
        ".", ",", "?", "!", ";", ":",
        "'", "\u{2019}", "\u{2018}", "\"", "\u{201C}", "\u{201D}",
    ]

    /// Subset of `autoReturnPunctuation` that takes a following space when
    /// `autoSpaceAfterReturn` is on. Excludes quotes/apostrophes, which hug the
    /// next character rather than sitting before a gap.
    private static let autoSpacePunctuation: Set<String> = [
        ".", ",", "?", "!", ";", ":",
    ]

    private func planeKey(_ glyph: String, to target: Plane, weight: Double) -> KeySpec {
        KeySpec(kind: .function, label: .text(glyph), weight: weight) { plane = target }
    }

    private func insert(_ s: String) { onInsert(s) }

    // MARK: - Row renderer (proportional widths, à la EmbeddedKeyboard)

    @ViewBuilder
    private func row(_ specs: [KeySpec], rowID: String, fixedHeight: CGFloat? = nil) -> some View {
        let total = specs.map(\.weight).reduce(0, +)
        let spacing = CGFloat(settings.keySpacing)
        let content = GeometryReader { geo in
            let gaps = spacing * CGFloat(max(specs.count - 1, 0))
            let unit = max((geo.size.width - gaps) / CGFloat(total), 0)
            HStack(spacing: spacing) {
                ForEach(Array(specs.enumerated()), id: \.offset) { i, spec in
                    KeyView(spec: spec, theme: theme, cornerRadius: CGFloat(settings.keyCornerRadius),
                            popupEnabled: settings.keyPopupEnabled, pressWarp: settings.keyPressWarp,
                            keyID: "\(rowID)-\(i)",
                            simulatedPressed: controller.pressedKeyID == "\(rowID)-\(i)",
                            router: touch)
                        .frame(width: unit * CGFloat(spec.weight))
                }
            }
        }
        // A `fixedHeight` row (the number strip) takes exactly that; the rest leave
        // height flexible and divide the host evenly, so there's never a top/bottom
        // gap.
        if let fixedHeight {
            content.frame(height: fixedHeight)
        } else {
            content.frame(maxHeight: .infinity)
        }
    }
}

// MARK: - Key-popup plumbing
//
// The pressed-key bubble must float above the WHOLE keyboard — a per-key
// overlay escaping its bounds gets occluded by the keys in the row above. So
// each pressed character key publishes its glyph + bounds up via an anchor
// preference, and the canvas draws a single popup on top of everything.

struct KeyPopup {
    let glyph: String
    let anchor: Anchor<CGRect>
}

struct KeyPopupKey: PreferenceKey {
    static let defaultValue: KeyPopup? = nil
    static func reduce(value: inout KeyPopup?, nextValue: () -> KeyPopup?) {
        if let next = nextValue() { value = next }
    }
}

// MARK: - Glyph layer plumbing
//
// Each key publishes its glyph + bounds + bloom transform; the canvas draws them
// all in one layer ABOVE the glass container, so the container's morph (which
// blends a bloomed key into its neighbours) never displaces the letter.

struct KeyGlyphInfo: Identifiable, Equatable {
    let id: String
    let anchor: Anchor<CGRect>
    let isSystem: Bool
    let glyph: String
    let color: Color
    let scaleX: CGFloat
    let scaleY: CGFloat
    let offsetX: CGFloat
    let hidden: Bool
    let deleteTick: Int
    let multiChar: Bool
    /// Override glyph point size (number row); nil = default sizing.
    var fontSize: CGFloat? = nil
}

struct KeyGlyphKey: PreferenceKey {
    static let defaultValue: [KeyGlyphInfo] = []
    static func reduce(value: inout [KeyGlyphInfo], nextValue: () -> [KeyGlyphInfo]) {
        value.append(contentsOf: nextValue())
    }
}

/// Fills a popup's shape with the right material (Liquid Glass or an opaque
/// bubble) plus a drop shadow — shared by every popup style.
private struct PopupChrome<S: Shape>: ViewModifier {
    let shape: S
    let theme: Theme
    let glass: Bool
    /// When set, the popup takes this tint instead of the resting key fill — used
    /// by the balloon so it matches the pressed key it rises out of, blending into
    /// one continuous shape rather than reading as a detached blob.
    var tint: Color? = nil
    /// Override the drop shadow (opacity, radius, y). The balloon dips into the
    /// key, so it wants a faint shadow — a strong one paints a dark line across
    /// the key where the two shapes overlap. Defaults to the floating tile's.
    var shadow: (opacity: Double, radius: CGFloat, y: CGFloat) = (0.3, 6, 2)

    @ViewBuilder func body(content: Content) -> some View {
        if glass, #available(iOS 26.0, *) {
            content
                .glassEffect(tint.map { .regular.tint($0) } ?? .regular, in: shape)
                .shadow(color: .black.opacity(shadow.opacity), radius: shadow.radius, y: shadow.y)
        } else {
            let resting: Color = theme.material == .liquidGlass
                ? (theme.isDark ? Color(.sRGB, white: 0.16) : Color(.sRGB, white: 0.98))
                : theme.keyFill.color
            content
                .background(tint ?? resting, in: shape)
                .shadow(color: .black.opacity(shadow.opacity), radius: shadow.radius, y: shadow.y)
        }
    }
}

/// A key-popup outline drawn as ONE continuous shape spanning the whole pressed
/// key: a wide, flat-topped rounded-rectangle head (like the system keyboard's
/// magnifier) that eases down through a short concave neck to the key's width,
/// then runs straight to a rounded foot. Because the balloon *is* the key (it
/// covers it exactly, same width / corners / tint) there's no seam — the head
/// reads as the key broadening upward.
private struct BalloonPopupShape: Shape {
    let keyWidth: CGFloat
    /// Height of the rounded-rectangle head, before the neck begins.
    let headHeight: CGFloat
    /// Y of the key's top edge within the frame; below it the sides run straight
    /// down to the foot, above it is the head + neck.
    let shoulderY: CGFloat
    /// Roundness of the head's top corners.
    let topCorner: CGFloat
    /// Roundness of the foot's corners — the key's own corner radius.
    let bottomCorner: CGFloat

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let cx = w / 2
        let rt = min(topCorner, w / 2)
        let kHalf = min(keyWidth, w) / 2
        let leftK = cx - kHalf, rightK = cx + kHalf
        let br = min(bottomCorner, kHalf)
        let shoulder = min(max(shoulderY, rt + 8), h - br - 1)
        // Head's straight sides end a little above the shoulder, leaving a short
        // neck to ease in to the key width.
        let headB = min(headHeight, shoulder - 8)

        var p = Path()
        // Head — wide rounded-rectangle top.
        p.move(to: CGPoint(x: rt, y: 0))
        p.addLine(to: CGPoint(x: w - rt, y: 0))
        p.addQuadCurve(to: CGPoint(x: w, y: rt), control: CGPoint(x: w, y: 0))
        p.addLine(to: CGPoint(x: w, y: headB))
        // Short right neck — concave ease to the key's right edge (vertical
        // tangents at both ends so head and key sides flow in smoothly).
        p.addCurve(to: CGPoint(x: rightK, y: shoulder),
                   control1: CGPoint(x: w, y: shoulder),
                   control2: CGPoint(x: rightK, y: headB))
        // Straight down the key's right side to the foot.
        p.addLine(to: CGPoint(x: rightK, y: h - br))
        p.addQuadCurve(to: CGPoint(x: rightK - br, y: h), control: CGPoint(x: rightK, y: h))
        p.addLine(to: CGPoint(x: leftK + br, y: h))
        p.addQuadCurve(to: CGPoint(x: leftK, y: h - br), control: CGPoint(x: leftK, y: h))
        // Up the key's left side, then the mirrored neck back to the head.
        p.addLine(to: CGPoint(x: leftK, y: shoulder))
        p.addCurve(to: CGPoint(x: 0, y: headB),
                   control1: CGPoint(x: leftK, y: headB),
                   control2: CGPoint(x: 0, y: shoulder))
        p.addLine(to: CGPoint(x: 0, y: rt))
        p.addQuadCurve(to: CGPoint(x: rt, y: 0), control: CGPoint(x: 0, y: 0))
        p.closeSubpath()
        return p
    }
}

/// The balloon popup, with its "droplet" emerge: on press it springs up out of
/// the key — anchored at the foot, it stretches from a low squash to full height
/// and settles with a soft wobble, like a droplet drawn upward. A faint shadow
/// keeps the foot from painting a line across the key it overlaps.
private struct BalloonPopup: View {
    let glyph: String
    let bulbWidth: CGFloat
    let totalHeight: CGFloat
    /// Signed offset of the glyph from the frame centre, up into the bulb.
    let glyphOffset: CGFloat
    let shape: BalloonPopupShape
    let tint: Color
    let theme: Theme
    let glass: Bool

    @State private var emerged = false

    var body: some View {
        Text(glyph)
            .font(.system(size: 26, weight: .regular))
            .foregroundStyle(.white)
            .offset(y: glyphOffset)                   // lift glyph into the bulb
            .frame(width: bulbWidth, height: totalHeight)
            .modifier(PopupChrome(shape: shape, theme: theme, glass: glass,
                                  tint: tint, shadow: (0.22, 5, 1.5)))
            // Droplet emerge: scale up from the foot (the key), so the bulb is
            // drawn upward out of the key rather than fading in over it.
            .scaleEffect(x: emerged ? 1 : 0.9, y: emerged ? 1 : 0.5, anchor: .bottom)
            .opacity(emerged ? 1 : 0.5)
            .onAppear {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.62)) { emerged = true }
            }
    }
}

// MARK: - Key spec + view

/// A single key's appearance + behaviour. Value type so rows can be rebuilt
/// cheaply on every shift/plane change.
struct KeySpec: Identifiable {
    enum Kind { case character, function }
    enum Label { case text(String); case system(String) }

    let id = UUID()
    let kind: Kind
    let label: Label
    let weight: Double
    let highlighted: Bool
    /// Pressed state glows red instead of accent (the backspace key).
    let isDestructive: Bool
    /// The space bar — taps insert a space, press-and-drag moves the cursor.
    let isSpace: Bool
    /// Repeats `action` while held (the backspace key).
    let isRepeatable: Bool
    /// The shift key — it has its own glass + symbol animation, so it opts out
    /// of the generic press-warp bloom (which would double up and look janky).
    let isShift: Bool
    /// Called with a signed character delta while dragging the space bar.
    let onCursorMove: ((Int) -> Void)?
    /// Override glyph point size (the number row uses this); nil = default sizing.
    let fontSize: CGFloat?
    let action: () -> Void

    init(kind: Kind, label: Label, weight: Double, highlighted: Bool = false,
         isDestructive: Bool = false, isSpace: Bool = false, isRepeatable: Bool = false,
         isShift: Bool = false, onCursorMove: ((Int) -> Void)? = nil, fontSize: CGFloat? = nil,
         action: @escaping () -> Void) {
        self.kind = kind; self.label = label; self.weight = weight
        self.highlighted = highlighted; self.isDestructive = isDestructive
        self.isSpace = isSpace; self.isRepeatable = isRepeatable; self.isShift = isShift
        self.onCursorMove = onCursorMove; self.fontSize = fontSize; self.action = action
    }
}

/// Renders one key and detects key-*down* (via a zero-distance drag) so the
/// host clinks the instant the finger lands, then fires the action on release.
/// A one-shot, additive "tap registered" flash, replayed on every press.
///
/// Keyed to `KeyTouchRouter`'s per-key tap tick (which bumps on every
/// touch-down), so it fires even when the same key is re-pressed while it's
/// still in the pressed/linger state — the case where the bloom, sprung on
/// `isPressed`, can't re-animate. It briefly brightens the key over its own
/// shape and fades out; it changes no geometry, so it layers on top of the
/// bloom/popup without overriding either. Gated on the same `keyPressWarp`
/// switch as the bloom, so turning press visuals off silences it too.
private struct TapPulse: ViewModifier {
    let trigger: Int
    let shape: RoundedRectangle
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

private struct KeyView: View {
    let spec: KeySpec
    let theme: Theme
    let cornerRadius: CGFloat
    let popupEnabled: Bool
    /// Bloom/warp the key on press (optional, per `keyPressWarp`).
    let pressWarp: Bool
    /// Stable identity (row-col) so the glyph layer can track this key across
    /// rebuilds for its symbol animations.
    let keyID: String
    /// Driven by an external typing simulator (the device showcase) — shows the
    /// key as pressed even though no finger is on it.
    let simulatedPressed: Bool
    /// Shared multitouch state — this key's press / warp is read out of here,
    /// written by the single UIKit touch surface (see `KeyTouchRouter`).
    let router: KeyTouchRouter

    /// Pressed for any reason: a real finger (the router) or the simulator.
    private var isPressed: Bool { router.pressed.contains(keyID) || simulatedPressed }
    /// Space-bar trackpad drag state (only the space key reads these).
    private var cursorActive: Bool { router.spaceCursorActive }
    private var dragX: CGFloat { router.spaceDragX }
    /// Bumped on every auto-repeat delete to bounce the glyph as feedback.
    private var deleteTick: Int { router.deleteTick }

    /// iOS-style destructive red for the pressed backspace key.
    private static let destructiveTint = Color(.sRGB, red: 0.91, green: 0.22, blue: 0.18)
    /// How much the space bar shrinks while it's a cursor trackpad (held for the
    /// whole drag, sprung back only on release).
    private static let spaceDragScale: CGFloat = 0.9

    private var isCharacter: Bool { spec.kind == .character }

    /// Whether this key is currently showing its magnified popup — if so the key
    /// skips the press bloom (the popup is the press feedback). The key keeps its
    /// own glyph; the popup floats above it like the system keyboard.
    private var showsPopup: Bool {
        guard isPressed, popupEnabled, isCharacter else { return false }
        if case let .text(g) = spec.label, g.count == 1 { return true }
        return false
    }

    /// The colour a key glows when pressed — red for destructive (backspace),
    /// the theme accent otherwise.
    private var pressedTint: Color {
        spec.isDestructive ? Self.destructiveTint : theme.accent.color
    }

    private var fill: Color {
        if spec.highlighted { return theme.accent.color }
        return (isCharacter ? theme.keyFill : theme.specialKeyFill).color
    }
    private var textColor: Color {
        if spec.highlighted { return .white }
        return (isCharacter ? theme.keyText : theme.specialKeyText).color
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: cornerRadius, style: .continuous) }

    /// Liquid "warp": the space bar stretches toward the finger (and squashes
    /// vertically) while dragging the cursor; with `pressWarp` on, every key
    /// blooms a little on press. Both spring back on release.
    private var warp: (scaleX: CGFloat, scaleY: CGFloat, offset: CGFloat) {
        if spec.isSpace, cursorActive {
            let offset = max(min(dragX * 0.14, 28), -28)   // lean toward the finger
            // While the space bar is acting as a cursor trackpad it SHRINKS (both
            // width and height) and holds that smaller size for the whole drag —
            // a fixed scale, not one tied to how far you've dragged. So passing
            // back through the centre doesn't pop it to full size; it only springs
            // back on release (when `cursorActive` clears). Width now matches what
            // the height already did.
            return (Self.spaceDragScale, Self.spaceDragScale, offset)
        }
        // Visible bloom on press for the generic keys. The shift key opts out —
        // it has its own interactive-glass morph (see `glass` / `surface`).
        if pressWarp, isPressed, !showsPopup, !spec.isShift {
            // The space bar is much wider than a letter key, so the same scale
            // factor reads as a far bigger bloom. Tone it down for the space bar.
            let bloom: CGFloat = spec.isSpace ? 1.04 : 1.12
            return (bloom, bloom, 0)
        }
        return (1, 1, 0)
    }

    var body: some View {
        let w = warp
        // Generic keys: only the SURFACE blooms here (and morphs in the
        // container); the glyph is drawn on top by the canvas glyph layer.
        // The shift key draws its OWN glyph as glass content, so its interactive
        // glass can animate the glyph along with it (the caps-lock morph).
        return surface
            .scaleEffect(x: w.scaleX, y: w.scaleY, anchor: .center)
            .offset(x: w.offset)
            .animation(.interactiveSpring(response: 0.28, dampingFraction: 0.72), value: dragX)
            // Spring the generic press bloom; shift self-animates via its glass.
            .animation(pressWarp && !spec.isShift
                       ? .interactiveSpring(response: 0.26, dampingFraction: 0.6) : nil,
                       value: isPressed)
            // Additive "tap registered" flash. The bloom above is sprung on
            // `isPressed`, which never re-toggles when the SAME key is tapped
            // twice inside the linger window (the second `l` in "tell") — so the
            // re-press reads as dropped though the character did insert. This
            // pulse is keyed to the router's per-press tick, which bumps on every
            // landing, so each tap gets its own confirmation. It only flashes a
            // brief highlight over the key — it never touches the bloom geometry,
            // so it adds to the press effect rather than overriding it.
            .modifier(TapPulse(trigger: router.tapTick(keyID), shape: shape, enabled: pressWarp))
            // Publish the glyph for the on-top layer — except shift, which draws
            // its own so it can morph with its interactive glass.
            .anchorPreference(key: KeyGlyphKey.self, value: .bounds) { anchor in
                spec.isShift ? [] : [glyphInfo(anchor: anchor, warp: w)]
            }
            // Publish bounds + glyph to the popup layer while pressed.
            .anchorPreference(key: KeyPopupKey.self, value: .bounds) { anchor in
                // Only magnify single-glyph keys (letters, numbers, symbols) —
                // never multi-character keys like "space", which would just show
                // a truncated "S…" bubble.
                guard isPressed, popupEnabled, isCharacter,
                      case let .text(g) = spec.label, g.count == 1 else { return nil }
                return KeyPopup(glyph: g, anchor: anchor)
            }
            // Publish this key's frame so the multitouch surface can hit-test to
            // it. Every key (including shift / space / function) is touchable.
            .anchorPreference(key: KeyFrameKey.self, value: .bounds) { [keyID: $0] }
    }

    /// Describe this key's glyph for the canvas glyph layer.
    private func glyphInfo(anchor: Anchor<CGRect>,
                           warp: (scaleX: CGFloat, scaleY: CGFloat, offset: CGFloat)) -> KeyGlyphInfo {
        let isSystem: Bool
        let glyph: String
        let multiChar: Bool
        switch spec.label {
        case .text(let t):   isSystem = false; glyph = t; multiChar = t.count > 1
        case .system(let n): isSystem = true;  glyph = n; multiChar = false
        }
        return KeyGlyphInfo(
            id: keyID, anchor: anchor, isSystem: isSystem, glyph: glyph,
            color: isPressed ? .white : textColor,
            scaleX: warp.scaleX, scaleY: warp.scaleY, offsetX: warp.offset,
            // Only the backspace key bounces on auto-repeat; every other key
            // feeds 0 so a delete burst doesn't jiggle shift / globe / return.
            // The key keeps its own glyph even while popping — the popup sits
            // above it (à la the system keyboard), so the letter stays put.
            hidden: false, deleteTick: spec.isRepeatable ? deleteTick : 0, multiChar: multiChar,
            fontSize: spec.fontSize)
    }

    /// The key's drawn surface: shift carries its own glyph (so its interactive
    /// glass morphs the glyph too); every other key is just the bare surface, its
    /// glyph painted by the canvas glyph layer.
    @ViewBuilder private var surface: some View {
        if spec.isShift {
            shiftSurface
        } else {
            keyBackground
        }
    }

    /// Just the key's surface (glass or solid fill). The glyph is drawn ON TOP by
    /// the canvas glyph layer, so it never rides along with the glass morph.
    @ViewBuilder private var keyBackground: some View {
        switch theme.material {
        case .liquidGlass:
            if #available(iOS 26.0, *) {
                Color.clear.glassEffect(glass, in: shape)
            } else {
                // Pre-26 fallback: system blur material + a faint theme tint.
                shape.fill(.ultraThinMaterial).overlay(shape.fill(glassFallbackTint))
            }
        case .solid:
            shape
                .fill(isPressed ? pressedTint.opacity(0.85) : fill)
                .shadow(color: .black.opacity(theme.isDark ? 0.4 : 0.18), radius: 0, y: 1)
        }
    }

    /// The shift key, with its glyph as the glass's content (so the interactive
    /// material animates the glyph during the caps-lock morph), plus the animated
    /// shift ⇄ caps-lock symbol swap.
    @ViewBuilder private var shiftSurface: some View {
        let content = shiftLabel
            .foregroundStyle(isPressed ? Color.white : textColor)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        switch theme.material {
        case .liquidGlass:
            if #available(iOS 26.0, *) {
                content.glassEffect(glass, in: shape)
            } else {
                content.background {
                    shape.fill(.ultraThinMaterial).overlay(shape.fill(glassFallbackTint))
                }
            }
        case .solid:
            content.background {
                shape
                    .fill(isPressed ? pressedTint.opacity(0.85) : fill)
                    .shadow(color: .black.opacity(theme.isDark ? 0.4 : 0.18), radius: 0, y: 1)
            }
        }
    }

    @ViewBuilder private var shiftLabel: some View {
        if case let .system(name) = spec.label {
            Image(systemName: name)
                .font(.system(size: 18, weight: .medium))
                .contentTransition(.symbolEffect(.replace))
                // The interactive glass lens re-renders this content on every
                // touch; pinning identity to the name keeps those press
                // re-renders from re-entering the replace transition and
                // dropping the glyph. Only a real shift ⇄ caps-lock swap
                // changes identity and cross-fades.
                .id(name)
                .animation(.snappy(duration: 0.25), value: name)
        }
    }

    /// Tint applied to a glass key: character keys take the key fill, function keys
    /// the function-key fill, pressed / latched keys glow with the accent. The
    /// theme fills are low-opacity by design (see the builder's hint), so they
    /// colour the glass without killing its translucency.
    private var glassTint: Color? {
        if isPressed { return pressedTint }
        if spec.highlighted { return theme.accent.color }
        return (isCharacter ? theme.keyFill : theme.specialKeyFill).color
    }

    @available(iOS 26.0, *)
    private var glass: Glass {
        // Generic keys: non-interactive — their press warp is our own centred
        // `scaleEffect`, and the material's interactive lens would shove the
        // glyph off-centre. The shift key DOES use interactive glass: it draws
        // its own glyph, so the lens morphs the glyph too — its signature
        // caps-lock animation.
        let base = spec.isShift ? Glass.regular.interactive() : Glass.regular
        return glassTint.map { base.tint($0) } ?? base
    }

    private var glassFallbackTint: Color {
        if isPressed { return pressedTint.opacity(0.85) }
        if spec.highlighted { return theme.accent.color.opacity(0.85) }
        return (isCharacter ? theme.keyFill : theme.specialKeyFill).color
    }
}

// MARK: - Suggestion bar

/// The autocomplete strip above the keys, à la the native iOS predictive bar.
/// When an auto-correction is pending it leads with the user's literal word in
/// quotes (tap to keep) and shows the fix as a highlighted "primary" chip that
/// `space` will apply — then fills the rest with predictions. With no pending
/// correction it's just the predictions. Empty slots hold space so the bar
/// always fills the top of the keyboard.
struct SuggestionBar: View {
    let suggestions: [String]
    let autocorrection: Autocorrection?
    /// Emoji matching the word being typed — rendered as plain chips on the right
    /// and inserted (replacing the word) only when tapped. Never space-applied.
    let emoji: [String]
    let theme: Theme
    let onTap: (String) -> Void
    let onKeepTyped: () -> Void
    let onEmoji: (String) -> Void

    private enum Kind { case keep, primary, normal, emoji }
    private struct Candidate: Identifiable {
        let id = UUID()
        let text: String
        let kind: Kind
    }

    private var candidates: [Candidate] {
        var words: [Candidate] = []
        if let c = autocorrection {
            words.append(Candidate(text: c.from, kind: .keep))
            words.append(Candidate(text: c.to, kind: .primary))
            for s in suggestions
            where s.caseInsensitiveCompare(c.to) != .orderedSame
                && s.caseInsensitiveCompare(c.from) != .orderedSame {
                words.append(Candidate(text: s, kind: .normal))
            }
        } else {
            for s in suggestions { words.append(Candidate(text: s, kind: .normal)) }
        }
        // Reserve the right end for emoji chips when there are any, so they're
        // never crowded out — always leaving at least one word slot.
        let emojiCands = emoji.prefix(2).map { Candidate(text: $0, kind: .emoji) }
        let wordSlots = max(1, 3 - emojiCands.count)
        return Array(words.prefix(wordSlots)) + emojiCands
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(candidates.enumerated()), id: \.element.id) { idx, cand in
                if idx > 0 { divider }
                chip(cand)
            }
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private func chip(_ c: Candidate) -> some View {
        Button {
            switch c.kind {
            case .keep:  onKeepTyped()
            case .emoji: onEmoji(c.text)
            default:     onTap(c.text)
            }
        } label: {
            chipLabel(c)
                .font(.system(size: 17))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private func chipLabel(_ c: Candidate) -> some View {
        switch c.kind {
        case .keep:
            // The literal typed word, quoted — tap to reject the correction.
            Text("“\(c.text)”")
                .foregroundStyle(theme.keyText.color.opacity(0.7))
        case .primary:
            // The correction `space` will apply — highlighted like iOS, and
            // matching the theme: a real glass pill on Liquid Glass, a tinted
            // capsule on solid.
            let pill = Text(c.text)
                .foregroundStyle(theme.keyText.color)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
            if theme.material == .liquidGlass, #available(iOS 26.0, *) {
                pill.glassEffect(.regular.tint(theme.accent.color.opacity(0.55)).interactive(),
                                 in: Capsule())
            } else {
                pill.background(theme.accent.color.opacity(0.22), in: Capsule())
            }
        case .normal:
            Text(c.text).foregroundStyle(theme.keyText.color)
        case .emoji:
            // A plain (non-primary) emoji chip — slightly larger so the glyph
            // reads, and tinted nothing so it never looks like the space-applied
            // correction.
            Text(c.text).font(.system(size: 24))
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(theme.keyText.color.opacity(0.15))
            .frame(width: 0.5)
            .padding(.vertical, 11)
    }
}
