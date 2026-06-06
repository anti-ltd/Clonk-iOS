/**
 Touch and feel tuning screen. Three tabs — Touch, Spring, Timing — each with a
 preset chip row above the raw sliders in a `TunedSection` disclosure group.
 */
import SwiftUI
import iUXiOS

/// Low-level keyboard tuning: touch hitbox + cursor, spring physics, and timing.
/// App-level management (backup/restore + reset) lives under Setup now — this
/// screen is purely the dials that change how the keyboard feels to touch.
struct AdvancedSettingsView: View {
    private enum Tab { case touch, spring, timing }

    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedTab: Tab = .touch
    @State private var previewDark: Bool = false

    var body: some View {
        @Bindable var model = model
        PinnedPreviewLayout(settings: model.settings,
                            showHitboxOverlay: selectedTab == .touch,
                            previewColorScheme: model.settings.matchSystemAppearance
                                ? (previewDark ? .dark : .light)
                                : nil) {
            Picker("", selection: $selectedTab) {
                Text("Touch").tag(Tab.touch)
                Text("Spring").tag(Tab.spring)
                Text("Timing").tag(Tab.timing)
            }
            .pickerStyle(.segmented)
            .padding(.bottom, 4)

            switch selectedTab {
            case .touch:
                touchTab(model: model)
            case .spring:
                springTab(model: model)
            case .timing:
                timingTab(model: model)
            }
        }
        .navigationTitle("Touch & Feel")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if model.settings.matchSystemAppearance {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { previewDark.toggle() } label: {
                        Image(systemName: previewDark ? "moon.fill" : "sun.max")
                    }
                }
            }
        }
        .onAppear { previewDark = colorScheme == .dark }
    }

    // MARK: - Tabs

    @ViewBuilder
    private func touchTab(model: AppModel) -> some View {
        @Bindable var model = model
        TunedSection(title: "Hitbox", presets: TuningPresets.hitbox) {
            SliderRow("Hitbox size", value: $model.settings.hitboxScale,
                      in: 0.75...1.25, step: 0.05) {
                $0 == 1.0 ? "Default" : "\(Int(($0 * 100).rounded()))%"
            }
            // Bar / icon targets sit above the keys and carry their own hitbox
            // multipliers — only offered when each element is actually shown.
            if model.settings.suggestionsEnabled {
                Divider()
                SliderRow("Suggestion bar", value: $model.settings.suggestionHitboxScale,
                          in: 0.75...1.5, step: 0.05) {
                    $0 == 1.0 ? "Default" : "\(Int(($0 * 100).rounded()))%"
                }
            }
            if model.settings.activateWithIcon && panelIconAvailable {
                Divider()
                SliderRow("Panel icon", value: $model.settings.panelButtonHitboxScale,
                          in: 0.75...1.5, step: 0.05) {
                    $0 == 1.0 ? "Default" : "\(Int(($0 * 100).rounded()))%"
                }
            }
        }
        CardSection("Cursor") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Movement type").foregroundStyle(.secondary).font(.subheadline)
                Picker("Movement type", selection: $model.settings.cursorMovementType) {
                    ForEach(CursorMovementType.allCases) { type in
                        Text(type.label).tag(type)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(.vertical, UX.rowVPadding)
            Divider()
            Text(cursorHelpText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, UX.rowVPadding)
        }
        TunedSection(title: "Cursor feel", presets: TuningPresets.cursor) {
            SliderRow("Activation time",
                      value: $model.settings.spaceCursorActivationDelay,
                      in: 0...500, step: 25) {
                $0 < 5 ? "Instant" : "\(Int($0))ms"
            }
            Divider()
            SliderRow("Scroll sensitivity",
                      value: Binding(
                        get: { 30 - model.settings.spaceCursorStride },
                        set: { model.settings.spaceCursorStride = 30 - $0 }),
                      in: 8...24, step: 2) {
                $0 == 20 ? "Default" : "\(Int(($0 / 20 * 100).rounded()))%"
            }
            Divider()
            SliderRow("Line length",
                      value: $model.settings.cursorLineStride,
                      in: 5...80, step: 5) {
                "\(Int($0)) chars"
            }
        }
    }

    @ViewBuilder
    private func springTab(model: AppModel) -> some View {
        @Bindable var model = model
        TunedSection(title: "Animation", presets: TuningPresets.animation) {
            fineTuneHeader("Key press")
            SliderRow("Bloom", value: $model.settings.keyBloomScale,
                      in: 1.0...1.4, step: 0.02) {
                $0 == 1.0 ? "Off" : "\(Int(($0 * 100).rounded()))%"
            }
            Divider()
            SliderRow("Speed", value: $model.settings.keySpringResponse,
                      in: 0.08...0.6, step: 0.02) {
                String(format: "%.2fs", $0)
            }
            Divider()
            SliderRow("Springiness", value: $model.settings.keySpringDamping,
                      in: 0.3...1.0, step: 0.05) {
                $0 >= 0.99 ? "Firm" : String(format: "%.2f", $0)
            }

            fineTuneHeader("Space bar")
            SliderRow("Speed", value: $model.settings.spaceSpringResponse,
                      in: 0.08...0.6, step: 0.02) {
                String(format: "%.2fs", $0)
            }
            Divider()
            SliderRow("Springiness", value: $model.settings.spaceSpringDamping,
                      in: 0.3...1.0, step: 0.05) {
                $0 >= 0.99 ? "Firm" : String(format: "%.2f", $0)
            }
            Divider()
            SliderRow("Lean", value: $model.settings.spaceLeanMultiplier,
                      in: 0...0.3, step: 0.01) {
                $0 == 0 ? "Off" : String(format: "%.2f×", $0)
            }
            Divider()
            SliderRow("Cursor shrink", value: $model.settings.spaceCursorDragScale,
                      in: 0.7...1.0, step: 0.02) {
                $0 >= 0.99 ? "Off" : "\(Int(($0 * 100).rounded()))%"
            }

            fineTuneHeader("Popup")
            SliderRow("Speed", value: $model.settings.popupSpringResponse,
                      in: 0.08...0.6, step: 0.02) {
                String(format: "%.2fs", $0)
            }
            Divider()
            SliderRow("Springiness", value: $model.settings.popupSpringDamping,
                      in: 0.3...1.0, step: 0.05) {
                $0 >= 0.99 ? "Firm" : String(format: "%.2f", $0)
            }
        }
    }

    @ViewBuilder
    private func timingTab(model: AppModel) -> some View {
        @Bindable var model = model
        TunedSection(title: "Backspace & linger", presets: TuningPresets.timing) {
            fineTuneHeader("Key press")
            SliderRow("Press linger", value: $model.settings.keyPressLinger,
                      in: 0...0.4, step: 0.02) {
                $0 < 0.005 ? "Off" : "\(Int(($0 * 1000).rounded()))ms"
            }

            fineTuneHeader("Backspace repeat")
            Text("How long to hold the key before rapid-delete begins, and how fast it accelerates.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, UX.rowVPadding)
            Divider()
            SliderRow("Hold delay", value: $model.settings.repeatHoldDelay,
                      in: 150...800, step: 25) {
                "\(Int($0))ms"
            }
            Divider()
            SliderRow("Start speed", value: $model.settings.repeatInitialInterval,
                      in: 50...200, step: 10) {
                "\(Int($0))ms"
            }
            Divider()
            SliderRow("Max speed", value: $model.settings.repeatMinInterval,
                      in: 20...80, step: 5) {
                "\(Int($0))ms"
            }
            Divider()
            SliderRow("Acceleration", value: $model.settings.repeatAccelStep,
                      in: 1...20, step: 1) {
                "\(Int($0))ms/step"
            }
        }
    }

    /// A small group heading used inside a "Fine-tune" disclosure to separate the
    /// raw sliders into their original sub-groups.
    @ViewBuilder
    private func fineTuneHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 14)
            .padding(.bottom, 2)
    }

    // MARK: - Helpers

    /// Whether the top-left panel icon can appear at all — i.e. at least one
    /// action panel is enabled. (Clipboard also needs Full Access at runtime, but
    /// the slider is harmless to offer regardless.)
    private var panelIconAvailable: Bool {
        model.settings.clipboardEnabled
            || model.settings.notepadEnabled
            || model.settings.emojiEnabled
    }

    private var cursorHelpText: String {
        switch model.settings.cursorMovementType {
        case .spacebar:
            return "Slide on the space bar to move the cursor — left/right by characters, up/down by lines. Raise the activation time so the cursor only engages when you hold deliberately; lower the sensitivity if it still triggers by accident."
        case .trackpad:
            return "Hold the space bar to turn the keyboard into a trackpad — drag to move the cursor (left/right by characters, up/down by lines), then lift to return to the keys. Raise the activation time so it only engages on a deliberate hold; lower the sensitivity if it triggers by accident."
        case .combined:
            return "Type as normal — but hold the space bar and the keys blank out and stop responding while you drag the cursor (left/right by characters, up/down by lines), with the space bar morphing. Lift to return to the keys."
        }
    }
}
