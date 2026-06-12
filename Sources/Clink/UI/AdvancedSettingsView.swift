/**
 Touch and feel tuning screen. Two tabs — Spring, Timing — each with a
 preset chip row above the raw sliders in a `TunedSection` disclosure group.
 

 Module: app-ui · Target: Clink
 Learn: docs/09-app-ui.md
 */
import SwiftUI
import iUXiOS

/// Low-level keyboard tuning: spring physics and timing.
/// App-level management (backup/restore + reset) lives under Setup now — this
/// screen is purely the dials that change how the keyboard feels to touch.
struct AdvancedSettingsView: View {
    private enum Tab { case spring, timing }

    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedTab: Tab = .spring
    @State private var previewDark: Bool = false

    private var themeAccent: Color {
        model.settings.resolvedTheme(dark: colorScheme == .dark).accent.color
    }

    var body: some View {
        @Bindable var model = model
        PinnedPreviewLayout(settings: model.settings,
                            previewColorScheme: model.settings.matchSystemAppearance
                                ? (previewDark ? .dark : .light)
                                : nil) {
            Picker("", selection: $selectedTab) {
                Text("Spring").tag(Tab.spring)
                Text("Timing").tag(Tab.timing)
            }
            .pickerStyle(.segmented)
            .padding(.bottom, 4)

            switch selectedTab {
            case .spring:
                springTab(model: model)
            case .timing:
                timingTab(model: model)
            }
        }
        .navigationTitle("Touch & Feel")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if model.settings.matchSystemAppearance {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { previewDark.toggle() } label: {
                        Image(systemName: previewDark ? "moon.fill" : "sun.max")
                    }
                }
            }
        }
        .tint(themeAccent)
        .onAppear { previewDark = colorScheme == .dark }
    }

    // MARK: - Tabs

    @ViewBuilder
    private func springTab(model: AppModel) -> some View {
        @Bindable var model = model
        TunedSection(title: "Animation", presets: TuningPresets.animation) {
            fineTuneHeader("Key press")
            SliderRow("Bloom", value: $model.settings.keyBloomScale,
                      in: 1.0...1.4, step: 0.02) {
                $0 == 1.0 ? "Off" : "\(Int(($0 * 100).rounded()))%"
            }
            Divider()
            SliderRow("Speed", value: $model.settings.keySpringResponse,
                      in: 0.08...0.6, step: 0.02) {
                String(format: "%.2fs", $0)
            }
            Divider()
            SliderRow("Springiness", value: $model.settings.keySpringDamping,
                      in: 0.3...1.0, step: 0.05) {
                $0 >= 0.99 ? "Firm" : String(format: "%.2f", $0)
            }

            fineTuneHeader("Space bar")
            SliderRow("Speed", value: $model.settings.spaceSpringResponse,
                      in: 0.08...0.6, step: 0.02) {
                String(format: "%.2fs", $0)
            }
            Divider()
            SliderRow("Springiness", value: $model.settings.spaceSpringDamping,
                      in: 0.3...1.0, step: 0.05) {
                $0 >= 0.99 ? "Firm" : String(format: "%.2f", $0)
            }
            Divider()
            SliderRow("Lean", value: $model.settings.spaceLeanMultiplier,
                      in: 0...0.3, step: 0.01) {
                $0 == 0 ? "Off" : String(format: "%.2f×", $0)
            }
            Divider()
            SliderRow("Cursor shrink", value: $model.settings.spaceCursorDragScale,
                      in: 0.7...1.0, step: 0.02) {
                $0 >= 0.99 ? "Off" : "\(Int(($0 * 100).rounded()))%"
            }

            fineTuneHeader("Popup")
            SliderRow("Speed", value: $model.settings.popupSpringResponse,
                      in: 0.08...0.6, step: 0.02) {
                String(format: "%.2fs", $0)
            }
            Divider()
            SliderRow("Springiness", value: $model.settings.popupSpringDamping,
                      in: 0.3...1.0, step: 0.05) {
                $0 >= 0.99 ? "Firm" : String(format: "%.2f", $0)
            }
        }
    }

    @ViewBuilder
    private func timingTab(model: AppModel) -> some View {
        @Bindable var model = model
        TunedSection(title: "Backspace & linger", presets: TuningPresets.timing) {
            fineTuneHeader("Key press")
            SliderRow("Press linger", value: $model.settings.keyPressLinger,
                      in: 0...0.4, step: 0.02) {
                $0 < 0.005 ? "Off" : "\(Int(($0 * 1000).rounded()))ms"
            }

            fineTuneHeader("Backspace repeat")
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

    /// A small group heading used inside a "Fine-tune" disclosure to separate the
    /// raw sliders into their original sub-groups.
    @ViewBuilder
    private func fineTuneHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 14)
            .padding(.bottom, 2)
    }
}
