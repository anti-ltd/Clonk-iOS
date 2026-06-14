/**
 Animation tuning screen. One scrolling page, no tabs:

   • Feel    — a preset row (one tap sets the whole feel) + the primary Bloom
               slider, with every advanced spring/timing knob tucked inside one
               collapsed "Fine-tune" disclosure (key speed/springiness, instant,
               linger, min-highlight, glass return, space bar, popup).
   • Effects — the optional, self-contained flair: tap flash (strength + look),
               glow, press style, entrance. Each gates on its own strength —
               there is no master switch.

 The pinned live preview sits above; `$model.settings` bindings persist via
 `AppModel.settings` `didSet`.


 Module: app-ui · Target: Clink
 Learn: docs/09-app-ui.md
 */
import SwiftUI
import iUXiOS

/// Key-press feel + effects tuning with a pinned live preview, as a single
/// calm scroll: presets up top, advanced knobs collapsed by default.
struct AnimationView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @State private var fineTuneExpanded = false

    private var themeAccent: Color {
        model.settings.resolvedTheme(dark: colorScheme == .dark).accent.color
    }

    /// The glass-return dial only does anything on a Liquid Glass theme (solid
    /// themes have no neighbour merge), so it's shown only then.
    private var isGlassTheme: Bool {
        model.settings.resolvedTheme(dark: colorScheme == .dark).material == .liquidGlass
    }

    var body: some View {
        @Bindable var model = model
        PinnedPreviewLayout(settings: model.settings, previewColorScheme: nil) {
            feelCard(model: model)
            effectsCard(model: model)
            Text("Effects are optional and run only on press or appearance — never in the typing hot path, so the keyboard stays fast. Works on Liquid Glass and solid themes alike.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 4)
        }
        .navigationTitle("Animation")
        .navigationBarTitleDisplayMode(.inline)
        .tint(themeAccent)
    }

    // MARK: - Feel

    @ViewBuilder
    private func feelCard(model: AppModel) -> some View {
        @Bindable var model = model
        CardSection("Feel") {
            PresetChips(presets: TuningPresets.animation)
                .padding(.vertical, UX.rowVPadding)
            Divider()
            SliderRow("Bloom",
                      tooltip: "How much a key scales up when pressed. 100% is off. Higher values give a more exaggerated pop. On Liquid Glass themes a large bloom is automatically softened so the neighbour-merge stays smooth on older devices — you set one value, it stays fast everywhere.",
                      value: $model.settings.keyBloomScale,
                      in: 1.0...1.4, step: 0.02) {
                $0 == 1.0 ? "Off" : "\(Int(($0 * 100).rounded()))%"
            }
            Divider()
            DisclosureGroup("Fine-tune", isExpanded: $fineTuneExpanded) {
                VStack(spacing: 0) {
                    keyFineTune(model: model)
                    spaceFineTune(model: model)
                    popupFineTune(model: model)
                }
                .padding(.top, 6)
            }
            .tint(.primary)
            .padding(.vertical, UX.rowVPadding)
        }
    }

    /// Advanced key-press knobs (spring + timing), collapsed inside Fine-tune.
    @ViewBuilder
    private func keyFineTune(model: AppModel) -> some View {
        @Bindable var model = model
        ToggleRow("Instant highlight",
                  subtitle: "Keys snap instantly to their bloom size with no spring, like the stock keyboard.",
                  isOn: $model.settings.keyPressInstant)
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
        if isGlassTheme {
            Divider()
            SliderRow("Return on glass",
                      tooltip: "Base speed a key settles back to rest on Liquid Glass themes (the press itself still uses Speed above). Lower is snappier. A bigger Bloom automatically eases back a little longer so the larger collapse stays smooth.",
                      value: $model.settings.glassReleaseResponse,
                      in: 0.06...0.4, step: 0.02) {
                String(format: "%.2fs", $0)
            }
        }
    }

    /// Space-bar spring + drag knobs, inside Fine-tune.
    @ViewBuilder
    private func spaceFineTune(model: AppModel) -> some View {
        @Bindable var model = model
        fineTuneHeader("Space bar")
        SliderRow("Bloom",
                  tooltip: "How much the space bar expands when tapped.",
                  value: $model.settings.spaceBloomScale,
                  in: 1.0...1.2, step: 0.01) {
            $0 <= 1.001 ? "Off" : "\(Int(($0 * 100).rounded()))%"
        }
        Divider()
        SliderRow("Speed",
                  tooltip: "How fast the space-bar spring settles. Lower is snappier.",
                  value: $model.settings.spaceSpringResponse,
                  in: 0.08...0.6, step: 0.02) {
            String(format: "%.2fs", $0)
        }
        Divider()
        SliderRow("Springiness",
                  tooltip: "How much the space-bar spring bounces. Lower bounces more, 1.0 settles cleanly.",
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

    /// Popup spring knobs, inside Fine-tune (only when popups are on).
    @ViewBuilder
    private func popupFineTune(model: AppModel) -> some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            fineTuneHeader("Popup")
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
        .gated(model.settings.keyPopupEnabled,
               reason: "Turn on key popups (Popups settings) to tune these.")
    }

    /// A small group label between blocks inside the Fine-tune disclosure.
    @ViewBuilder
    private func fineTuneHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 14)
            .padding(.bottom, 2)
    }

    // MARK: - Effects

    @ViewBuilder
    private func effectsCard(model: AppModel) -> some View {
        @Bindable var model = model
        // Each effect is self-contained — "off" when its own strength is 0, on
        // independently of the others. No master switch, nothing greyed out by
        // another control (except the tap-flash look, which needs the flash on).
        let flashOn = model.settings.tapFlashStrength >= 0.005
        CardSection("Effects") {
            SliderRow("Tap flash",
                      tooltip: "Brightness burst on the key cap at the moment of the press. 0% turns it off. Fires on every tap, independent of the bloom.",
                      value: $model.settings.tapFlashStrength,
                      in: 0...0.7, step: 0.02) {
                $0 < 0.005 ? "Off" : "\(Int(($0 * 100).rounded()))%"
            }
            Group {
                Divider()
                ToggleRow("Accent flash",
                          subtitle: "Flash the key in the theme accent instead of white.",
                          isOn: $model.settings.tapFlashAccent)
                Divider()
                ToggleRow("Ring flash",
                          subtitle: "Burst an outline around the key instead of a filled wash.",
                          isOn: $model.settings.tapFlashRing)
            }
            .disabled(!flashOn)
            .opacity(flashOn ? 1 : 0.4)
            .animation(Motion.settingsReveal.animation, value: flashOn)

            Divider()
            SliderRow("Glow",
                      tooltip: "A soft accent-coloured halo behind each key while it's held. 0% turns it off. Only the keys you're touching glow, and it eases off automatically under low power or heat.",
                      value: $model.settings.keyPressGlow,
                      in: 0...1, step: 0.05) {
                $0 <= 0.001 ? "Off" : "\(Int(($0 * 100).rounded()))%"
            }

            Divider()
            chipRow("Press style",
                    caption: "The shape of the press — grow, press in, or wobble. Applies when Bloom is on.") {
                OptionChips(options: KeyPressStyle.allCases.map { ($0.label, $0) },
                            selection: $model.settings.keyPressStyle)
                    .tint(themeAccent)
            }

            Divider()
            chipRow("Entrance",
                    caption: "How the keyboard animates in each time it opens.") {
                OptionChips(options: KeyboardEntrance.allCases.map { ($0.label, $0) },
                            selection: $model.settings.keyboardEntrance)
                    .tint(themeAccent)
            }
        }
    }

    /// A labelled option-chip row for the effects card (press style, entrance).
    /// Takes the chips as content so it stays clear of `OptionChips`' generics.
    @ViewBuilder
    private func chipRow<Content: View>(_ title: String, caption: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.medium))
            Text(caption).font(.caption).foregroundStyle(.secondary)
            content()
        }
        .padding(.vertical, UX.rowVPadding)
    }
}

#if DEBUG
#Preview { AnimationView().clinkPreview() }
#endif
