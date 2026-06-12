/**
 Suggestions settings — suggestion bar and auto-correction toggles.
 

 Module: app-ui · Target: Clink
 Learn: docs/04-prediction.md
 */
import SwiftUI
import iUXiOS

/// Suggestion bar, autocorrect, and revert-on-delete toggles.
/// `$model.settings` bindings persist via `AppModel.settings` `didSet`.
struct SuggestionsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        PinnedPreviewLayout(settings: model.settings) {
            CardSection("Suggestions") {
                ToggleRow("Suggestion bar",
                          subtitle: "Offline autocomplete above the keys.",
                          isOn: $model.settings.suggestionsEnabled)
                if model.settings.suggestionsEnabled {
                    Divider()
                    SliderRow("Top padding",
                              tooltip: "Extra space above the suggestion bar.",
                              value: $model.settings.suggestionTopPadding,
                              in: 0...20, step: 1) {
                        $0 == 0 ? "None" : "\(Int($0)) pt"
                    }
                }
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
            // Learning (remembering words, suppressing rejected corrections) now
            // lives on its own Adaptation page under Customization.
        }
        .navigationTitle("Suggestions")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#if DEBUG
#Preview { SuggestionsView().clinkPreview() }
#endif
