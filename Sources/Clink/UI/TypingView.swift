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

                CardSection("Text") {
                    ToggleRow("Auto-capitalize",
                              subtitle: "Capitalize the first letter of a sentence.",
                              isOn: $model.settings.autoCapitalize)
                    Divider()
                    ToggleRow("Auto punctuation",
                              subtitle: "Add apostrophes to contractions like “dont” → “don’t”.",
                              isOn: $model.settings.autoPunctuationEnabled)
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

                CardSection("Clipboard") {
                    ToggleRow("Clipboard history",
                              subtitle: "Save recently copied text for quick re-paste. Adds a clipboard icon to the left of the suggestions bar.",
                              isOn: $model.settings.clipboardEnabled)
                    if model.settings.clipboardEnabled && !model.hasFullAccess {
                        Divider()
                        NavigationLink { EnableFlowView() } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "lock.shield").font(.title3).foregroundStyle(.tint)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Full Access required").font(.subheadline.weight(.semibold))
                                    Text("Clipboard history needs Full Access to read what you've copied.")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            }
                            .padding(14)
                            .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
        }
        .navigationTitle("Typing")
        .navigationBarTitleDisplayMode(.inline)
    }
}
