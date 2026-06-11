/**
 Suggestions settings — suggestion bar and auto-correction toggles.
 */
import SwiftUI
import iUXiOS

struct SuggestionsView: View {
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
                if model.settings.autocorrectEnabled {
                    Divider()
                    ToggleRow("Revert on delete",
                              subtitle: "Press delete after a correction to restore the word you typed.",
                              isOn: $model.settings.revertAutocorrectOnDelete)
                }
            }
        }
        .navigationTitle("Suggestions")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#if DEBUG
#Preview { SuggestionsView().clinkPreview() }
#endif
