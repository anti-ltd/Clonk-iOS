/**
 Named setting presets and the UI components that surface them: `PresetChips`
 (a horizontal chip row) and `TunedSection` (a card with presets + a Fine-tune
 disclosure wrapping the raw sliders).
 

 Module: app-ui · Target: Clink
 Learn: docs/09-app-ui.md
 */
import SwiftUI
import iUXiOS

/// A named bundle of setting values. Tapping a preset writes its values in one
/// shot; `matches` reports whether the current settings already equal it (so the
/// chip can highlight, or fall back to "Custom" when the user has hand-tuned).
///
/// This is how the dense tuning pages stay calm: most people pick a preset and
/// never open "Fine-tune" at all. The raw sliders are all still there — just one
/// disclosure away — so nothing is lost.
struct Preset: Sendable {
    let name: String
    let apply: @Sendable (inout KeyboardSettings) -> Void
    let matches: @Sendable (KeyboardSettings) -> Bool
    /// Optional one-line summary of the values this preset writes, shown under the
    /// chip row when the preset is active (so it's clear what a tap changed).
    var detail: String? = nil
}

/// Float compare with a tolerance — preset values are discrete, but stored
/// doubles drift, so exact `==` would never match.
private func aeq(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.001 }

// MARK: - Catalogs

/// Named preset catalogs for tuning screens. Each `Preset.apply` writes a bundle
/// of `KeyboardSettings` fields; `PresetChips` / `TunedSection` surface them in UI.
enum TuningPresets {
    /// Hitbox forgiveness (touch target size vs precision).
    static let hitbox: [Preset] = [
        Preset(name: "Precise",   apply: { $0.hitboxScale = 0.82 }, matches: { aeq($0.hitboxScale, 0.82) },
               detail: "Hitbox 82% — tight targets, fewer mis-hits between keys."),
        Preset(name: "Default",   apply: { $0.hitboxScale = 0.90 }, matches: { aeq($0.hitboxScale, 0.90) },
               detail: "Hitbox 90%."),
        Preset(name: "Forgiving", apply: { $0.hitboxScale = 1.08 }, matches: { aeq($0.hitboxScale, 1.08) },
               detail: "Hitbox 108% — bigger targets, catches more taps."),
    ]

    /// Cursor movement mode — how the space bar activates cursor control.
    static let cursorMovementType: [Preset] = [
        Preset(name: "Spacebar",  apply: { $0.cursorMovementType = .spacebar  }, matches: { $0.cursorMovementType == .spacebar  },
               detail: "Slide along the space bar to move the cursor."),
        Preset(name: "Trackpad",  apply: { $0.cursorMovementType = .trackpad  }, matches: { $0.cursorMovementType == .trackpad  },
               detail: "Hold space to turn the whole keyboard into a 2-D trackpad."),
        Preset(name: "Combined",  apply: { $0.cursorMovementType = .combined  }, matches: { $0.cursorMovementType == .combined  },
               detail: "Hold space to drag; keys stay visible but go inert."),
    ]

    /// Cursor engagement — how eager the space-bar cursor is to activate.
    static let cursor: [Preset] = [
        // Deliberate is the shipped default (see `KeyboardSettings` field defaults).
        Preset(name: "Deliberate", apply: { $0.spaceCursorActivationDelay = 150; $0.spaceCursorStride = 16 },
               matches: { aeq($0.spaceCursorActivationDelay, 150) && aeq($0.spaceCursorStride, 16) },
               detail: "150ms hold · 16pt per character — fewer accidental scrolls."),
        Preset(name: "Instant",    apply: { $0.spaceCursorActivationDelay = 0;   $0.spaceCursorStride = 10 },
               matches: { aeq($0.spaceCursorActivationDelay, 0) && aeq($0.spaceCursorStride, 10) },
               detail: "Instant · 10pt per character."),
        Preset(name: "Sensitive",  apply: { $0.spaceCursorActivationDelay = 0;   $0.spaceCursorStride = 8 },
               matches: { aeq($0.spaceCursorActivationDelay, 0) && aeq($0.spaceCursorStride, 8) },
               detail: "Instant · 8pt per character — the cursor flies."),
    ]

