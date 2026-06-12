/**
 Popups settings — key popup toggle, style, and Liquid Glass option.
 

 Module: app-ui · Target: Clink
 Learn: docs/09-app-ui.md
 */
import SwiftUI
import iUXiOS

struct PopupsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        PinnedPreviewLayout(settings: model.settings) {
            CardSection("Key popups") {
                ToggleRow("Key popups",
                          subtitle: "Show an enlarged bubble when a key is pressed.",
                          isOn: $model.settings.keyPopupEnabled)
                if model.settings.keyPopupEnabled {
                    Divider()
                    HStack {
                        Text("Popup style")
                        Spacer()
                        Picker("Popup style", selection: $model.settings.keyPopupStyle) {
                            ForEach(KeyPopupStyle.allCases) { style in
                                Text(style.label).tag(style)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                    .padding(.vertical, UX.rowVPadding)
                    Divider()
                    ToggleRow("Liquid Glass popups",
                              subtitle: "Render key popups as glass on Liquid Glass themes.",
                              isOn: $model.settings.liquidGlassPopup)
                }
            }
            if model.settings.keyPopupEnabled {
                CardSection("Animation") {
                    PresetChips(presets: TuningPresets.popup)
                        .padding(.vertical, UX.rowVPadding)
                    Divider()
                    SliderRow("Speed",
                              tooltip: "Spring response time for the popup appearing and disappearing.",
                              value: $model.settings.popupSpringResponse,
                              in: 0.08...0.6, step: 0.02) {
                        String(format: "%.2fs", $0)
                    }
                    Divider()
                    SliderRow("Springiness",
                              tooltip: "How much the popup bounces on entry. Lower values add more spring.",
                              value: $model.settings.popupSpringDamping,
                              in: 0.3...1.0, step: 0.05) {
                        $0 >= 0.99 ? "Firm" : String(format: "%.2f", $0)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(Motion.settingsReveal.animation, value: model.settings.keyPopupEnabled)
        .navigationTitle("Popups")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#if DEBUG
#Preview { PopupsView().clinkPreview() }
#endif
