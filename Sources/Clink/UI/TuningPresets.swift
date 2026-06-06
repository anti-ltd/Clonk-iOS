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
}

/// Float compare with a tolerance — preset values are discrete, but stored
/// doubles drift, so exact `==` would never match.
private func aeq(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.001 }

// MARK: - Catalogs

enum TuningPresets {
    /// Hitbox forgiveness (touch target size vs precision).
    static let hitbox: [Preset] = [
        Preset(name: "Precise",   apply: { $0.hitboxScale = 0.82 }, matches: { aeq($0.hitboxScale, 0.82) }),
        Preset(name: "Default",   apply: { $0.hitboxScale = 0.90 }, matches: { aeq($0.hitboxScale, 0.90) }),
        Preset(name: "Forgiving", apply: { $0.hitboxScale = 1.08 }, matches: { aeq($0.hitboxScale, 1.08) }),
    ]

    /// Cursor engagement — how eager the space-bar cursor is to activate.
    static let cursor: [Preset] = [
        Preset(name: "Default",    apply: { $0.spaceCursorActivationDelay = 0;   $0.spaceCursorStride = 10 },
               matches: { aeq($0.spaceCursorActivationDelay, 0) && aeq($0.spaceCursorStride, 10) }),
        Preset(name: "Deliberate", apply: { $0.spaceCursorActivationDelay = 150; $0.spaceCursorStride = 16 },
               matches: { aeq($0.spaceCursorActivationDelay, 150) && aeq($0.spaceCursorStride, 16) }),
        Preset(name: "Sensitive",  apply: { $0.spaceCursorActivationDelay = 0;   $0.spaceCursorStride = 8 },
               matches: { aeq($0.spaceCursorActivationDelay, 0) && aeq($0.spaceCursorStride, 8) }),
    ]

    /// Animation character across key / space bar / popup springs.
    static let animation: [Preset] = [
        Preset(name: "Default", apply: { s in
            s.keyBloomScale = 1.12; s.keySpringResponse = 0.26; s.keySpringDamping = 0.60
            s.spaceSpringResponse = 0.28; s.spaceSpringDamping = 0.78
            s.spaceLeanMultiplier = 0.14; s.spaceCursorDragScale = 0.90
            s.popupSpringResponse = 0.32; s.popupSpringDamping = 0.62
        }, matches: { s in
            aeq(s.keyBloomScale, 1.12) && aeq(s.keySpringResponse, 0.26) && aeq(s.keySpringDamping, 0.60)
            && aeq(s.spaceSpringResponse, 0.28) && aeq(s.spaceSpringDamping, 0.78)
            && aeq(s.spaceLeanMultiplier, 0.14) && aeq(s.spaceCursorDragScale, 0.90)
            && aeq(s.popupSpringResponse, 0.32) && aeq(s.popupSpringDamping, 0.62)
        }),
        Preset(name: "Snappy", apply: { s in
            s.keyBloomScale = 1.06; s.keySpringResponse = 0.16; s.keySpringDamping = 0.85
            s.spaceSpringResponse = 0.16; s.spaceSpringDamping = 0.88
            s.spaceLeanMultiplier = 0.08; s.spaceCursorDragScale = 0.95
            s.popupSpringResponse = 0.20; s.popupSpringDamping = 0.85
        }, matches: { s in
            aeq(s.keyBloomScale, 1.06) && aeq(s.keySpringResponse, 0.16) && aeq(s.keySpringDamping, 0.85)
            && aeq(s.spaceSpringResponse, 0.16) && aeq(s.spaceSpringDamping, 0.88)
            && aeq(s.spaceLeanMultiplier, 0.08) && aeq(s.spaceCursorDragScale, 0.95)
            && aeq(s.popupSpringResponse, 0.20) && aeq(s.popupSpringDamping, 0.85)
        }),
        Preset(name: "Bouncy", apply: { s in
            s.keyBloomScale = 1.20; s.keySpringResponse = 0.34; s.keySpringDamping = 0.45
            s.spaceSpringResponse = 0.36; s.spaceSpringDamping = 0.55
            s.spaceLeanMultiplier = 0.20; s.spaceCursorDragScale = 0.85
            s.popupSpringResponse = 0.40; s.popupSpringDamping = 0.48
        }, matches: { s in
            aeq(s.keyBloomScale, 1.20) && aeq(s.keySpringResponse, 0.34) && aeq(s.keySpringDamping, 0.45)
            && aeq(s.spaceSpringResponse, 0.36) && aeq(s.spaceSpringDamping, 0.55)
            && aeq(s.spaceLeanMultiplier, 0.20) && aeq(s.spaceCursorDragScale, 0.85)
            && aeq(s.popupSpringResponse, 0.40) && aeq(s.popupSpringDamping, 0.48)
        }),
        Preset(name: "Minimal", apply: { s in
            s.keyBloomScale = 1.0; s.keySpringResponse = 0.12; s.keySpringDamping = 1.0
            s.spaceSpringResponse = 0.12; s.spaceSpringDamping = 1.0
            s.spaceLeanMultiplier = 0.0; s.spaceCursorDragScale = 1.0
            s.popupSpringResponse = 0.16; s.popupSpringDamping = 1.0
        }, matches: { s in
            aeq(s.keyBloomScale, 1.0) && aeq(s.keySpringResponse, 0.12) && aeq(s.keySpringDamping, 1.0)
            && aeq(s.spaceSpringResponse, 0.12) && aeq(s.spaceSpringDamping, 1.0)
            && aeq(s.spaceLeanMultiplier, 0.0) && aeq(s.spaceCursorDragScale, 1.0)
            && aeq(s.popupSpringResponse, 0.16) && aeq(s.popupSpringDamping, 1.0)
        }),
    ]