    /// The whole press FEEL in one tap — every spring/bloom/timing knob the
    /// "Feel" card exposes (key + space bar + popup springs, both blooms, instant,
    /// press linger, glass return). Deliberately does NOT touch the Effects (tap
    /// flash, glow, press style, entrance) or the `minPressVisible` accessibility
    /// floor — those stay the user's own choices, never wiped by a feel swap.
    static let animation: [Preset] = [
        Preset(name: "Default", apply: { s in
            s.keyBloomScale = 1.12; s.keySpringResponse = 0.26; s.keySpringDamping = 0.60
            s.keyPressInstant = false; s.keyPressLinger = 0.06
            s.spaceBloomScale = 1.04; s.spaceSpringResponse = 0.28; s.spaceSpringDamping = 0.78
            s.spaceLeanMultiplier = 0.14; s.spaceCursorDragScale = 0.90
            s.popupSpringResponse = 0.32; s.popupSpringDamping = 0.62
            s.glassReleaseResponse = 0.12
        }, matches: { s in
            aeq(s.keyBloomScale, 1.12) && aeq(s.keySpringResponse, 0.26) && aeq(s.keySpringDamping, 0.60)
            && !s.keyPressInstant && aeq(s.keyPressLinger, 0.06)
            && aeq(s.spaceBloomScale, 1.04) && aeq(s.spaceSpringResponse, 0.28) && aeq(s.spaceSpringDamping, 0.78)
            && aeq(s.spaceLeanMultiplier, 0.14) && aeq(s.spaceCursorDragScale, 0.90)
            && aeq(s.popupSpringResponse, 0.32) && aeq(s.popupSpringDamping, 0.62)
            && aeq(s.glassReleaseResponse, 0.12)
        }, detail: "Key 0.26s/0.60 · space 0.28s · popup 0.32s · bloom 112% · linger 60ms."),
        Preset(name: "Snappy", apply: { s in
            s.keyBloomScale = 1.06; s.keySpringResponse = 0.16; s.keySpringDamping = 0.85
            s.keyPressInstant = false; s.keyPressLinger = 0.04
            s.spaceBloomScale = 1.02; s.spaceSpringResponse = 0.16; s.spaceSpringDamping = 0.88
            s.spaceLeanMultiplier = 0.08; s.spaceCursorDragScale = 0.95
            s.popupSpringResponse = 0.20; s.popupSpringDamping = 0.85
            s.glassReleaseResponse = 0.10
        }, matches: { s in
            aeq(s.keyBloomScale, 1.06) && aeq(s.keySpringResponse, 0.16) && aeq(s.keySpringDamping, 0.85)
            && !s.keyPressInstant && aeq(s.keyPressLinger, 0.04)
            && aeq(s.spaceBloomScale, 1.02) && aeq(s.spaceSpringResponse, 0.16) && aeq(s.spaceSpringDamping, 0.88)
            && aeq(s.spaceLeanMultiplier, 0.08) && aeq(s.spaceCursorDragScale, 0.95)
            && aeq(s.popupSpringResponse, 0.20) && aeq(s.popupSpringDamping, 0.85)
            && aeq(s.glassReleaseResponse, 0.10)
        }, detail: "Key 0.16s/0.85 · space 0.16s · popup 0.20s · bloom 106% — fast & firm."),
        Preset(name: "Bouncy", apply: { s in
            s.keyBloomScale = 1.20; s.keySpringResponse = 0.34; s.keySpringDamping = 0.45
            s.keyPressInstant = false; s.keyPressLinger = 0.08
            s.spaceBloomScale = 1.08; s.spaceSpringResponse = 0.36; s.spaceSpringDamping = 0.55
            s.spaceLeanMultiplier = 0.20; s.spaceCursorDragScale = 0.85
            s.popupSpringResponse = 0.40; s.popupSpringDamping = 0.48
            s.glassReleaseResponse = 0.16
        }, matches: { s in
            aeq(s.keyBloomScale, 1.20) && aeq(s.keySpringResponse, 0.34) && aeq(s.keySpringDamping, 0.45)
            && !s.keyPressInstant && aeq(s.keyPressLinger, 0.08)
            && aeq(s.spaceBloomScale, 1.08) && aeq(s.spaceSpringResponse, 0.36) && aeq(s.spaceSpringDamping, 0.55)
            && aeq(s.spaceLeanMultiplier, 0.20) && aeq(s.spaceCursorDragScale, 0.85)
            && aeq(s.popupSpringResponse, 0.40) && aeq(s.popupSpringDamping, 0.48)
            && aeq(s.glassReleaseResponse, 0.16)
        }, detail: "Key 0.34s/0.45 · space 0.36s · popup 0.40s · bloom 120% — loose & playful."),
        Preset(name: "Minimal", apply: { s in
            s.keyBloomScale = 1.0; s.keySpringResponse = 0.12; s.keySpringDamping = 1.0
            s.keyPressInstant = false; s.keyPressLinger = 0.0
            s.spaceBloomScale = 1.0; s.spaceSpringResponse = 0.12; s.spaceSpringDamping = 1.0
            s.spaceLeanMultiplier = 0.0; s.spaceCursorDragScale = 1.0
            s.popupSpringResponse = 0.16; s.popupSpringDamping = 1.0
            s.glassReleaseResponse = 0.08
        }, matches: { s in
            aeq(s.keyBloomScale, 1.0) && aeq(s.keySpringResponse, 0.12) && aeq(s.keySpringDamping, 1.0)
            && !s.keyPressInstant && aeq(s.keyPressLinger, 0.0)
            && aeq(s.spaceBloomScale, 1.0) && aeq(s.spaceSpringResponse, 0.12) && aeq(s.spaceSpringDamping, 1.0)
            && aeq(s.spaceLeanMultiplier, 0.0) && aeq(s.spaceCursorDragScale, 1.0)
            && aeq(s.popupSpringResponse, 0.16) && aeq(s.popupSpringDamping, 1.0)
            && aeq(s.glassReleaseResponse, 0.08)
        }, detail: "No bloom · no lean · firm 0.12s springs — flattest, most static."),
    ]

