/**
 Response settings — gesture timing & thresholds. How long a hold takes to fire
 a long-press (accent bar, emoji skin tones) and how far a slide must travel to
 trigger the 123 slide-up. Presets up top, raw sliders below.
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
                Text("How long to hold before a long-press fires, and how much your finger may drift mid-hold before it's read as a swipe instead.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, UX.rowVPadding)
                Divider()
                SliderRow("Accent delay", value: $model.settings.accentHoldDelay,
                          in: 150...900, step: 25) { "\(Int($0))ms" }
                Divider()
                SliderRow("Emoji tone delay", value: $model.settings.emojiToneHoldDelay,
                          in: 120...700, step: 20) { "\(Int($0))ms" }
                Divider()
                SliderRow("Hold steadiness", value: $model.settings.accentMoveCancel,
                          in: 4...30, step: 2) { "\(Int($0))pt" }
            }

            CardSection("Slide up") {
                Text("How far the 123 key must be dragged upward to open the action-panel picker. Only applies when slide-up access is on.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, UX.rowVPadding)
                Divider()
                SliderRow("Trigger distance", value: $model.settings.dragUpThreshold,
                          in: 10...50, step: 2) { "\(Int($0))pt" }
            }
        }
        .navigationTitle("Response")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#if DEBUG
#Preview { ResponseView().clinkPreview() }
#endif
