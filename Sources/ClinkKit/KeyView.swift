/**
 `KeyView`: a single key rendered with its fill, text, bloom animation, and
 optional glass effect.
 

 Module: keyboard-core · Target: ClinkKit
 Learn: docs/02-keyboard-core.md
 */
import SwiftUI


// MARK: - Key view

/// Renders one key surface (glass or solid) and publishes glyph, popup, accent,
/// and hit-frame preferences for the canvas overlay layers. Press/warp state is
/// read from `TouchEngine`; touches are handled by `MultiTouchSurface`, not here.
struct KeyView: View {
    let spec: KeySpec
    let theme: Theme
    let cornerRadius: CGFloat
    let popupEnabled: Bool
    /// Swell the key as a swiping finger passes over it (liquid-glass only, per
    /// `swipeKeyMorph`).
    let swipeMorph: Bool
    /// Peak extra scale at the finger's centre (per `swipeMorphStrength`).
    /// The ripple's reach (`swipeMorphRadius`) lives in the router, which
    /// computes and pushes each key's bulge.
    let swipeMorphStrength: CGFloat
    /// Stable identity (row-col) so the glyph layer can track this key across
    /// rebuilds for its symbol animations.
    let keyID: String
    /// Plane this key belongs to, stamped onto its published glyph so the canvas
    /// can drop glyphs left over from the previous plane during a switch.
    let plane: KeyboardController.Plane
    /// Driven by an external typing simulator (the device showcase) — shows the
    /// key as pressed even though no finger is on it.
    let simulatedPressed: Bool
    /// Shared multitouch state — this key's press / warp is read out of here,
    /// written by the single UIKit touch surface (see `TouchEngine`).
    let router: TouchEngine
    let physics: KeyPressPhysics
    let longPressHintsEnabled: Bool

    /// This key's own observable press state — reading it (rather than a shared
    /// set on the router) means a press invalidates only this key's view, not
    /// the whole grid. The lookup itself is unobserved (see `TouchEngine`).
    private var state: KeyPressState { router.state(for: keyID) }

    /// Pressed for any reason: a real finger (the router) or the simulator.
    private var isPressed: Bool { state.isPressed || simulatedPressed }
    /// Space-bar trackpad drag state (only the space key reads these).
    private var cursorActive: Bool { router.spaceCursorActive }
    private var dragX: CGFloat { router.spaceDragX }
    /// Bumped on every auto-repeat delete to bounce the glyph as feedback.
    private var deleteTick: Int { router.deleteTick }
    /// True while a backspace swipe-to-delete-word is engaged (delete key only).
    private var deleteSwiping: Bool { router.deleteWordSwipeActive }

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

    /// Live swell from a passing swipe finger (1 = rest). Glass-only and gated on
    /// `swipeKeyMorph`; reads this key's OWN router-pushed bulge (see
    /// `KeyPressState.bulge`), so a glide sample re-renders only the keys whose
    /// swell actually changed — every key pulling the live trail per sample is
    /// what made the ripple drop frames. Settles back to 1 the moment the swipe
    /// lifts (the router zeroes all bulges). Applied to the surface alone (not
    /// the glyph), so the glass flows while the letter holds its place — and
    /// because the surfaces share a `GlassEffectContainer`, a swollen key
    /// liquid-merges into its neighbours as the ripple passes. Strength comes
    /// from `swipeMorphStrength`; the reach lives in the router
    /// (`swipeMorphRadius`), where the bulge is computed.
    private var swipeBulgeScale: CGFloat {
        guard swipeMorph, theme.material == .liquidGlass else { return 1 }
        return 1 + state.bulge * swipeMorphStrength
    }