    // (The standalone `spaceBar` preset row was retired when the Animation page
    // folded the space-bar knobs into the single "Feel" preset + Fine-tune — the
    // `animation` preset above now sets the space-bar feel too.)

    /// Popup emerge spring — speed and springiness only.
    static let popup: [Preset] = [
        Preset(name: "Default", apply: { s in
            s.popupSpringResponse = 0.32; s.popupSpringDamping = 0.62
        }, matches: { s in
            aeq(s.popupSpringResponse, 0.32) && aeq(s.popupSpringDamping, 0.62)
        }, detail: "0.32s · 0.62."),
        Preset(name: "Snappy", apply: { s in
            s.popupSpringResponse = 0.20; s.popupSpringDamping = 0.85
        }, matches: { s in
            aeq(s.popupSpringResponse, 0.20) && aeq(s.popupSpringDamping, 0.85)
        }, detail: "0.20s · 0.85 — quick pop."),
        Preset(name: "Bouncy", apply: { s in
            s.popupSpringResponse = 0.40; s.popupSpringDamping = 0.48
        }, matches: { s in
            aeq(s.popupSpringResponse, 0.40) && aeq(s.popupSpringDamping, 0.48)
        }, detail: "0.40s · 0.48 — pronounced bounce."),
        Preset(name: "Minimal", apply: { s in
            s.popupSpringResponse = 0.16; s.popupSpringDamping = 1.0
        }, matches: { s in
            aeq(s.popupSpringResponse, 0.16) && aeq(s.popupSpringDamping, 1.0)
        }, detail: "0.16s · firm snap."),
    ]

    /// Press linger + backspace auto-repeat timing.
    static let timing: [Preset] = [
        Preset(name: "Default", apply: { s in
            s.keyPressLinger = 0.06; s.repeatHoldDelay = 450
            s.repeatInitialInterval = 110; s.repeatMinInterval = 40; s.repeatAccelStep = 6
        }, matches: { s in
            aeq(s.keyPressLinger, 0.06) && aeq(s.repeatHoldDelay, 450)
            && aeq(s.repeatInitialInterval, 110) && aeq(s.repeatMinInterval, 40) && aeq(s.repeatAccelStep, 6)
        }, detail: "Linger 60ms · repeat after 450ms, 110→40ms."),
        Preset(name: "Fast", apply: { s in
            s.keyPressLinger = 0.04; s.repeatHoldDelay = 250
            s.repeatInitialInterval = 80; s.repeatMinInterval = 25; s.repeatAccelStep = 10
        }, matches: { s in
            aeq(s.keyPressLinger, 0.04) && aeq(s.repeatHoldDelay, 250)
            && aeq(s.repeatInitialInterval, 80) && aeq(s.repeatMinInterval, 25) && aeq(s.repeatAccelStep, 10)
        }, detail: "Linger 40ms · repeat after 250ms, 80→25ms — quick & aggressive."),
        Preset(name: "Relaxed", apply: { s in
            s.keyPressLinger = 0.10; s.repeatHoldDelay = 600
            s.repeatInitialInterval = 150; s.repeatMinInterval = 60; s.repeatAccelStep = 3
        }, matches: { s in
            aeq(s.keyPressLinger, 0.10) && aeq(s.repeatHoldDelay, 600)
            && aeq(s.repeatInitialInterval, 150) && aeq(s.repeatMinInterval, 60) && aeq(s.repeatAccelStep, 3)
        }, detail: "Linger 100ms · repeat after 600ms, 150→60ms — calm & forgiving."),
    ]

