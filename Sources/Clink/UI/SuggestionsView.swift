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
            }
        }
        .navigationTitle("Suggestions")
        .navigationBarTitleDisplayMode(.inline)
    }
}
