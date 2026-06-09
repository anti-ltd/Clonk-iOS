/**
 Keys settings — Geometry tab (size & shape) and Backspace tab (repeat timing).
 */
import SwiftUI
import iUXiOS

struct KeysView: View {
    private enum Tab { case geometry, padding, backspace }

    @Environment(AppModel.self) private var model
    @State private var selectedTab: Tab = .geometry

    var body: some View {
        @Bindable var model = model
        PinnedPreviewLayout(settings: model.settings,
                            bottomBar: AnyView(
                                ThemedTabPicker(
                                    options: [("Geometry", Tab.geometry),
                                              ("Padding", Tab.padding),
                                              ("Backspace", Tab.backspace)],
                                    selection: $selectedTab)
                            )) {
            switch selectedTab {
            case .geometry:
                geometryTab(model: model)
            case .padding:
                paddingTab(model: model)
            case .backspace:
                backspaceTab(model: model)
            }
        }
        .navigationTitle("Keys")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Tabs

    @ViewBuilder
    private func geometryTab(model: AppModel) -> some View {
        @Bindable var model = model
        CardSection("Presets") {
            PresetChips(presets: TuningPresets.size)
                .padding(.vertical, UX.rowVPadding)
        }

        CardSection("Values") {
            SliderRow("Key height",
                      tooltip: "Taller keys are easier to tap accurately. Shorter keys give more screen room.",
                      value: $model.settings.keyHeight,
                      in: 38...58, step: 1) { "\(Int($0))pt" }
            Divider()
            SliderRow("Roundness",
                      tooltip: "Corner radius of each key. 0 is square, higher values make rounder caps.",
                      value: $model.settings.keyCornerRadius,
                      in: 0...22, step: 1) { "\(Int($0))pt" }
            Divider()
            SliderRow("Key width",
                      tooltip: "Width of each letter key within its grid cell. Lower values add more space between keys.",
                      value: $model.settings.keyWidthFraction,
                      in: 0.6...1, step: 0.02) { "\(Int(($0 * 100).rounded()))%" }
            Divider()
            SliderRow("Space bar width",
                      tooltip: "Width of the space bar in key units. Narrower leaves room for keys on either side.",
                      value: $model.settings.spaceWidth,
                      in: 3...7, step: 0.5) { String(format: "%.1f keys", $0) }
            Divider()
            SliderRow("Shift & delete width",
                      tooltip: "Width of the shift and backspace keys relative to a standard letter key.",
                      value: $model.settings.funcKeyWidth,
                      in: 1...2, step: 0.1) { String(format: "%.1f keys", $0) }
            Divider()
            SliderRow("Key spacing",
                      tooltip: "Horizontal gap between adjacent keys in the same row.",
                      value: $model.settings.keySpacing,
                      in: 1...12, step: 1) { "\(Int($0))pt" }
            Divider()
            SliderRow("Row spacing",
                      tooltip: "Vertical gap between rows of keys.",
                      value: $model.settings.rowSpacing,
                      in: 0...16, step: 1) { "\(Int($0))pt" }
        }
    }

    @ViewBuilder
    private func paddingTab(model: AppModel) -> some View {
        @Bindable var model = model
        CardSection("Values") {
            SliderRow("Top padding",
                      tooltip: "Space between the suggestion bar and the top row of keys.",
                      value: $model.settings.keyboardTopPadding,
                      in: 0...48, step: 1) { "\(Int($0))pt" }
            Divider()
            SliderRow("Bottom padding",
                      tooltip: "Lifts the entire keyboard up from the bottom edge of the keyboard extension.",
                      value: $model.settings.keyboardBottomPadding,
                      in: 0...64, step: 1) { "\(Int($0))pt" }
        }
    }

    @ViewBuilder
    private func backspaceTab(model: AppModel) -> some View {
        @Bindable var model = model
        CardSection("Presets") {
            PresetChips(presets: TuningPresets.timing)
                .padding(.vertical, UX.rowVPadding)
        }

        CardSection("Values") {
            SliderRow("Hold delay",
                      tooltip: "How long you must hold backspace before rapid-delete kicks in.",
                      value: $model.settings.repeatHoldDelay,
                      in: 150...800, step: 25) {
                "\(Int($0))ms"
            }
            Divider()
            SliderRow("Start speed",
                      tooltip: "Time between each deletion when rapid-delete starts. Higher is slower.",
                      value: $model.settings.repeatInitialInterval,
                      in: 50...200, step: 10) {
                "\(Int($0))ms"
            }
            Divider()
            SliderRow("Max speed",
                      tooltip: "Fastest deletion rate after the key fully accelerates. Lower is faster.",
                      value: $model.settings.repeatMinInterval,
                      in: 20...80, step: 5) {
                "\(Int($0))ms"
            }
            Divider()
            SliderRow("Acceleration",
                      tooltip: "How quickly repeat accelerates to max speed. Higher gets there faster.",
                      value: $model.settings.repeatAccelStep,
                      in: 1...20, step: 1) {
                "\(Int($0))ms/step"
            }
        }
    }
}

#if DEBUG
#Preview { KeysView().clinkPreview() }
#endif
