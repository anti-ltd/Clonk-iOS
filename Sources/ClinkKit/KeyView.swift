/**
 `KeyView`: a single key rendered with its fill, text, bloom animation, and
 optional glass effect. Also defines `TapPulse` (the additive press-flash animation).
 */
import SwiftUI

// MARK: - Tap pulse

/// A one-shot, additive "tap registered" flash, replayed on every press.
///
/// Keyed to `KeyTouchRouter`'s per-key tap tick (which bumps on every
/// touch-down), so it fires even when the same key is re-pressed while it's
/// still in the pressed/linger state — the case where the bloom, sprung on
/// `isPressed`, can't re-animate. It briefly brightens the key over its own
/// shape and fades out; it changes no geometry, so it layers on top of the
/// bloom/popup without overriding either. Gated on the same `keyPressWarp`
/// switch as the bloom, so turning press visuals off silences it too.
struct TapPulse: ViewModifier {
    let trigger: Int
    let shape: RoundedRectangle
    let enabled: Bool
    /// Peak opacity of the flash (0 = off). Tunable via `tapFlashStrength`.
    var strength: CGFloat = 0.34

    func body(content: Content) -> some View {
        if enabled, strength > 0.001 {
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
                    CubicKeyframe(strength, duration: 0.05)   // snap bright
                    CubicKeyframe(0.0, duration: 0.20)        // ease back out
                }
            }
        } else {
            content
        }
    }
}

// MARK: - Key view

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
struct KeyView: View {
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
    let physics: KeyPressPhysics

    /// Pressed for any reason: a real finger (the router) or the simulator.
    private var isPressed: Bool { router.pressed.contains(keyID) || simulatedPressed }
    /// Space-bar trackpad drag state (only the space key reads these).
    private var cursorActive: Bool { router.spaceCursorActive }
    private var dragX: CGFloat { router.spaceDragX }
    /// Bumped on every auto-repeat delete to bounce the glyph as feedback.
    private var deleteTick: Int { router.deleteTick }

    /// iOS-style destructive red for the pressed backspace key.
    private static let destructiveTint = Color(.sRGB, red: 0.91, green: 0.22, blue: 0.18)

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
        if spec.isSpace, isPressed {
            // The bar leans toward the finger the whole time it's held (tracking
            // `dragX` from the first move — no frozen dead zone) and SHRINKS a fixed
            // amount once a real drag engages, holding that size for the whole drag.
            // The lean is applied as a NON-animated `.offset` in `body`, so it glides
            // live with the finger; on glass that means one liquid-merge morph per
            // finger frame instead of a spring's backlog of them (the drag stutter).
            let maxLean: CGFloat = 28
            let offset = max(min(dragX * physics.spaceLeanMultiplier, maxLean), -maxLean)
            let scale: CGFloat = cursorActive ? physics.spaceCursorDragScale
                                              : (pressWarp && !showsPopup ? physics.spaceBloomScale : 1)
            return (scale, scale, offset)
        }
        // Visible bloom on press for the generic keys. The shift key opts out —
        // it has its own interactive-glass morph (see `glass` / `surface`).
        if pressWarp, isPressed, !showsPopup, !spec.isShift {
            return (physics.bloomScale, physics.bloomScale, 0)
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
            // The lean offset rides BEFORE the springs below. While dragging, only
            // `dragX` (the offset) changes — `isPressed`/`cursorActive` are steady —
            // so no spring fires and the bar tracks the finger live, 1:1: one
            // liquid-merge morph per finger frame, not a spring's backlog of them
            // (that backlog was the drag stutter). On RELEASE the springs DO fire and
            // carry the offset back to centre together with the scale, so it glides
            // home instead of snapping.
            .offset(x: w.offset)
            // Press bloom (non-space). For the SPACE bar this uses the SAME spring as
            // the cursor shrink below, so a drag-release — where `isPressed` and
            // `cursorActive` clear in the same frame — settles on ONE spring instead
            // of two different ones fighting over the scale (the release stutter).
            .animation(spec.isSpace
                       ? .interactiveSpring(response: physics.spaceSpringResponse, dampingFraction: physics.spaceSpringDamping)
                       : (pressWarp && !spec.isShift && !physics.instant
                          ? .interactiveSpring(response: physics.springResponse, dampingFraction: physics.springDamping) : nil),
                       value: isPressed)
            // The space bar's trackpad shrink in/out — a one-shot at engage/release,
            // matched to the spring above. Scoped to space so a space drag never
            // re-animates any other key.
            .animation(spec.isSpace
                       ? .interactiveSpring(response: physics.spaceSpringResponse, dampingFraction: physics.spaceSpringDamping) : nil,
                       value: cursorActive)
            // Additive "tap registered" flash. The bloom above is sprung on
            // `isPressed`, which never re-toggles when the SAME key is tapped
            // twice inside the linger window (the second `l` in "tell") — so the
            // re-press reads as dropped though the character did insert. This
            // pulse is keyed to the router's per-press tick, which bumps on every
            // landing, so each tap gets its own confirmation. It only flashes a
            // brief highlight over the key — it never touches the bloom geometry,
            // so it adds to the press effect rather than overriding it.
            .modifier(TapPulse(trigger: router.tapTick(keyID), shape: shape, enabled: pressWarp, strength: physics.tapFlashStrength))
            // Publish the glyph for the on-top layer — except shift, which draws
            // its own so it can morph with its interactive glass.
            .anchorPreference(key: KeyGlyphKey.self, value: .bounds) { anchor in
                spec.isShift ? [] : [glyphInfo(anchor: anchor, warp: w)]
            }
            // Publish bounds + glyph to the popup layer while pressed.
            .anchorPreference(key: KeyPopupKey.self, value: .bounds) { anchor in
                // Only magnify single-glyph keys (letters, numbers, symbols) —
                // never multi-character keys like "space", which would just show
                // a truncated "S…" bubble. Suppressed while THIS key's accent bar
                // is up (the bar replaces the magnifier).
                guard isPressed, popupEnabled, isCharacter,
                      router.accentKeyID != keyID,
                      case let .text(g) = spec.label, g.count == 1 else { return nil }
                return KeyPopup(glyph: g, anchor: anchor)
            }
            // Publish this key's bounds while its accent bar is up, so the canvas
            // can anchor the accent picker over it.
            .anchorPreference(key: AccentPopupKey.self, value: .bounds) { anchor in
                router.accentKeyID == keyID ? anchor : nil
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
        // The resting fill tint is dialled by the theme's glass tint strength —
        // lower lets more clear glass through so the refraction reads.
        let base = (isCharacter ? theme.keyFill : theme.specialKeyFill).color
        return base.opacity(theme.glassTintStrength)
    }

    @available(iOS 26.0, *)
    private var glass: Glass {
        // Variant (regular / clear) and tint come from the theme. Interactive is
        // always on for shift (it draws its own glyph, so the lens morphs it — the
        // caps-lock animation) and otherwise opt-in per theme: generic key glyphs
        // are drawn in a separate layer, so an interactive lens warps the material
        // under the finger without dragging the glyph off-centre.
        var base: Glass = theme.glassVariant == .clear ? .clear : .regular
        if spec.isShift || theme.glassInteractive { base = base.interactive() }
        return glassTint.map { base.tint($0) } ?? base
    }

    private var glassFallbackTint: Color {
        if isPressed { return pressedTint.opacity(0.85) }
        if spec.highlighted { return theme.accent.color.opacity(0.85) }
        let base = (isCharacter ? theme.keyFill : theme.specialKeyFill).color
        return base.opacity(theme.glassTintStrength)
    }
}
