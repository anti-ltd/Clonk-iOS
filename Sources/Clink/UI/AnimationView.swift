/**
 Animation tuning screen. Three tabs — Spring, Timing, Effects. Spring tab shows
 three cards (Keys, Space bar, Popup); the Popup card is hidden when popups are
 off. Effects holds the optional flair: press style, tap-flash look, key glow,
 and the keyboard entrance animation.


 Module: app-ui · Target: Clink
 Learn: docs/09-app-ui.md
 */
import SwiftUI
import iUXiOS

/// Spring physics and press-timing tuning with a pinned live preview.
/// `$model.settings` bindings persist via `AppModel.settings` `didSet`.
struct AnimationView: View {
    private enum Tab { case spring, timing, effects }

    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedTab: Tab = .spring

    private var themeAccent: Color {
        model.settings.resolvedTheme(dark: colorScheme == .dark).accent.color
    }

    /// The glass-press dials only do anything on a Liquid Glass theme (solid
    /// themes have no neighbour merge), so the card is shown only then.
    private var isGlassTheme: Bool {
        model.settings.resolvedTheme(dark: colorScheme == .dark).material == .liquidGlass
    }

    var body: some View {
        @Bindable var model = model
        PinnedPreviewLayout(settings: model.settings,
                            previewColorScheme: nil,
                            bottomBar: AnyView(
                                ThemedTabPicker(
                                    options: [("Spring", Tab.spring), ("Timing", Tab.timing), ("Effects", Tab.effects)],
                                    selection: $selectedTab)
                            )) {
            switch selectedTab {
            case .spring:
                springTab(model: model)
            case .timing:
                timingTab(model: model)
            case .effects:
                effectsTab(model: model)
            }
        }
        .navigationTitle("Animation")
        .navigationBarTitleDisplayMode(.inline)
        .tint(themeAccent)
    }

    // MARK: - Tabs

