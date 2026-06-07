/**
 Hitbox tuning screen — split into two tabs over a live preview with the hitbox
 overlay always on: "General" tunes the static key/bar/icon touch-target sizes,
 "Adaptive" tunes the next-letter-prediction sizing that flexes each key as you
 type (a replication of iOS's native adaptive hitboxes).
 */
import SwiftUI
import iUXiOS

struct HitboxView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabbedPreviewLayout(settings: model.settings, showHitboxOverlay: true, tabs: [
            PreviewTab("General") { GeneralHitboxControls() },
            PreviewTab("Adaptive") { AdaptiveHitboxControls() },
        ])
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
                      subtitle: "Predict your next letter and quietly enlarge the likely keys (and shrink the unlikely ones) without moving them — like the native keyboard",
                      isOn: $model.settings.adaptiveHitboxes)
        }
        if model.settings.adaptiveHitboxes {
            CardSection("Fine tuning") {
                SliderRow("Grow likely keys", value: $model.settings.adaptiveGrow,
                          in: 1.0...1.6, step: 0.05) {
                    $0 == 1.0 ? "Off" : "+\(Int((($0 - 1) * 100).rounded()))%"
                }
                Divider()
                SliderRow("Shrink unlikely keys", value: $model.settings.adaptiveShrink,
                          in: 0.6...1.0, step: 0.05) {
                    $0 == 1.0 ? "Off" : "−\(Int(((1 - $0) * 100).rounded()))%"
                }
                Divider()
                SliderRow("Prediction strength", value: $model.settings.adaptivePredictionWeight,
                          in: 0.0...1.0, step: 0.05) {
                    "\(Int(($0 * 100).rounded()))%"
                }
            }
            CardSection("Behaviour") {
                ToggleRow("Predict at word start",
                          subtitle: "Bias toward common opening letters before you've typed anything; off keeps the keys neutral until there's a letter to predict from",
                          isOn: $model.settings.adaptivePredictAtWordStart)
            }
        }
    }
}