    /// Gesture response — how eagerly long-press / slide-up gestures fire.
    static let response: [Preset] = [
        Preset(name: "Default", apply: { s in
            s.accentHoldDelay = 500; s.emojiToneHoldDelay = 280
            s.dragUpThreshold = 24; s.accentMoveCancel = 12
        }, matches: { s in
            aeq(s.accentHoldDelay, 500) && aeq(s.emojiToneHoldDelay, 280)
            && aeq(s.dragUpThreshold, 24) && aeq(s.accentMoveCancel, 12)
        }, detail: "Accent 500ms · tone 280ms · slide-up 24pt."),
        Preset(name: "Eager", apply: { s in
            s.accentHoldDelay = 300; s.emojiToneHoldDelay = 180
            s.dragUpThreshold = 16; s.accentMoveCancel = 18
        }, matches: { s in
            aeq(s.accentHoldDelay, 300) && aeq(s.emojiToneHoldDelay, 180)
            && aeq(s.dragUpThreshold, 16) && aeq(s.accentMoveCancel, 18)
        }, detail: "Accent 300ms · tone 180ms · slide-up 16pt — gestures fire sooner."),
        Preset(name: "Deliberate", apply: { s in
            s.accentHoldDelay = 700; s.emojiToneHoldDelay = 420
            s.dragUpThreshold = 36; s.accentMoveCancel = 8
        }, matches: { s in
            aeq(s.accentHoldDelay, 700) && aeq(s.emojiToneHoldDelay, 420)
            && aeq(s.dragUpThreshold, 36) && aeq(s.accentMoveCancel, 8)
        }, detail: "Accent 700ms · tone 420ms · slide-up 36pt — fewer accidental holds."),
    ]

    /// Overall key size & spacing.
    static let size: [Preset] = [
        Preset(name: "Compact", apply: { s in
            s.keyHeight = 44; s.keyCornerRadius = 10; s.keyWidthFraction = 1
            s.spaceWidth = 6; s.funcKeyWidth = 1.3; s.keySpacing = 1; s.rowSpacing = 2
        }, matches: { s in
            aeq(s.keyHeight, 44) && aeq(s.keyCornerRadius, 10) && aeq(s.keyWidthFraction, 1)
            && aeq(s.spaceWidth, 6) && aeq(s.funcKeyWidth, 1.3) && aeq(s.keySpacing, 1) && aeq(s.rowSpacing, 2)
        }, detail: "44pt keys · radius 10 · tight 1/2pt gaps."),
        Preset(name: "Default", apply: { s in
            s.keyHeight = 51; s.keyCornerRadius = 13; s.keyWidthFraction = 1
            s.spaceWidth = 7; s.funcKeyWidth = 1.4; s.keySpacing = 1; s.rowSpacing = 4
        }, matches: { s in
            aeq(s.keyHeight, 51) && aeq(s.keyCornerRadius, 13) && aeq(s.keyWidthFraction, 1)
            && aeq(s.spaceWidth, 7) && aeq(s.funcKeyWidth, 1.4) && aeq(s.keySpacing, 1) && aeq(s.rowSpacing, 4)
        }, detail: "51pt keys · radius 13 · 1/4pt gaps."),
        Preset(name: "Large", apply: { s in
            s.keyHeight = 58; s.keyCornerRadius = 16; s.keyWidthFraction = 1
            s.spaceWidth = 7; s.funcKeyWidth = 1.5; s.keySpacing = 2; s.rowSpacing = 6
        }, matches: { s in
            aeq(s.keyHeight, 58) && aeq(s.keyCornerRadius, 16) && aeq(s.keyWidthFraction, 1)
            && aeq(s.spaceWidth, 7) && aeq(s.funcKeyWidth, 1.5) && aeq(s.keySpacing, 2) && aeq(s.rowSpacing, 6)
        }, detail: "58pt keys · radius 16 · roomy 2/6pt gaps."),
    ]

