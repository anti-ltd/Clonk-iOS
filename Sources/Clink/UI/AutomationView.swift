/**
 Automation settings — auto-behaviors that fire without explicit input:
 capitalization, punctuation, and symbol-page returns.
 

 Module: app-ui · Target: Clink
 Learn: docs/04-prediction.md
 */
import SwiftUI
import iUXiOS

struct AutomationView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        PinnedPreviewLayout(settings: model.settings) {
            CardSection("Text") {
                ToggleRow("Auto-capitalize",
                          subtitle: "Capitalize the first letter of a sentence.",
                          isOn: $model.settings.autoCapitalize)
                Divider()
                ToggleRow("Auto punctuation",
                          subtitle: "Add apostrophes to contractions like \u{201C}dont\u{201D} → \u{201C}don\u{2019}t\u{201D}.",
                          isOn: $model.settings.autoPunctuationEnabled)
                if model.settings.autocorrectEnabled {
                    Divider()
                    ToggleRow("Revert auto-correct on delete",
                              subtitle: "Press delete after a correction to restore the word you typed.",
                              isOn: $model.settings.revertAutocorrectOnDelete)
                }
            }

            CardSection("Symbols") {
                ToggleRow("Return to letters",
                          subtitle: "After typing punctuation on the symbols page, flip back to letters.",
                          isOn: $model.settings.autoReturnToLetters)
                if model.settings.autoReturnToLetters {
                    Divider()
                    ToggleRow("Add a space",
                              subtitle: "After flipping back, insert a space so you can keep typing.",
                              isOn: $model.settings.autoSpaceAfterReturn)
                }
            }
        }
        .navigationTitle("Automation")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#if DEBUG
#Preview { AutomationView().clinkPreview() }
#endif