    @ViewBuilder
    private func springTab(model: AppModel) -> some View {
        @Bindable var model = model
        CardSection("Key press") {
            ToggleRow("Liquid key press",
                      subtitle: "Bloom and warp each key on press. Works best on Liquid Glass.",
                      isOn: $model.settings.keyPressWarp)
            Divider()
            ToggleRow("Instant highlight",
                      subtitle: "Keys snap instantly to their bloom size with no spring, like the stock keyboard.",
                      isOn: $model.settings.keyPressInstant)
            .disabled(!model.settings.keyPressWarp)
            .opacity(model.settings.keyPressWarp ? 1 : 0.4)
        }
        CardSection("Keys") {
            PresetChips(presets: TuningPresets.animation)
                .padding(.vertical, UX.rowVPadding)
            Divider()
            SliderRow("Bloom",
                      tooltip: "How much a key scales up when pressed. Higher values give a more exaggerated pop.",
                      value: $model.settings.keyBloomScale,
                      in: 1.0...1.4, step: 0.02) {
                $0 == 1.0 ? "Off" : "\(Int(($0 * 100).rounded()))%"
            }
            if !model.settings.keyPressInstant {
                Divider()
                SliderRow("Speed",
                          tooltip: "How fast the spring settles. Lower is snappier, higher is more relaxed.",
                          value: $model.settings.keySpringResponse,
                          in: 0.08...0.6, step: 0.02) {
                    String(format: "%.2fs", $0)
                }
                Divider()
                SliderRow("Springiness",
                          tooltip: "How much the spring bounces. Lower bounces more, 1.0 settles cleanly.",
                          value: $model.settings.keySpringDamping,
                          in: 0.3...1.0, step: 0.05) {
                    $0 >= 0.99 ? "Firm" : String(format: "%.2f", $0)
                }
            }
            Divider()
            SliderRow("Tap flash",
                      tooltip: "Brightness burst on the key cap at the moment of the press.",
                      value: $model.settings.tapFlashStrength,
                      in: 0...0.7, step: 0.02) {
                $0 < 0.005 ? "Off" : "\(Int(($0 * 100).rounded()))%"
            }
        }
        .animation(Motion.settingsReveal.animation, value: model.settings.keyPressInstant)
        Group {
            if isGlassTheme {
                CardSection("Liquid Glass") {
                    SliderRow("Bloom on glass",
                              tooltip: "How much a key grows when pressed on Liquid Glass themes. A pressed key liquid-merges with its neighbours, which is expensive to redraw on older devices — lower keeps that merge gentler and smoother. 0% removes the size bloom (the tap flash still fires).",
                              value: $model.settings.glassBloomFactor,
                              in: 0...1, step: 0.05) {
                        $0 <= 0.001 ? "Off" : "\(Int(($0 * 100).rounded()))%"
                    }
                    Divider()
                    SliderRow("Return on glass",
                              tooltip: "Base speed a key settles back to rest on Liquid Glass themes (the press itself still uses the Keys speed above). Lower is snappier. A bigger Bloom automatically eases back a little longer than this so the larger collapse stays smooth instead of jumping.",
                              value: $model.settings.glassReleaseResponse,
                              in: 0.06...0.4, step: 0.02) {
                        String(format: "%.2fs", $0)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(Motion.settingsReveal.animation, value: isGlassTheme)
        CardSection("Space bar") {
            PresetChips(presets: TuningPresets.spaceBar)
                .padding(.vertical, UX.rowVPadding)
            Divider()
            SliderRow("Bloom",
                      tooltip: "How much the space bar expands when tapped.",
                      value: $model.settings.spaceBloomScale,
                      in: 1.0...1.2, step: 0.01) {
                $0 <= 1.001 ? "Off" : "\(Int(($0 * 100).rounded()))%"
            }
            Divider()
            SliderRow("Speed",
                      tooltip: "How fast the spring settles. Lower is snappier, higher is more relaxed.",
                      value: $model.settings.spaceSpringResponse,
                      in: 0.08...0.6, step: 0.02) {
                String(format: "%.2fs", $0)
            }
            Divider()
            SliderRow("Springiness",
                      tooltip: "How much the spring bounces. Lower bounces more, 1.0 settles cleanly.",
                      value: $model.settings.spaceSpringDamping,
                      in: 0.3...1.0, step: 0.05) {
                $0 >= 0.99 ? "Firm" : String(format: "%.2f", $0)
            }
            Divider()
            SliderRow("Lean",
                      tooltip: "How much the space bar tilts in the direction you're sliding the cursor.",
                      value: $model.settings.spaceLeanMultiplier,
                      in: 0...0.3, step: 0.01) {
                $0 == 0 ? "Off" : String(format: "%.2f×", $0)
            }
            Divider()
            SliderRow("Cursor shrink",
                      tooltip: "How much the cursor narrows while you drag it across the space bar.",
                      value: $model.settings.spaceCursorDragScale,
                      in: 0.7...1.0, step: 0.02) {
                $0 >= 0.99 ? "Off" : "\(Int(($0 * 100).rounded()))%"
            }
        }
        Group {
            if model.settings.keyPopupEnabled {
                CardSection("Popup") {
                    PresetChips(presets: TuningPresets.popup)
                        .padding(.vertical, UX.rowVPadding)
                    Divider()
                    SliderRow("Speed",
                              tooltip: "Spring response time for the popup appearing and disappearing.",
                              value: $model.settings.popupSpringResponse,
                              in: 0.08...0.6, step: 0.02) {
                        String(format: "%.2fs", $0)
                    }
                    Divider()
                    SliderRow("Springiness",
                              tooltip: "How much the popup bounces on entry. Lower values add more spring.",
                              value: $model.settings.popupSpringDamping,
                              in: 0.3...1.0, step: 0.05) {
                        $0 >= 0.99 ? "Firm" : String(format: "%.2f", $0)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(Motion.settingsReveal.animation, value: model.settings.keyPopupEnabled)
    }

    @ViewBuilder
    private func timingTab(model: AppModel) -> some View {
        @Bindable var model = model
        CardSection("Key press") {
            SliderRow("Press linger",
                      tooltip: "How long the key stays in its pressed state before bouncing back. Adds a weighted feel.",
                      value: $model.settings.keyPressLinger,
                      in: 0...0.4, step: 0.02) {
                $0 < 0.005 ? "Off" : "\(Int(($0 * 1000).rounded()))ms"
            }
            Divider()
            SliderRow("Min highlight",
                      tooltip: "Shortest time a key stays lit after you tap it. Raise this if keys near the screen edge type but don't visibly highlight on a quick tap.",
                      value: $model.settings.minPressVisible,
                      in: 0...0.25, step: 0.01) {
                $0 < 0.005 ? "Off" : "\(Int(($0 * 1000).rounded()))ms"
            }
        }
    }

    @ViewBuilder
    private func effectsTab(model: AppModel) -> some View {
        @Bindable var model = model
        let warpOn = model.settings.keyPressWarp

        CardSection("Press style") {
            VStack(alignment: .leading, spacing: 8) {
                Text("The shape of the press — grow, press in, or wobble.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                OptionChips(
                    options: KeyPressStyle.allCases.map { ($0.label, $0) },
                    selection: $model.settings.keyPressStyle
                )
                .tint(themeAccent)
            }
            .padding(.vertical, UX.rowVPadding)
        }
        .disabled(!warpOn)
        .opacity(warpOn ? 1 : 0.4)

        CardSection("Tap flash") {
            ToggleRow("Accent colour",
                      subtitle: "Flash the key in the theme accent instead of white when you tap.",
                      isOn: $model.settings.tapFlashAccent)
            Divider()
            ToggleRow("Ring",
                      subtitle: "Burst an outline around the key instead of a filled wash.",
                      isOn: $model.settings.tapFlashRing)
        }
        .disabled(!warpOn || model.settings.tapFlashStrength < 0.005)
        .opacity(warpOn && model.settings.tapFlashStrength >= 0.005 ? 1 : 0.4)

        CardSection("Glow") {
            SliderRow("Press glow",
                      tooltip: "A soft accent-coloured halo behind each key while it's held. Only the keys you're touching glow, and it eases off automatically under low power or heat.",
                      value: $model.settings.keyPressGlow,
                      in: 0...1, step: 0.05) {
                $0 <= 0.001 ? "Off" : "\(Int(($0 * 100).rounded()))%"
            }
        }
        .disabled(!warpOn)
        .opacity(warpOn ? 1 : 0.4)

        CardSection("Entrance") {
            VStack(alignment: .leading, spacing: 8) {
                Text("How the keyboard animates in each time it opens.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                OptionChips(
                    options: KeyboardEntrance.allCases.map { ($0.label, $0) },
                    selection: $model.settings.keyboardEntrance
                )
                .tint(themeAccent)
            }
            .padding(.vertical, UX.rowVPadding)
        }

        Text("All effects are optional and run only on press or appearance — they never sit in the typing hot path, so the keyboard stays as fast as ever. Works on both Liquid Glass and solid themes.")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 4)
    }
}

#if DEBUG
#Preview { AnimationView().clinkPreview() }
#endif
