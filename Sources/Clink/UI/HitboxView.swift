/**
 Hitbox tuning screen — General tab (static key/bar/icon touch-target sizes) and
 Adaptive tab (next-letter-prediction sizing that flexes each key as you type, a
 replication of iOS's native adaptive hitboxes). Live preview with the hitbox
 overlay always on, so every change is visible.
 

 Module: app-ui · Target: Clink
 Learn: docs/09-app-ui.md
 */
import SwiftUI
import iUXiOS

struct HitboxView: View {
    private enum Tab { case general, adaptive }

    @Environment(AppModel.self) private var model
    @State private var selectedTab: Tab = .general

    var body: some View {
        @Bindable var model = model
        PinnedPreviewLayout(settings: model.settings,
                            showHitboxOverlay: true,
                            bottomBar: AnyView(
                                ThemedTabPicker(
                                    options: [("General", Tab.general), ("Adaptive", Tab.adaptive)],
                                    selection: $selectedTab)
                            )) {
            switch selectedTab {
            case .general:
                GeneralHitboxControls()
            case .adaptive:
                AdaptiveHitboxControls()
            }
        }
        .navigationTitle("Hitboxes")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Static touch-target sizing for the keys, suggestion bar, and panel icon.
private struct GeneralHitboxControls: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        CardSection("Presets") {
            PresetChips(presets: TuningPresets.hitbox)
                .padding(.vertical, UX.rowVPadding)
        }
        CardSection("Values") {
            SliderRow("Hitbox size",
                      tooltip: "Scales all key touch targets at once. Raise it if you miss keys often.",
                      value: $model.settings.hitboxScale,
                      in: 0.75...1.25, step: 0.05) {
                $0 == 1.0 ? "Default" : "\(Int(($0 * 100).rounded()))%"
            }
            // Bar / icon targets sit above the keys and carry their own hitbox
            // multipliers — only offered when each element is actually shown.
            if model.settings.suggestionsEnabled {
                Divider()
                SliderRow("Suggestion bar",
                          tooltip: "Touch target height for suggestion chips. Raise it if you often miss a tap.",
                          value: $model.settings.suggestionHitboxScale,
                          in: 0.75...1.5, step: 0.05) {
                    $0 == 1.0 ? "Default" : "\(Int(($0 * 100).rounded()))%"
                }
            }
            if model.settings.activateWithIcon && panelIconAvailable {
                Divider()
                SliderRow("Panel icon",
                          tooltip: "Touch target size for the panel button. Raise it if you frequently miss it.",
                          value: $model.settings.panelButtonHitboxScale,
                          in: 0.75...1.5, step: 0.05) {
                    $0 == 1.0 ? "Default" : "\(Int(($0 * 100).rounded()))%"
                }
            }
        }
    }

    private var panelIconAvailable: Bool {
        model.settings.clipboardEnabled
            || model.settings.notepadEnabled
            || model.settings.emojiEnabled
    }
}

/// Next-letter-prediction sizing — the master toggle and its fine-tuning knobs.
private struct AdaptiveHitboxControls: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        CardSection("Adaptive") {
            ToggleRow("Adaptive hitboxes",
                      subtitle: "Predicts your next letter and silently enlarges likely keys without moving them, like the native keyboard.",
                      isOn: $model.settings.adaptiveHitboxes)
        }
        if model.settings.adaptiveHitboxes {
            CardSection("Fine tuning") {
                SliderRow("Grow likely keys",
                          tooltip: "How much the predicted next-letter keys expand beyond their normal size.",
                          value: $model.settings.adaptiveGrow,
                          in: 1.0...1.6, step: 0.05) {
                    $0 == 1.0 ? "Off" : "+\(Int((($0 - 1) * 100).rounded()))%"
                }
                Divider()
                SliderRow("Shrink unlikely keys",
                          tooltip: "How much low-probability keys shrink to make room for the likely ones.",
                          value: $model.settings.adaptiveShrink,
                          in: 0.6...1.0, step: 0.05) {
                    $0 == 1.0 ? "Off" : "−\(Int(((1 - $0) * 100).rounded()))%"
                }
                Divider()
                SliderRow("Prediction strength",
                          tooltip: "How strongly predictions affect the hitboxes. Lower is subtle, higher pushes the bias harder.",
                          value: $model.settings.adaptivePredictionWeight,
                          in: 0.0...1.0, step: 0.05) {
                    "\(Int(($0 * 100).rounded()))%"
                }
            }
            CardSection("Behaviour") {
                ToggleRow("Predict at word start",
                          subtitle: "Bias toward common opening letters before you've typed anything. Off keeps keys neutral until there's a letter to predict from.",
                          isOn: $model.settings.adaptivePredictAtWordStart)
            }
        }
    }
}

#if DEBUG
#Preview { HitboxView().clinkPreview() }
#endif
