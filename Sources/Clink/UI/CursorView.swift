/**
 Cursor settings screen — Style tab (movement type) and Feel tab (presets + sliders).
 */
import SwiftUI
import iUXiOS

struct CursorView: View {
    private enum Tab { case style, feel }

    @Environment(AppModel.self) private var model
    @State private var selectedTab: Tab = .style

    var body: some View {
        @Bindable var model = model
        PinnedPreviewLayout(settings: model.settings,
                            bottomBar: AnyView(
                                ThemedTabPicker(
                                    options: [("Style", Tab.style), ("Feel", Tab.feel)],
                                    selection: $selectedTab)
                            )) {
            switch selectedTab {
            case .style:
                styleTab(model: model)
            case .feel:
                feelTab(model: model)
            }
        }
        .navigationTitle("Cursor")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Tabs

    @ViewBuilder
    private func styleTab(model: AppModel) -> some View {
        @Bindable var model = model
        CardSection("Cursor") {
            PresetChips(presets: TuningPresets.cursorMovementType)
                .padding(.vertical, UX.rowVPadding)
            Divider()
            Text(cursorHelpText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, UX.rowVPadding)
        }
    }

    @ViewBuilder
    private func feelTab(model: AppModel) -> some View {
        @Bindable var model = model
        CardSection("Presets") {
            PresetChips(presets: TuningPresets.cursor)
                .padding(.vertical, UX.rowVPadding)
        }

        CardSection("Values") {
            SliderRow("Activation time",
                      tooltip: "How long you must hold the space bar before cursor mode engages. Raise it if the cursor triggers accidentally while typing.",
                      value: $model.settings.spaceCursorActivationDelay,
                      in: 0...500, step: 25) {
                $0 < 5 ? "Instant" : "\(Int($0))ms"
            }
            Divider()
            SliderRow("Scroll sensitivity",
                      tooltip: "How far your finger needs to travel to move the cursor one character. Higher is more sensitive — lower it if the cursor jumps too fast.",
                      value: Binding(
                        get: { 30 - model.settings.spaceCursorStride },
                        set: { model.settings.spaceCursorStride = 30 - $0 }),
                      in: 8...24, step: 2) {
                $0 == 20 ? "Default" : "\(Int(($0 / 20 * 100).rounded()))%"
            }
            Divider()
            SliderRow("Line length",
                      tooltip: "Characters per line used to calculate vertical cursor jumps when you drag up or down.",
                      value: $model.settings.cursorLineStride,
                      in: 5...80, step: 5) {
                "\(Int($0)) chars"
            }
        }
    }

    private var cursorHelpText: String {
        switch model.settings.cursorMovementType {
        case .spacebar:
            return "Slide on the space bar to move the cursor — left/right by characters, up/down by lines. Raise the activation time so the cursor only engages when you hold deliberately; lower the sensitivity if it still triggers by accident."
        case .trackpad:
            return "Hold the space bar to turn the keyboard into a trackpad — drag to move the cursor (left/right by characters, up/down by lines), then lift to return to the keys. Raise the activation time so it only engages on a deliberate hold; lower the sensitivity if it triggers by accident."
        case .combined:
            return "Type as normal — but hold the space bar and the keys blank out and stop responding while you drag the cursor (left/right by characters, up/down by lines), with the space bar morphing. Lift to return to the keys."
        }
    }
}

#if DEBUG
#Preview { CursorView().clinkPreview() }
#endif
