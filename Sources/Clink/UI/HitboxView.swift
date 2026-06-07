/**
 Hitbox tuning screen — key touch-target sizes with a live overlay showing the
 actual hit areas on the keyboard preview.
 */
import SwiftUI
import iUXiOS

struct HitboxView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        PinnedPreviewLayout(settings: model.settings, showHitboxOverlay: true) {
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
        .navigationTitle("Hitboxes")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var panelIconAvailable: Bool {
        model.settings.clipboardEnabled
            || model.settings.notepadEnabled
            || model.settings.emojiEnabled
    }
}
