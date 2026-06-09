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
                      tooltip: "How far your finger travels to move the cursor one character. If it jumps too fast, lower this.",
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
            return "Slide on the space bar to move the cursor. Left/right moves by character, up/down by line. Raise the activation time so it only kicks in on a deliberate hold. Lower sensitivity if it still triggers by accident."
        case .trackpad:
            return "Hold the space bar to turn the keyboard into a trackpad. Drag to move the cursor, then lift to return to the keys. Raise the activation time so it only engages on a deliberate hold. Lower sensitivity if it triggers by accident."
        case .combined:
            return "Type normally, then hold the space bar to enter cursor mode. The keys blank out while you drag, and lift returns you to typing."
        }
    }
}

#if DEBUG
#Preview { CursorView().clinkPreview() }
#endif
