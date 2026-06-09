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
            PresetChips(presets: TuningPresets.responsiveness)
                .padding(.vertical, UX.rowVPadding)
        }

        CardSection("Backspace repeat") {
            SliderRow("Hold delay",
                      tooltip: "How long you must hold backspace before rapid-delete kicks in.",
                      value: $model.settings.repeatHoldDelay,
                      in: 150...800, step: 25) { "\(Int($0))ms" }
            Divider()
            SliderRow("Start speed",
                      tooltip: "Time between each deletion when rapid-delete starts. Higher is slower.",
                      value: $model.settings.repeatInitialInterval,
                      in: 40...250, step: 10) { "\(Int($0))ms" }
            Divider()
            SliderRow("Fastest speed",
                      tooltip: "Fastest deletion rate after the key fully accelerates. Lower is faster.",
                      value: $model.settings.repeatMinInterval,
                      in: 15...120, step: 5) { "\(Int($0))ms" }
            Divider()
            SliderRow("Acceleration",
                      tooltip: "How quickly repeat accelerates to max speed. Higher gets there faster.",
                      value: $model.settings.repeatAccelStep,
                      in: 0...20, step: 1) {
                $0 < 1 ? "Off" : "\(Int($0))ms/step"
            }
        }
    }

    @ViewBuilder
    private func suggestionsTab(model: AppModel) -> some View {
        @Bindable var model = model
        CardSection("Suggestion compute") {
            PresetChips(presets: TuningPresets.performance)
                .padding(.vertical, UX.rowVPadding)
            Divider()
            SliderRow("Compute delay",
                      tooltip: "Wait time after each keystroke before suggestions update. Longer saves CPU during fast typing, shorter keeps the bar snappier.",
                      value: $model.settings.suggestionDebounceDelay,
                      in: 20...300, step: 10) { "\(Int($0))ms" }
        }
    }
}

#if DEBUG
#Preview { PerformanceView().clinkPreview() }
#endif
