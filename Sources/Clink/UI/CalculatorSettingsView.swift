/**
 Calculator settings — on/off toggle for the calculator action panel,
 with a live pinned preview matching the emoji and layout pages.
 

 Module: app-ui · Target: Clink
 Learn: docs/09-app-ui.md
 */
import SwiftUI
import iUXiOS

/// Settings screen for the calculator panel.
struct CalculatorSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            if model.settings.calculatorEnabled {
                CalculatorPreview(settings: model.settings)
                    .padding(.horizontal, UX.screenPadding)
                    .padding(.top, UX.screenPadding)
                    .padding(.bottom, UX.cardSpacing)
                    .overlay(alignment: .bottom) { Divider().opacity(0.4) }
            }
            ScrollView {
                VStack(spacing: UX.cardSpacing) {
                    CardSection("Settings") {
                        ToggleRow("Calculator",
                                  subtitle: "Evaluate arithmetic and insert the result wherever you type. Adds a calculator to the panel button.",
                                  isOn: $model.settings.calculatorEnabled)
                    }
                }
                .padding(UX.screenPadding)
            }
        }
        .navigationTitle("Calculator")
        .navigationBarTitleDisplayMode(.inline)
        .themePageBackground()
    }
}

#if DEBUG
#Preview { CalculatorSettingsView().clinkPreview() }
#endif
