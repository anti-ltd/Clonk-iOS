/**
 Animation tuning screen. Two tabs — Spring, Timing. Spring tab shows three
 cards (Keys, Space bar, Popup); the Popup card is hidden when popups are off.
 */
import SwiftUI
import iUXiOS

struct AnimationView: View {
    private enum Tab { case spring, timing }

    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @Environment(NavBarState.self) private var navBar
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
                                : nil,
                            bottomBar: AnyView(
                                ThemedTabPicker(
                                    options: [("Spring", Tab.spring), ("Timing", Tab.timing)],
                                    selection: $selectedTab)
                            )) {
            switch selectedTab {
            case .spring:
                springTab(model: model)
            case .timing:
                timingTab(model: model)
            }
        }
        .navigationTitle("Animation")
        .navigationBarTitleDisplayMode(.inline)
        .tint(themeAccent)
        .onAppear {
            previewDark = colorScheme == .dark
            if model.settings.matchSystemAppearance {
                navBar.trailingIcon = previewDark ? "moon.fill" : "sun.max"
                navBar.trailingAction = { previewDark.toggle() }
            }
        }
        .onChange(of: previewDark) { _, new in
            if model.settings.matchSystemAppearance {
                navBar.trailingIcon = new ? "moon.fill" : "sun.max"
            }
        }
        .onChange(of: model.settings.matchSystemAppearance) { _, match in
            navBar.trailingIcon = match ? (previewDark ? "moon.fill" : "sun.max") : nil
            navBar.trailingAction = match ? { previewDark.toggle() } : nil
        }
    }

    // MARK: - Tabs

    @ViewBuilder
    private func springTab(model: AppModel) -> some View {
        @Bindable var model = model
        CardSection("Key press") {
            ToggleRow("Liquid key press",
                      subtitle: "Bloom and warp each key when pressed — best on Liquid Glass.",
                      isOn: $model.settings.keyPressWarp)
            Divider()
            ToggleRow("Instant highlight",
                      subtitle: "Drop the press spring — keys snap to their bloom with zero animation, like the stock keyboard. Hides the speed/springiness controls below.",
                      isOn: $model.settings.keyPressInstant)
            .disabled(!model.settings.keyPressWarp)
            .opacity(model.settings.keyPressWarp ? 1 : 0.4)
        }
        CardSection("Keys") {
            PresetChips(presets: TuningPresets.animation)
                .padding(.vertical, UX.rowVPadding)
            Divider()
            SliderRow("Bloom", value: $model.settings.keyBloomScale,
                      in: 1.0...1.4, step: 0.02) {
                $0 == 1.0 ? "Off" : "\(Int(($0 * 100).rounded()))%"
            }
            if !model.settings.keyPressInstant {
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
            }
            Divider()
            SliderRow("Tap flash", value: $model.settings.tapFlashStrength,
                      in: 0...0.7, step: 0.02) {
                $0 < 0.005 ? "Off" : "\(Int(($0 * 100).rounded()))%"
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.settings.keyPressInstant)
        CardSection("Space bar") {
            PresetChips(presets: TuningPresets.spaceBar)
                .padding(.vertical, UX.rowVPadding)
            Divider()
            SliderRow("Bloom", value: $model.settings.spaceBloomScale,
                      in: 1.0...1.2, step: 0.01) {
                $0 <= 1.001 ? "Off" : "\(Int(($0 * 100).rounded()))%"
            }
            Divider()
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
        }
        Group {
            if model.settings.keyPopupEnabled {
                CardSection("Popup") {
                    PresetChips(presets: TuningPresets.popup)
                        .padding(.vertical, UX.rowVPadding)
                    Divider()
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
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.settings.keyPopupEnabled)
    }

    @ViewBuilder
    private func timingTab(model: AppModel) -> some View {
        @Bindable var model = model
        CardSection("Key press") {
            SliderRow("Press linger", value: $model.settings.keyPressLinger,
                      in: 0...0.4, step: 0.02) {
                $0 < 0.005 ? "Off" : "\(Int(($0 * 1000).rounded()))ms"
            }
        }
    }

}

#if DEBUG
#Preview { AnimationView().clinkPreview() }
#endif
