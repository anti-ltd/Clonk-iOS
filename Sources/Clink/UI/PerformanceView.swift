/**
 Performance settings — two tabs: Responsiveness (snappiness preset + backspace
 repeat) and Suggestions (compute budget).
 */
import SwiftUI
import iUXiOS

struct PerformanceView: View {
    private enum Tab { case responsiveness, suggestions }

    @Environment(AppModel.self) private var model
    @State private var selectedTab: Tab = .responsiveness

    var body: some View {
        @Bindable var model = model
        PinnedPreviewLayout(settings: model.settings,
                            previewColorScheme: nil,
                            bottomBar: AnyView(
                                ThemedTabPicker(
                                    options: [("Responsiveness", Tab.responsiveness),
                                              ("Suggestions", Tab.suggestions)],
                                    selection: $selectedTab)
                            )) {
            switch selectedTab {
            case .responsiveness:
                responsivenessTab(model: model)
            case .suggestions:
                suggestionsTab(model: model)
            }
        }
        .navigationTitle("Performance")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Tabs

    @ViewBuilder
    private func responsivenessTab(model: AppModel) -> some View {
        @Bindable var model = model
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

    @ViewBuilder
    private func suggestionsTab(model: AppModel) -> some View {
        @Bindable var model = model
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
    }
}

#if DEBUG
#Preview { PerformanceView().clinkPreview() }
#endif