    /// Press linger + backspace auto-repeat timing.
    static let timing: [Preset] = [
        Preset(name: "Default", apply: { s in
            s.keyPressLinger = 0.06; s.repeatHoldDelay = 450
            s.repeatInitialInterval = 110; s.repeatMinInterval = 40; s.repeatAccelStep = 6
        }, matches: { s in
            aeq(s.keyPressLinger, 0.06) && aeq(s.repeatHoldDelay, 450)
            && aeq(s.repeatInitialInterval, 110) && aeq(s.repeatMinInterval, 40) && aeq(s.repeatAccelStep, 6)
        }),
        Preset(name: "Fast", apply: { s in
            s.keyPressLinger = 0.04; s.repeatHoldDelay = 250
            s.repeatInitialInterval = 80; s.repeatMinInterval = 25; s.repeatAccelStep = 10
        }, matches: { s in
            aeq(s.keyPressLinger, 0.04) && aeq(s.repeatHoldDelay, 250)
            && aeq(s.repeatInitialInterval, 80) && aeq(s.repeatMinInterval, 25) && aeq(s.repeatAccelStep, 10)
        }),
        Preset(name: "Relaxed", apply: { s in
            s.keyPressLinger = 0.10; s.repeatHoldDelay = 600
            s.repeatInitialInterval = 150; s.repeatMinInterval = 60; s.repeatAccelStep = 3
        }, matches: { s in
            aeq(s.keyPressLinger, 0.10) && aeq(s.repeatHoldDelay, 600)
            && aeq(s.repeatInitialInterval, 150) && aeq(s.repeatMinInterval, 60) && aeq(s.repeatAccelStep, 3)
        }),
    ]

    /// Overall key size & spacing.
    static let size: [Preset] = [
        Preset(name: "Compact", apply: { s in
            s.keyHeight = 44; s.keyCornerRadius = 10; s.keyWidthFraction = 1
            s.spaceWidth = 6; s.funcKeyWidth = 1.3; s.keySpacing = 1; s.rowSpacing = 2
        }, matches: { s in
            aeq(s.keyHeight, 44) && aeq(s.keyCornerRadius, 10) && aeq(s.keyWidthFraction, 1)
            && aeq(s.spaceWidth, 6) && aeq(s.funcKeyWidth, 1.3) && aeq(s.keySpacing, 1) && aeq(s.rowSpacing, 2)
        }),
        Preset(name: "Default", apply: { s in
            s.keyHeight = 51; s.keyCornerRadius = 13; s.keyWidthFraction = 1
            s.spaceWidth = 7; s.funcKeyWidth = 1.4; s.keySpacing = 1; s.rowSpacing = 4
        }, matches: { s in
            aeq(s.keyHeight, 51) && aeq(s.keyCornerRadius, 13) && aeq(s.keyWidthFraction, 1)
            && aeq(s.spaceWidth, 7) && aeq(s.funcKeyWidth, 1.4) && aeq(s.keySpacing, 1) && aeq(s.rowSpacing, 4)
        }),
        Preset(name: "Large", apply: { s in
            s.keyHeight = 58; s.keyCornerRadius = 16; s.keyWidthFraction = 1
            s.spaceWidth = 7; s.funcKeyWidth = 1.5; s.keySpacing = 2; s.rowSpacing = 6
        }, matches: { s in
            aeq(s.keyHeight, 58) && aeq(s.keyCornerRadius, 16) && aeq(s.keyWidthFraction, 1)
            && aeq(s.spaceWidth, 7) && aeq(s.funcKeyWidth, 1.5) && aeq(s.keySpacing, 2) && aeq(s.rowSpacing, 6)
        }),
    ]
}

// MARK: - Views

/// A horizontal row of preset chips. The chip matching the current settings is
/// filled; if none match (the user has fine-tuned), a "Custom" chip shows
/// instead so the state is never ambiguous.
struct PresetChips: View {
    @Environment(AppModel.self) private var model
    let presets: [Preset]

    var body: some View {
        let active = presets.first { $0.matches(model.settings) }?.name
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
                    chip("Custom", selected: true, tinted: true, action: nil)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    @ViewBuilder
    private func chip(_ title: String, selected: Bool, tinted: Bool = false, action: (() -> Void)?) -> some View {
        let label = Text(title)
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                selected
                    ? (tinted ? AnyShapeStyle(.tint.opacity(0.18)) : AnyShapeStyle(.tint))
                    : AnyShapeStyle(Color(.secondarySystemBackground)),
                in: Capsule())
            .foregroundStyle(selected ? (tinted ? AnyShapeStyle(.tint) : AnyShapeStyle(.white)) : AnyShapeStyle(.primary))
        if let action {
            Button(action: action) { label }.buttonStyle(.plain)
        } else {
            label
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
