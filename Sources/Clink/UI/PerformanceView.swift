/**
 Performance settings — typing responsiveness knobs that have no dedicated page,
 plus a cross-cutting "Responsiveness" preset that sets the whole snappiness
 cluster (key/space springs, bloom, linger, compute budget) in one tap. The raw
 spring/bloom sliders themselves live on Animation, hitboxes on Hitboxes, gesture
 delays on Response/Cursor — this page deliberately does not duplicate those.
 What it uniquely owns: the suggestion compute budget and backspace auto-repeat.
 Every value writes straight to `model.settings`, read live by the keyboard
 extension across the App Group — tunable on-device against the preview above.
 */
import SwiftUI
import iUXiOS

/// The responsiveness tuning hub. Surfaces the one-tap snappiness preset and the
/// two knob groups with no home elsewhere — suggestion compute budget and
/// backspace auto-repeat — without re-listing the spring/hitbox/gesture sliders
/// that already own dedicated pages.
struct PerformanceView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        PinnedPreviewLayout(settings: model.settings,
                            previewColorScheme: nil) {
            CardSection("Responsiveness") {
                Text("The overall snappiness of typing, in one tap. Native mimics the stock keyboard — fast, firm springs, minimal animation, tight compute. Default is Clink's softer liquid feel; Bouncy leans into the deformation. Fine-tune the individual springs under Animation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, UX.rowVPadding)
                Divider()
                PresetChips(presets: TuningPresets.responsiveness)
                    .padding(.vertical, UX.rowVPadding)
            }

            CardSection("Suggestion compute") {
                Text("How long after each keystroke before the suggestion engine runs. A longer delay collapses more keystrokes into one compute — fewer UITextChecker calls, less CPU, better battery in fast bursts. Shorter keeps the bar snappier.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, UX.rowVPadding)
                Divider()
                PresetChips(presets: TuningPresets.performance)
                    .padding(.vertical, UX.rowVPadding)
                Divider()
                SliderRow("Compute delay",
                          value: $model.settings.suggestionDebounceDelay,
                          in: 20...300, step: 10) { "\(Int($0))ms" }
            }

            CardSection("Backspace repeat") {
                Text("Hold backspace to delete repeatedly. The hold delay is the pause before it starts; the speed accelerates from the start interval toward the fastest interval the longer you hold.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, UX.rowVPadding)
                Divider()
                SliderRow("Hold delay", value: $model.settings.repeatHoldDelay,
                          in: 150...800, step: 25) { "\(Int($0))ms" }
                Divider()
                SliderRow("Start speed", value: $model.settings.repeatInitialInterval,
                          in: 40...250, step: 10) { "\(Int($0))ms" }
                Divider()
                SliderRow("Fastest speed", value: $model.settings.repeatMinInterval,
                          in: 15...120, step: 5) { "\(Int($0))ms" }
                Divider()
                SliderRow("Acceleration", value: $model.settings.repeatAccelStep,
                          in: 0...20, step: 1) {
                    $0 < 1 ? "Off" : "\(Int($0))ms/step"
                }
            }
        }
        .navigationTitle("Performance")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#if DEBUG
#Preview { PerformanceView().clinkPreview() }
#endif