    /// Suggestion compute budget — how often UITextChecker runs during typing.
    static let performance: [Preset] = [
        Preset(name: "Balanced",
               apply: { $0.suggestionDebounceDelay = 80 },
               matches: { aeq($0.suggestionDebounceDelay, 80) },
               detail: "Compute delay 80ms."),
        Preset(name: "Efficient",
               apply: { $0.suggestionDebounceDelay = 200 },
               matches: { aeq($0.suggestionDebounceDelay, 200) },
               detail: "Compute delay 200ms — fewer checks, best battery."),
        Preset(name: "Instant",
               apply: { $0.suggestionDebounceDelay = 20 },
               matches: { aeq($0.suggestionDebounceDelay, 20) },
               detail: "Compute delay 20ms — snappiest bar, most CPU."),
    ]

    /// Overall typing *feel* — the whole snappiness cluster in one tap. Drives the
    /// key/space-bar spring speed + damping, the press bloom and linger, and the
    /// suggestion compute budget together, so "how responsive does typing feel" is
    /// a single decision. The raw sliders below the chips still tune each one.
    ///
    /// `Native` mimics the stock keyboard: near-instant, firm springs, minimal
    /// bloom, no linger, tight compute. `Default` is Clink's softer liquid feel.
    /// `Bouncy` leans into the deformation for a playful, springy press.
    static let responsiveness: [Preset] = [
        Preset(name: "Native", apply: { s in
            s.keySpringResponse = 0.12; s.keySpringDamping = 0.90; s.keyBloomScale = 1.06
            s.keyPressLinger = 0.0
            s.spaceSpringResponse = 0.14; s.spaceSpringDamping = 0.90
            s.suggestionDebounceDelay = 30
        }, matches: { s in
            aeq(s.keySpringResponse, 0.12) && aeq(s.keySpringDamping, 0.90) && aeq(s.keyBloomScale, 1.06)
            && aeq(s.keyPressLinger, 0.0)
            && aeq(s.spaceSpringResponse, 0.14) && aeq(s.spaceSpringDamping, 0.90)
            && aeq(s.suggestionDebounceDelay, 30)
        }, detail: "Springs 0.12s · firm 0.90 · bloom 106% · no linger · compute 30ms."),
        Preset(name: "Default", apply: { s in
            s.keySpringResponse = 0.26; s.keySpringDamping = 0.60; s.keyBloomScale = 1.12
            s.keyPressLinger = 0.06
            s.spaceSpringResponse = 0.28; s.spaceSpringDamping = 0.78
            s.suggestionDebounceDelay = 80
        }, matches: { s in
            aeq(s.keySpringResponse, 0.26) && aeq(s.keySpringDamping, 0.60) && aeq(s.keyBloomScale, 1.12)
            && aeq(s.keyPressLinger, 0.06)
            && aeq(s.spaceSpringResponse, 0.28) && aeq(s.spaceSpringDamping, 0.78)
            && aeq(s.suggestionDebounceDelay, 80)
        }, detail: "Springs 0.26s · 0.60 · bloom 112% · linger 60ms · compute 80ms."),
        Preset(name: "Bouncy", apply: { s in
            s.keySpringResponse = 0.34; s.keySpringDamping = 0.45; s.keyBloomScale = 1.18
            s.keyPressLinger = 0.10
            s.spaceSpringResponse = 0.34; s.spaceSpringDamping = 0.60
            s.suggestionDebounceDelay = 80
        }, matches: { s in
            aeq(s.keySpringResponse, 0.34) && aeq(s.keySpringDamping, 0.45) && aeq(s.keyBloomScale, 1.18)
            && aeq(s.keyPressLinger, 0.10)
            && aeq(s.spaceSpringResponse, 0.34) && aeq(s.spaceSpringDamping, 0.60)
            && aeq(s.suggestionDebounceDelay, 80)
        }, detail: "Springs 0.34s · loose 0.45 · bloom 118% · linger 100ms · compute 80ms."),
    ]
}

// MARK: - Views

