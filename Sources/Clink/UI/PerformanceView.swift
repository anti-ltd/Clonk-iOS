/**
 Performance settings — suggestion compute budget and typing responsiveness.
 The main lever is the suggestion debounce delay: how long after each keystroke
 the keyboard waits before running UITextChecker. A longer wait collapses more
 keystrokes into a single compute (saves CPU/battery); a shorter wait keeps the
 bar snappier at the cost of more frequent checker invocations.
 */
import SwiftUI
import iUXiOS

/// Controls the keyboard extension's computational budget. Surfaces the
/// suggestion-engine debounce delay — the primary knob for balancing bar
/// responsiveness against CPU and battery usage during fast typing.
struct PerformanceView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        PinnedPreviewLayout(settings: model.settings,
                            previewColorScheme: nil) {
            CardSection("Presets") {
                PresetChips(presets: TuningPresets.performance)
                    .padding(.vertical, UX.rowVPadding)
            }

            CardSection("Suggestions") {
                Text("How long after each keystroke before the suggestion engine runs. A longer delay collapses more keystrokes into one compute — fewer UITextChecker calls, less CPU load, better battery life during fast bursts. A shorter delay keeps the suggestion bar snappier.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, UX.rowVPadding)
                Divider()
                SliderRow("Compute delay",
                          value: $model.settings.suggestionDebounceDelay,
                          in: 20...300, step: 10) { "\(Int($0))ms" }
            }
        }
        .navigationTitle("Performance")
        .navigationBarTitleDisplayMode(.inline)
    }
}
