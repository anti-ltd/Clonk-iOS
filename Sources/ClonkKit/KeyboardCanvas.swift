import SwiftUI

/// The Clonk keyboard, as a pure SwiftUI view. Lives in ClonkKit so that the
/// keyboard *extension* renders it live (wired to the document proxy + sound)
/// and the container *app* renders the very same view as a true-to-life
/// preview — there is no second, drifting "preview" implementation.
///
/// The canvas owns transient UI state (shift, which symbol plane is showing)
/// and reports only two document-affecting actions back to its host —
/// `onInsert` and `onBackspace` — plus `onAnyTap` (fired on every key-down so
/// the host can clonk + haptic) and an optional `onNextKeyboard` (the globe
/// key; the app preview passes nil to hide it).
public struct KeyboardCanvas: View {
    private let settings: KeyboardSettings
    private let onInsert: (String) -> Void
    private let onBackspace: () -> Void
    private let onAnyTap: () -> Void
    private let onNextKeyboard: (() -> Void)?
    private let onSuggestion: (String) -> Void
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
        self.onCancelAutocorrect = onCancelAutocorrect
        self.onCursorMove = onCursorMove
    }

    private typealias Plane = KeyboardController.Plane
    private typealias Shift = KeyboardController.Shift

    /// Transient keyboard state (plane / shift / simulated press). Held as a
    /// reference type so it can be shared with an external typing simulator.
    @State private var controller: KeyboardController

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
        var rows = settings.layout.rows.count + 1   // letter rows + bottom row
        if settings.showNumberRow { rows += 1 }
        var h = CGFloat(rows) * CGFloat(settings.keyHeight)
            + CGFloat(rows - 1) * CGFloat(settings.rowSpacing)
            + Metrics.vPadding * 2
        if settings.suggestionsEnabled { h += Metrics.suggestionBarHeight }
        return h
    }

    public var body: some View {
        VStack(spacing: 0) {
            if settings.suggestionsEnabled {
                SuggestionBar(suggestions: live.suggestions, autocorrection: live.autocorrection,
                              theme: theme, onTap: onSuggestion, onKeepTyped: onCancelAutocorrect)
                    .frame(height: Metrics.suggestionBarHeight)
            }
            keys
                .padding(.vertical, Metrics.vPadding)
                // Fill the remaining height so rows divide it evenly — no gap.
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                    // Animate symbol swaps both ways — e.g. shift ⇄ caps-lock.
                    .contentTransition(.symbolEffect(.replace))
                    .animation(.snappy(duration: 0.25), value: g.glyph)
                    // Bounce on each held-delete repeat (no-op elsewhere).
                    .symbolEffect(.bounce, value: g.deleteTick)
            } else {
                Text(g.glyph)
                    .font(.system(size: g.multiChar ? 16 : 22, weight: .regular))
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
        case .flat:
            positioned(tilePopup(glyph, width: max(keyRect.width, 40), height: 44, fontSize: 26),
                       height: 44, centerY: keyRect.minY - 18, midX: keyRect.midX, bounds: bounds)
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

    /// A rounded-rectangle popup (used by the floating + flat styles).
    private func tilePopup(_ glyph: String, width: CGFloat, height: CGFloat, fontSize: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: popupCorner, style: .continuous)
        return Text(glyph)
            .font(.system(size: fontSize, weight: .regular))
            .foregroundStyle(theme.keyText.color)
            .frame(width: width, height: height)
            .modifier(PopupChrome(shape: shape, theme: theme,
                                  glass: theme.material == .liquidGlass && settings.liquidGlassPopup))
    }

    /// A native-style balloon: a wide rounded bulb on a short neck that dips into
    /// the top of the pressed key. The glyph sits in the bulb. Clamped so the top
    /// row's bulb stays inside the keyboard rather than clipping at the top edge.
    private func balloonPopup(_ glyph: String, keyRect: CGRect, bounds: CGSize) -> some View {
        let bulbHeight: CGFloat = 48
        let neck = min(keyRect.height, 22)          // short neck, not the whole key
        let totalHeight = bulbHeight + neck
        let bulbWidth = max(keyRect.width * 1.3, 46)
        let shape = BalloonPopupShape(bulbHeight: bulbHeight, keyWidth: keyRect.width,
                                      cornerRadius: max(popupCorner, 10))
        // Neck dips ~8pt into the key's top; clamp so the bulb never clips.
        let desiredCenterY = keyRect.minY + 8 - totalHeight / 2
        let centerY = max(desiredCenterY, totalHeight / 2 + 2)
        return Text(glyph)
            .font(.system(size: 26, weight: .regular))
            .foregroundStyle(theme.keyText.color)
            .offset(y: -neck / 2)                    // lift glyph into the bulb
            .frame(width: bulbWidth, height: totalHeight)
            .modifier(PopupChrome(shape: shape, theme: theme,
                                  glass: theme.material == .liquidGlass && settings.liquidGlassPopup))
            .position(x: keyRect.midX, y: centerY)
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
                row(KeyboardLayout.numberRows[0].map { plainKey($0) }, rowID: "num")
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
        specs.append(.init(kind: .character, label: .text(""), weight: 5,
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
        return row(specs, rowID: "bottom")
    }

    // MARK: - Key specs

    private var shiftKey: KeySpec {
        let glyph = shift == .locked ? "capslock.fill" : (shift == .on ? "shift.fill" : "shift")
        return KeySpec(kind: .function, label: .system(glyph), weight: 1.4,
                       highlighted: shift != .off, isShift: true) {
            switch shift {
            case .off:    shift = .on
            case .on:     shift = .locked
            case .locked: shift = .off
            }
        }
    }

    private var backspaceKey: KeySpec {
        KeySpec(kind: .function, label: .system("delete.left"), weight: 1.4,
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
    private func plainKey(_ glyph: String) -> KeySpec {
        KeySpec(kind: .character, label: .text(glyph), weight: 1) { insert(glyph) }
    }

    private func planeKey(_ glyph: String, to target: Plane, weight: Double) -> KeySpec {
        KeySpec(kind: .function, label: .text(glyph), weight: weight) { plane = target }
    }

    private func insert(_ s: String) { onInsert(s) }

    // MARK: - Row renderer (proportional widths, à la EmbeddedKeyboard)

    private func row(_ specs: [KeySpec], rowID: String) -> some View {
        let total = specs.map(\.weight).reduce(0, +)
        let spacing = CGFloat(settings.keySpacing)
        return GeometryReader { geo in
            let gaps = spacing * CGFloat(max(specs.count - 1, 0))
            let unit = max((geo.size.width - gaps) / CGFloat(total), 0)
            HStack(spacing: spacing) {
                ForEach(Array(specs.enumerated()), id: \.offset) { i, spec in
                    KeyView(spec: spec, theme: theme, cornerRadius: CGFloat(settings.keyCornerRadius),
                            popupEnabled: settings.keyPopupEnabled, pressWarp: settings.keyPressWarp,
                            keyID: "\(rowID)-\(i)",
                            simulatedPressed: controller.pressedKeyID == "\(rowID)-\(i)",
                            onPressDown: onAnyTap)
                        .frame(width: unit * CGFloat(spec.weight))
                }
            }
        }
        // Rows divide the host's height evenly — no fixed per-row height, so
        // there's never a top/bottom gap.
        .frame(maxHeight: .infinity)
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

    @ViewBuilder func body(content: Content) -> some View {
        if glass, #available(iOS 26.0, *) {
            content
                .glassEffect(.regular, in: shape)
                .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
        } else {
            let fill: Color = theme.material == .liquidGlass
                ? (theme.isDark ? Color(.sRGB, white: 0.16) : Color(.sRGB, white: 0.98))
                : theme.keyFill.color
            content
                .background(fill, in: shape)
                .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
        }
    }
}

/// A native-style key-popup outline: a wide rounded bulb on top that necks down
/// (concave sides) to `keyWidth` at the bottom, so it reads as rising out of the
/// pressed key. Drawn in a rect whose bottom edge aligns with the key.
private struct BalloonPopupShape: Shape {
    let bulbHeight: CGFloat
    let keyWidth: CGFloat
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let r = min(cornerRadius, w / 2)
        let bulbH = min(bulbHeight, h)
        let kw = min(keyWidth, w)
        let leftB = (w - kw) / 2
        let rightB = (w + kw) / 2

        var p = Path()
        // Bulb top, with rounded top corners.
        p.move(to: CGPoint(x: r, y: 0))
        p.addLine(to: CGPoint(x: w - r, y: 0))
        p.addQuadCurve(to: CGPoint(x: w, y: r), control: CGPoint(x: w, y: 0))
        p.addLine(to: CGPoint(x: w, y: bulbH))
        // Right neck — concave taper down to the key's right edge.
        p.addCurve(to: CGPoint(x: rightB, y: h),
                   control1: CGPoint(x: w, y: h),
                   control2: CGPoint(x: rightB, y: bulbH))
        // Bottom edge (key width).
        p.addLine(to: CGPoint(x: leftB, y: h))
        // Left neck — mirror of the right.
        p.addCurve(to: CGPoint(x: 0, y: bulbH),
                   control1: CGPoint(x: leftB, y: bulbH),
                   control2: CGPoint(x: 0, y: h))
        p.addLine(to: CGPoint(x: 0, y: r))
        p.addQuadCurve(to: CGPoint(x: r, y: 0), control: CGPoint(x: 0, y: 0))
        p.closeSubpath()
        return p
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
    let action: () -> Void

    init(kind: Kind, label: Label, weight: Double, highlighted: Bool = false,
         isDestructive: Bool = false, isSpace: Bool = false, isRepeatable: Bool = false,
         isShift: Bool = false, onCursorMove: ((Int) -> Void)? = nil, action: @escaping () -> Void) {
        self.kind = kind; self.label = label; self.weight = weight
        self.highlighted = highlighted; self.isDestructive = isDestructive
        self.isSpace = isSpace; self.isRepeatable = isRepeatable; self.isShift = isShift
        self.onCursorMove = onCursorMove; self.action = action
    }
}

/// Renders one key and detects key-*down* (via a zero-distance drag) so the
/// host clonks the instant the finger lands, then fires the action on release.
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
    let onPressDown: () -> Void

    @State private var pressed = false

    /// Pressed for any reason: a real finger (`pressed`) or the simulator.
    private var isPressed: Bool { pressed || simulatedPressed }
    /// Space-bar trackpad drag state.
    @State private var cursorActive = false
    @State private var cursorSteps = 0
    /// Live horizontal drag offset while sliding the cursor — drives the glass
    /// "warp" of the space bar. Zero when not dragging (so it springs back).
    @State private var dragX: CGFloat = 0
    /// Held-key auto-repeat loop (the backspace key).
    @State private var repeatTask: Task<Void, Never>?
    /// Bumped on every auto-repeat delete to bounce the glyph as feedback.
    @State private var deleteTick = 0

    /// iOS-style destructive red for the pressed backspace key.
    private static let destructiveTint = Color(.sRGB, red: 0.91, green: 0.22, blue: 0.18)
    /// Points of horizontal drag per one character of cursor movement.
    private static let cursorStride: CGFloat = 10

    private var isCharacter: Bool { spec.kind == .character }

    /// Whether this key is currently showing its magnified popup — if so the
    /// key hides its own glyph (the popup carries it) and skips the press bloom,
    /// so the letter isn't drawn twice (key + popup) and looking off-centre.
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
            let s = min(abs(dragX) / 260, 0.16)            // 0…16% stretch
            let offset = max(min(dragX * 0.14, 28), -28)   // lean toward the finger
            // Height stays squashed for the whole drag (not just off-centre), so
            // it doesn't pop back to full height when you pass through the middle.
            return (1 + s, 0.9, offset)
        }
        // Visible bloom on press for the generic keys. The shift key opts out —
        // it has its own interactive-glass morph (see `glass` / `surface`).
        if pressWarp, isPressed, !showsPopup, !spec.isShift {
            return (1.12, 1.12, 0)
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
            .contentShape(Rectangle())
            .gesture(activeGesture)
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
            hidden: showsPopup, deleteTick: deleteTick, multiChar: multiChar)
    }

    private var activeGesture: AnyGesture<Void> {
        if spec.isSpace { return AnyGesture(spaceGesture.map { _ in () }) }
        if spec.isRepeatable { return AnyGesture(repeatGesture.map { _ in () }) }
        return AnyGesture(keyGesture.map { _ in () })
    }

    /// A held key (backspace) that fires once on touch-down, then auto-repeats
    /// with an initial delay and acceleration — hold to delete many characters.
    private var repeatGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                if !pressed { pressed = true; startRepeating() }
            }
            .onEnded { _ in pressed = false; stopRepeating() }
    }

    private func startRepeating() {
        stopRepeating()
        repeatTask = Task { @MainActor in
            onPressDown(); spec.action()                 // first delete, immediately
            try? await Task.sleep(for: .milliseconds(450))   // hold delay before repeat
            var interval = 110
            while !Task.isCancelled {
                onPressDown(); spec.action()
                deleteTick &+= 1                          // bounce the glyph
                interval = max(40, interval - 6)         // accelerate
                try? await Task.sleep(for: .milliseconds(interval))
            }
        }
    }

    private func stopRepeating() {
        repeatTask?.cancel()
        repeatTask = nil
    }

    /// Standard keys: letters commit on touch-DOWN so fast typing registers
    /// instantly; function keys wait for release so a graze can't fire them.
    private var keyGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                if !pressed {
                    pressed = true
                    onPressDown()
                    if isCharacter { spec.action() }
                }
            }
            .onEnded { _ in
                pressed = false
                if !isCharacter { spec.action() }
            }
    }

    /// Space bar: a quick tap inserts a space; press-and-drag horizontally turns
    /// it into a trackpad that slides the cursor (à la the native keyboard).
    private var spaceGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !pressed { pressed = true; onPressDown() }
                // Past a small threshold the gesture becomes a cursor drag, so a
                // plain tap (no real movement) still types a space.
                if abs(value.translation.width) > Self.cursorStride { cursorActive = true }
                if cursorActive {
                    dragX = value.translation.width   // drives the glass warp
                    let step = Int((value.translation.width / Self.cursorStride).rounded(.towardZero))
                    if step != cursorSteps {
                        spec.onCursorMove?(step - cursorSteps)
                        cursorSteps = step
                    }
                }
            }
            .onEnded { _ in
                pressed = false
                if !cursorActive { spec.action() }   // tap → insert a space
                cursorActive = false
                cursorSteps = 0
                dragX = 0                            // spring the warp back
            }
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
                .animation(.snappy(duration: 0.25), value: name)
        }
    }

    /// Tint applied to a glass key. Character keys stay untinted (pure
    /// refractive glass); function keys take a faint tint; pressed / latched
    /// keys glow with the accent.
    private var glassTint: Color? {
        if isPressed { return pressedTint }
        if spec.highlighted { return theme.accent.color }
        return isCharacter ? nil : theme.specialKeyFill.color
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
    let theme: Theme
    let onTap: (String) -> Void
    let onKeepTyped: () -> Void

    private enum Kind { case keep, primary, normal }
    private struct Candidate: Identifiable {
        let id = UUID()
        let text: String
        let kind: Kind
    }

    private var candidates: [Candidate] {
        var out: [Candidate] = []
        if let c = autocorrection {
            out.append(Candidate(text: c.from, kind: .keep))
            out.append(Candidate(text: c.to, kind: .primary))
            for s in suggestions
            where s.caseInsensitiveCompare(c.to) != .orderedSame
                && s.caseInsensitiveCompare(c.from) != .orderedSame {
                out.append(Candidate(text: s, kind: .normal))
            }
        } else {
            for s in suggestions { out.append(Candidate(text: s, kind: .normal)) }
        }
        return Array(out.prefix(3))
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
            if c.kind == .keep { onKeepTyped() } else { onTap(c.text) }
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
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(theme.keyText.color.opacity(0.15))
            .frame(width: 0.5)
            .padding(.vertical, 11)
    }
}
