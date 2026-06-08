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
            SliderRow("Key height", value: $model.settings.keyHeight,
                      in: 38...58, step: 1) { "\(Int($0))pt" }
            Divider()
            SliderRow("Roundness", value: $model.settings.keyCornerRadius,
                      in: 0...22, step: 1) { "\(Int($0))pt" }
            Divider()
            SliderRow("Key width", value: $model.settings.keyWidthFraction,
                      in: 0.6...1, step: 0.02) { "\(Int(($0 * 100).rounded()))%" }
            Divider()
            SliderRow("Space bar width", value: $model.settings.spaceWidth,
                      in: 3...7, step: 0.5) { String(format: "%.1f keys", $0) }
            Divider()
            SliderRow("Shift & delete width", value: $model.settings.funcKeyWidth,
                      in: 1...2, step: 0.1) { String(format: "%.1f keys", $0) }
            Divider()
            SliderRow("Key spacing", value: $model.settings.keySpacing,
                      in: 1...12, step: 1) { "\(Int($0))pt" }
            Divider()
            SliderRow("Row spacing", value: $model.settings.rowSpacing,
                      in: 0...16, step: 1) { "\(Int($0))pt" }
        }
    }

    @ViewBuilder
    private func paddingTab(model: AppModel) -> some View {
        @Bindable var model = model
        CardSection("Values") {
            Text("Add space around the keyboard — not between keys. Top padding sits between the suggestion bar and the keys (handy with a background image); bottom padding lifts the whole keyboard up from the bottom edge.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, UX.rowVPadding)
            Divider()
            SliderRow("Top padding", value: $model.settings.keyboardTopPadding,
                      in: 0...48, step: 1) { "\(Int($0))pt" }
            Divider()
            SliderRow("Bottom padding", value: $model.settings.keyboardBottomPadding,
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
            Text("How long to hold the key before rapid-delete begins, and how fast it accelerates.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, UX.rowVPadding)
            Divider()
            SliderRow("Hold delay", value: $model.settings.repeatHoldDelay,
                      in: 150...800, step: 25) {
                "\(Int($0))ms"
            }
            Divider()
            SliderRow("Start speed", value: $model.settings.repeatInitialInterval,
                      in: 50...200, step: 10) {
                "\(Int($0))ms"
            }
            Divider()
            SliderRow("Max speed", value: $model.settings.repeatMinInterval,
                      in: 20...80, step: 5) {
                "\(Int($0))ms"
            }
            Divider()
            SliderRow("Acceleration", value: $model.settings.repeatAccelStep,
                      in: 1...20, step: 1) {
                "\(Int($0))ms/step"
            }
        }
    }
}

#if DEBUG
#Preview { KeysView().clinkPreview() }
#endif