/// A horizontal row of preset chips. The chip matching the current settings is
/// filled; if none match (the user has fine-tuned), a "Custom" chip shows
/// instead so the state is never ambiguous.
struct PresetChips: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.cardCornerRadius) private var cardCornerRadius
    @Environment(\.useGlassCards) private var useGlassCards
    let presets: [Preset]

    private var theme: Theme { model.settings.resolvedTheme(dark: colorScheme == .dark) }
    private var inactiveFill: Color { theme.specialKeyFill.color }
    private var accentFill: Color { theme.accent.color }

    var body: some View {
        let activePreset = presets.first { $0.matches(model.settings) }
        let active = activePreset?.name
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(presets, id: \.name) { preset in
                        chip(preset.name, selected: preset.name == active) {
                            var s = model.settings
                            preset.apply(&s)
                            model.settings = s
                        }
                    }
                    if active == nil {
                        chip("Custom", selected: true, action: nil)
                    }
                }
                .padding(.horizontal, 2)
            }
            if let detail = activePreset?.detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 2)
            }
        }
    }

    @ViewBuilder
    private func chip(_ title: String, selected: Bool, action: (() -> Void)?) -> some View {
        if let action {
            Button(action: action) { chipLabel(title, selected: selected) }.buttonStyle(.plain)
        } else {
            chipLabel(title, selected: selected)
        }
    }

    @ViewBuilder
    private func chipLabel(_ title: String, selected: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
        let text = Text(title)
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .foregroundStyle(selected ? Color.white : Color.primary)
        if useGlassCards, #available(iOS 26.0, *) {
            let glass: Glass = selected
                ? Glass.regular.tint(accentFill).interactive()
                : Glass.regular.tint(inactiveFill)
            text.background { Color.clear.glassEffect(glass, in: shape) }
        } else {
            text.background(
                selected ? AnyShapeStyle(accentFill) : AnyShapeStyle(inactiveFill),
                in: shape)
        }
    }
}

/// A calm tuning block: a row of presets up top, with every raw control tucked
/// into a collapsed "Fine-tune" disclosure. Replaces a wall of sliders with a
/// single decision for the common case.
struct TunedSection<Content: View>: View {
    let title: String
    let presets: [Preset]
    @ViewBuilder var fineTune: Content
    @State private var expanded = false

    var body: some View {
        CardSection(title) {
            PresetChips(presets: presets)
                .padding(.vertical, UX.rowVPadding)
            Divider()
            DisclosureGroup("Fine-tune", isExpanded: $expanded) {
                VStack(spacing: 0) { fineTune }
                    .padding(.top, 6)
            }
            .tint(.primary)
            .padding(.vertical, UX.rowVPadding)
        }
    }
}

// MARK: - Gating (show-disabled-with-reason)
//
// House rule: a setting that depends on a feature being on is shown even when
// that feature is off — disabled, dimmed, with a one-line reason — rather than
// hidden. The page never goes empty; users can see what's available before
// flipping the switch. `GatedCard` gates a whole card (reason at the top);
// `.gated(_:reason:)` gates an inline block (reason beneath it).

/// A lock glyph + a short reason, explaining why the controls near it are off.
struct LockedReason: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "lock.fill").font(.caption2)
            Text(text).font(.caption)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, UX.rowVPadding)
    }
}

/// A `CardSection` that keeps its dependent controls visible when their feature
/// is off — disabled and dimmed, with a reason at the top — instead of hiding
/// them. Use for a whole card that only does something once `enabled` is true.
struct GatedCard<Content: View>: View {
    let title: String?
    let enabled: Bool
    let reason: String
    @ViewBuilder var content: Content

    init(_ title: String? = nil, enabled: Bool, reason: String,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.enabled = enabled
        self.reason = reason
        self.content = content()
    }

    var body: some View {
        CardSection(title) {
            if !enabled {
                LockedReason(reason)
                Divider()
            }
            content
                .disabled(!enabled)
                .opacity(enabled ? 1 : 0.45)
        }
        .animation(.snappy(duration: 0.25), value: enabled)
    }
}

extension View {
    /// Keep this control visible when its feature is off — disabled, dimmed, with
    /// a reason caption beneath — instead of hiding it. For an inline block that
    /// lives inside an otherwise-active card.
    @ViewBuilder
    func gated(_ enabled: Bool, reason: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            self
                .disabled(!enabled)
                .opacity(enabled ? 1 : 0.45)
            if !enabled { LockedReason(reason) }
        }
        .animation(.snappy(duration: 0.25), value: enabled)
    }
}
