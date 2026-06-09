/**
 Cursor settings screen — Style tab (movement type) and Feel tab (presets + sliders).
 */
import SwiftUI
import iUXiOS

struct CursorView: View {
    private enum Tab { case style, feel }

    @Environment(AppModel.self) private var model
    @Environment(\.cardCornerRadius) private var cardCornerRadius
    @State private var selectedTab: Tab = .style

    var body: some View {
        @Bindable var model = model
        PinnedPreviewLayout(settings: model.settings,
                            previewCursorActive: model.settings.cursorMovementType != .spacebar,
                            lockedPreviewText: "The quick brown fox jumps over the lazy dog",
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
            CursorModePreview(mode: model.settings.cursorMovementType,
                              cornerRadius: cardCornerRadius)
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

// MARK: - CursorModePreview

/// Animated diagram illustrating how each cursor movement type works.
/// Placed between the preset chips and the help text in the Style tab.
private struct CursorModePreview: View {
    let mode: CursorMovementType
    let cornerRadius: CGFloat

    @State private var phase: CGFloat = 0

    var body: some View {
        ZStack {
            switch mode {
            case .spacebar: spacebarDiagram
            case .trackpad: trackpadDiagram
            case .combined: combinedDiagram
            }
        }
        .frame(height: 90)
        // Remount the view (restarting the animation) when mode changes.
        .id(mode)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                phase = 1
            }
        }
    }

    // MARK: Spacebar — cursor beam slides left ↔ right inside the space bar

    private var spacebarDiagram: some View {
        VStack(spacing: 10) {
            Text("Slide left or right")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                keyBox(width: 38, height: 32)   // modifier key
                ZStack {
                    // Space bar body
                    RoundedRectangle(cornerRadius: min(cornerRadius, 8), style: .continuous)
                        .fill(.tint.opacity(0.15))
                    RoundedRectangle(cornerRadius: min(cornerRadius, 8), style: .continuous)
                        .strokeBorder(.tint.opacity(0.25), lineWidth: 1)
                    // Direction arrows
                    HStack {
                        Image(systemName: "arrow.left")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tint.opacity(0.55))
                        Spacer()
                        Image(systemName: "arrow.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tint.opacity(0.55))
                    }
                    .padding(.horizontal, 12)
                    // Animated cursor beam
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(.tint)
                        .frame(width: 2.5, height: 20)
                        .offset(x: (phase - 0.5) * 80)
                }
                .frame(height: 32)
                keyBox(width: 38, height: 32)   // return key
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: Trackpad — keyboard fades; cursor dot roams the full area

    private var trackpadDiagram: some View {
        ZStack {
            // Faded letter rows (hint that the keyboard is still there but blurred out)
            VStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { row in
                    HStack(spacing: 3) {
                        ForEach(0..<(10 - row), id: \.self) { _ in
                            RoundedRectangle(cornerRadius: min(cornerRadius, 4), style: .continuous)
                                .fill(Color.primary.opacity(0.08))
                                .frame(height: 15)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)

            // Cursor dot moving along a diagonal path
            Circle()
                .fill(.tint)
                .frame(width: 10, height: 10)
                .blur(radius: 1)
                .offset(x: (phase - 0.5) * 70, y: (phase - 0.5) * 22)
        }
    }

    // MARK: Combined — key rows stay visible; cursor slides along space bar

    private var combinedDiagram: some View {
        VStack(spacing: 6) {
            // Keys remain visible
            VStack(spacing: 3) {
                HStack(spacing: 3) {
                    ForEach(0..<10, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: min(cornerRadius, 4), style: .continuous)
                            .fill(Color.primary.opacity(0.15))
                            .frame(height: 14)
                    }
                }
                HStack(spacing: 3) {
                    ForEach(0..<9, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: min(cornerRadius, 4), style: .continuous)
                            .fill(Color.primary.opacity(0.15))
                            .frame(height: 14)
                    }
                }
            }
            .padding(.horizontal, 20)

            // Bottom row — space bar highlighted + cursor
            HStack(spacing: 6) {
                keyBox(width: 30, height: 24)
                ZStack {
                    RoundedRectangle(cornerRadius: min(cornerRadius, 7), style: .continuous)
                        .fill(.tint.opacity(0.18))
                    RoundedRectangle(cornerRadius: min(cornerRadius, 7), style: .continuous)
                        .strokeBorder(.tint.opacity(0.25), lineWidth: 1)
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(.tint)
                        .frame(width: 2.5, height: 15)
                        .offset(x: (phase - 0.5) * 64)
                }
                .frame(height: 24)
                keyBox(width: 30, height: 24)
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: Helpers

    private func keyBox(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: min(cornerRadius, 6), style: .continuous)
            .fill(Color.primary.opacity(0.12))
            .frame(width: width, height: height)
    }
}

#if DEBUG
#Preview { CursorView().clinkPreview() }
#endif