    /// Liquid "warp": the space bar stretches toward the finger (and squashes
    /// vertically) while dragging the cursor; when bloom is on (its scale > 1),
    /// every key blooms a little on press. Both spring back on release. Each
    /// effect self-gates on its own strength — there is no master switch.
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
                                              : (!showsPopup && physics.spaceBloomScale > 1.0001 ? physics.spaceBloomScale : 1)
            return (scale, scale, offset)
        }
        // Visible bloom on press for the generic keys — only when bloom is on
        // (its effective scale grows). The shift key opts out (its own
        // interactive-glass morph, see `glass` / `surface`). Skipped entirely
        // during a typing burst: a sprung scale re-rasters the glass lens every
        // frame, and that frame work lands on the next key's touch delivery —
        // felt as haptic lag. In a burst the key tint-flips instead (one raster),
        // and the bloom returns the instant typing slows (see MotionProfile).
        if isPressed, !showsPopup, !spec.isShift, physics.bloomEnabled,
           !MotionProfile.shared.prefersInstantKeyPress {
            // Softened on glass (see `effectiveBloomScale`) so the key grows
            // less into its neighbours — cheaper for the container to merge.
            // `pressStyle` reshapes the SAME single scale into different feels:
            // grow uniformly (bloom), shrink (press-in), or squash on one axis
            // (jelly / stretch). Same one-`scaleEffect` cost for every style.
            let s = physics.effectiveBloomScale          // e.g. 1.06–1.12
            let inv = max(0.5, 2 - s)                     // mirrored "shrink"
            switch physics.pressStyle {
            case .bloom:   return (s, s, 0)
            case .sink:    return (inv, inv, 0)
            case .jelly:   return (s, inv, 0)            // wide + short
            case .stretch: return (inv, s, 0)            // narrow + tall
            }
        }
        return (1, 1, 0)
    }

    var body: some View {
        // NOTE: glass keys deliberately do NOT register a dependency on a
        // neighbour's press here. The pressed key still blooms and its own lens
        // re-rasterizes, but waking the ~6 surrounding keys so the bulge
        // liquid-*bleeds* into them meant ~7 lens re-rasters per frame for the
        // whole spring — the press lag, even on a full-power device. Isolating
        // the bloom to the pressed key alone (one lens per frame) is the ~6× win;
        // the only thing lost is the brief inter-key bleed on a tap, which is
        // barely perceptible at tap speed. The SWIPE ripple keeps its cross-key
        // swell — it pushes per-key `bulge` directly, no neighbour wake needed.
        let w = warp
        // The press bloom is applied to the SURFACE (the glass lens deforms) AND
        // republished to the glyph layer, so key and letter morph together. On
        // glass the bloom GROWTH is auto-clamped (see `effectiveBloomScale`) so a
        // single lens re-raster per frame stays cheap; the shift key draws its own
        // glyph as glass content for the caps-lock morph.
        let swipeScale = swipeBulgeScale
        return surface
            // Accent glow behind a pressed key — a blurred tinted halo on the few
            // keys held at once. Only the opacity animates (the layer is always
            // present when enabled, so no structural insert mid-press); gated on
            // the expensive-effects tier so it drops under power/thermal pressure.
            .background { pressGlowLayer }
            // Swipe ripple: a passing glide finger swells the key. Lightly sprung so
            // it flows rather than snaps, and keyed only to its own value so it never
            // disturbs the press bloom below. Multiplies with the press scale.
            .scaleEffect(swipeScale, anchor: .center)
            .animation(Motion.swipeRipple.animation, value: swipeScale)
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
            // During a typing burst, snap (no animation): a spring would
            // interpolate the tint/scale over many frames, each one re-rastering
            // the glass lens and stealing time from the next key's touch
            // delivery. One raster down, one up — nothing per-frame.
            .animation(MotionProfile.shared.prefersInstantKeyPress ? nil
                       : spec.isSpace
                       ? physics.spaceSpringAnimation
                       : (physics.bloomEnabled && !spec.isShift && !physics.instant
                          // Bloom RISES with the tuned (bouncy) spring, RETURNS
                          // with the calmer settle — body re-evaluates when
                          // `isPressed` flips, so the active spring matches the
                          // direction. The return's collapsed ring is what stops
                          // the glass lens re-compositing through a long bounce.
                          // Now that the bloom is isolated to this one key (no
                          // neighbour re-blend, see `body`), the per-frame lens
                          // re-raster is a single key — cheap enough to keep the
                          // full sprung deformation + tint.
                          ? (isPressed ? physics.keySpringAnimation : physics.keyReleaseAnimation) : nil),
                       value: isPressed)
            // The space bar's trackpad shrink in/out — a one-shot at engage/release,
            // matched to the spring above. Scoped to space so a space drag never
            // re-animates any other key.
            .animation(spec.isSpace
                       ? physics.spaceSpringAnimation : nil,
                       value: cursorActive)
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
            // can anchor the accent picker over it. `isPressed` is checked FIRST
            // so unpressed keys never read (and thus never observe) the shared
            // `accentKeyID` — an accent session can only start on a held key, so
            // the gate loses nothing while sparing the grid an invalidation on
            // every session start/end.
            .anchorPreference(key: AccentPopupKey.self, value: .bounds) { anchor in
                isPressed && router.accentKeyID == keyID ? anchor : nil
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
            id: keyID, plane: plane, anchor: anchor, isSystem: isSystem, glyph: glyph,
            color: isPressed ? .white : textColor,
            scaleX: warp.scaleX, scaleY: warp.scaleY, offsetX: warp.offset,
            // Only the backspace key bounces on auto-repeat; every other key
            // feeds 0 so a delete burst doesn't jiggle shift / globe / return.
            // The key keeps its own glyph even while popping — the popup sits
            // above it (à la the system keyboard), so the letter stays put.
            hidden: false, deleteTick: spec.isRepeatable ? deleteTick : 0,
            deleteSwiping: spec.onDeleteWord != nil ? deleteSwiping : false,
            multiChar: multiChar,
            fontSize: spec.fontSize,
            hint: {
                guard longPressHintsEnabled, isCharacter, spec.accents.count >= 2 else { return nil }
                let v = spec.accents[1]
                return v.count == 1 ? v : nil
            }())
    }

    /// Soft accent halo behind a pressed key (the "glow" effect). Always present
    /// when enabled so only its opacity animates — never a structural insert that
    /// would hitch the press. Honours the motion profile's expensive-effects gate.
    @ViewBuilder private var pressGlowLayer: some View {
        if physics.pressGlow > 0.001, !spec.isSpace {
            shape.fill(pressedTint)
                .opacity(isPressed && MotionProfile.shared.allowsExpensiveEffects
                         ? Double(physics.pressGlow) : 0)
                .blur(radius: 9)
                .scaleEffect(1.18)
                .allowsHitTesting(false)
                .animation(Motion.tapFlashOut.animation, value: isPressed)
        }
    }

    // MARK: - Surface rendering

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
                .animation(Motion.glyphSwap.animation, value: name)
        }
    }

    // MARK: - Glass tint & material

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
