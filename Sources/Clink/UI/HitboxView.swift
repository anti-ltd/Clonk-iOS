/**
 Hitbox tuning screen. One scrolling page, no tabs:

   • Hitboxes — a size preset + the raw key/bar/icon target sliders in one
                collapsed "Fine-tune" disclosure.
   • Adaptive — the next-letter-prediction toggle (a replica of iOS's native
                adaptive hitboxes), with its tuning knobs collapsed.

 Live preview keeps the hitbox overlay on, so every change is visible.
 `$model.settings` bindings persist via `AppModel.settings` `didSet`.


 Module: app-ui · Target: Clink
 Learn: docs/09-app-ui.md
 */
import SwiftUI
import iUXiOS

/// Static + adaptive touch-target sizing — the Hitboxes tab content of the Keys
/// page (the page turns on the preview's hitbox overlay).
struct HitboxControls: View {
    var body: some View {
        GeneralHitboxControls()
        AdaptiveHitboxControls()
    }
}

/// Static touch-target sizing for the keys, suggestion bar, and panel icon.
private struct GeneralHitboxControls: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        CardSection("Hitboxes") {
            PresetChips(presets: TuningPresets.hitbox)
                .padding(.vertical, UX.rowVPadding)
            FineTune {
                SliderRow("Hitbox size",
                          tooltip: "Scales all key touch targets at once. Raise it if you miss keys often.",
                          value: $model.settings.hitboxScale,
                          in: 0.75...1.25, step: 0.05) {
                    $0 == 1.0 ? "Default" : "\(Int(($0 * 100).rounded()))%"
                }
                // Bar / icon targets sit above the keys and carry their own
                // hitbox multipliers. The suggestion bar's is shown disabled
                // when the bar is off; the panel icon's stays conditional on
                // the icon actually being available.
                Divider()
                SliderRow("Suggestion bar",
                          tooltip: "Touch target height for suggestion chips. Raise it if you often miss a tap.",
                          value: $model.settings.suggestionHitboxScale,
                          in: 0.75...1.5, step: 0.05) {
                    $0 == 1.0 ? "Default" : "\(Int(($0 * 100).rounded()))%"
                }
                .gated(model.settings.suggestionsEnabled,
                       reason: "Turn on the Suggestion bar to size it.")
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
    }

    private var panelIconAvailable: Bool {
        model.settings.clipboardEnabled
            || model.settings.notepadEnabled
            || model.settings.emojiEnabled
    }
}

/// Next-letter-prediction sizing — the toggle and its fine-tuning knobs.
private struct AdaptiveHitboxControls: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        CardSection("Adaptive") {
            ToggleRow("Adaptive hitboxes",
                      subtitle: "Predicts your next letter and silently enlarges likely keys without moving them, like the native keyboard.",
                      isOn: $model.settings.adaptiveHitboxes)
            FineTune(enabledWhen: model.settings.adaptiveHitboxes,
                     reason: "Turn on Adaptive hitboxes to fine-tune the prediction.") {
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
                Divider()
                ToggleRow("Predict at word start",
                          subtitle: "Bias toward common opening letters before you've typed anything. Off keeps keys neutral until there's a letter to predict from.",
                          isOn: $model.settings.adaptivePredictAtWordStart)
            }
        }
    }
}

#if DEBUG
#Preview { KeysView().clinkPreview() }
#endif
