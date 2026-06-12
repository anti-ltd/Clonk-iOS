/**
 Response settings — gesture timing & thresholds. How long a hold takes to fire
 a long-press (accent bar, emoji skin tones) and how far a slide must travel to
 trigger the 123 slide-up. Presets up top, raw sliders below.
 

 Module: app-ui · Target: Clink
 Learn: docs/09-app-ui.md
 */
import SwiftUI
import iUXiOS

/// Tuning for the keyboard's gesture *response*: long-press delays and the
/// slide-up trigger distance. These are the thresholds that decide how eager the
/// keyboard is to read a hold or a swipe — distinct from the spring/animation
/// feel (Animation) and the touch-target sizes (Hitboxes).
struct ResponseView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        PinnedPreviewLayout(settings: model.settings,
                            previewColorScheme: nil) {
            CardSection("Presets") {
                PresetChips(presets: TuningPresets.response)
                    .padding(.vertical, UX.rowVPadding)
            }

            CardSection("Long press") {
                SliderRow("Accent delay",
                          tooltip: "How long to hold a letter key before the accent picker appears.",
                          value: $model.settings.accentHoldDelay,
                          in: 150...900, step: 25) { "\(Int($0))ms" }
                Divider()
                SliderRow("Emoji tone delay",
                          tooltip: "How long to hold an emoji before the skin tone picker appears.",
                          value: $model.settings.emojiToneHoldDelay,
                          in: 120...700, step: 20) { "\(Int($0))ms" }
                Divider()
                SliderRow("Hold steadiness",
                          tooltip: "How much your finger can move during a hold before it registers as a swipe instead.",
                          value: $model.settings.accentMoveCancel,
                          in: 4...30, step: 2) { "\(Int($0))pt" }
            }

            if model.settings.activateWithSlideUp {
                CardSection("Slide up") {
                    SliderRow("Trigger distance",
                              tooltip: "How far up to drag the 123 key to open the panel. Lower triggers more easily, higher prevents accidents.",
                              value: $model.settings.dragUpThreshold,
                              in: 10...50, step: 2) { "\(Int($0))pt" }
                }
            }
        }
        .navigationTitle("Response")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#if DEBUG
#Preview { ResponseView().clinkPreview() }
#endif
