/**
 Smart-text settings screen: autocorrect, suggestions, capitalization, and auto-punctuation.
 

 Module: app-ui · Target: Clink
 Learn: docs/04-prediction.md
 */
import SwiftUI
import iUXiOS

/// Smart-text settings — everything about what the keyboard *does* with the
/// characters you type: predictions, corrections, and the little automatic
/// niceties. Pulled out of "Layout & Keys" into its own screen so autocorrect
/// and friends live somewhere a user would actually look for them.
struct TypingView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        PinnedPreviewLayout(settings: model.settings) {
                CardSection("Suggestions") {
                    ToggleRow("Suggestion bar",
                              subtitle: "Offline autocomplete above the keys.",
                              isOn: $model.settings.suggestionsEnabled)
                    Divider()
                    ToggleRow("Auto-correction",
                              subtitle: "Fix the word when you type a space or punctuation.",
                              isOn: $model.settings.autocorrectEnabled)
                }

}
        .navigationTitle("Typing")
        .navigationBarTitleDisplayMode(.inline)
    }
}
