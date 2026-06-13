/**
 Suggestions settings — General tab (suggestion bar and auto-correction
 toggles) and Custom tab (the user's own dictionary words).


 Module: app-ui · Target: Clink
 Learn: docs/04-prediction.md
 */
import SwiftUI
import iUXiOS

/// Suggestion bar, autocorrect, and a hand-curated custom dictionary.
/// `$model.settings` bindings persist via `AppModel.settings` `didSet`.
/// Custom words live in `UserAdaptation` (App Group file) as pinned entries.
struct SuggestionsView: View {
    private enum Tab { case general, custom }

    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.cardCornerRadius) private var cardCornerRadius

    private var themeAccent: Color {
        model.settings.resolvedTheme(dark: colorScheme == .dark).accent.color
    }

    @State private var selectedTab: Tab = .general
    @State private var newWord = ""
    @State private var customWords: [String] = []
    @State private var openRow: Int? = nil
    @FocusState private var fieldFocused: Bool

    var body: some View {
        @Bindable var model = model
        PinnedPreviewLayout(settings: model.settings,
                            bottomBar: AnyView(
                                ThemedTabPicker(
                                    options: [("General", Tab.general),
                                              ("Custom", Tab.custom)],
                                    selection: $selectedTab)
                            )) {
            switch selectedTab {
            case .general: generalTab(model: model)
            case .custom:  customTab
            }
        }
        .tint(themeAccent)
        .navigationTitle("Suggestions")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { customWords = UserAdaptation.shared.customWords() }
    }

    // MARK: - General

    @ViewBuilder
    private func generalTab(model: AppModel) -> some View {
        @Bindable var model = model
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

    // MARK: - Custom dictionary

    @ViewBuilder
    private var customTab: some View {
        CardSection("Add word") {
            HStack(spacing: 8) {
                TextField("New word", text: $newWord)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($fieldFocused)
                    .submitLabel(.done)
                    .onSubmit(addWord)
                Button(action: addWord) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .foregroundStyle(canAdd ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                .disabled(!canAdd)
            }
            .padding(.vertical, UX.rowVPadding)
        }

        if customWords.isEmpty {
            emptyState
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("Your words")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                VStack(spacing: 8) {
                    ForEach(Array(customWords.enumerated()), id: \.element) { index, word in
                        SwipeRow(id: index, cornerRadius: cardCornerRadius, actions: [
                            SwipeAction(icon: "trash.fill", label: "Delete",
                                        tint: .red) { remove(word) },
                        ], openID: $openRow,
                           cardBackground: {
                            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                                .fill(Color(.secondarySystemGroupedBackground))
                                .overlay(
                                    RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                                )
                        }) {
                            HStack {
                                Text(word)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                Spacer()
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                        }
                    }
                }
            }
        }

        Text("Custom words are treated as correctly spelled, ranked in the bar, and swipeable. They stay on this device and aren't cleared with learned words.")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "character.book.closed")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("No custom words")
                .font(.subheadline.weight(.medium))
            Text("Add names, slang, or jargon the keyboard keeps fighting.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Actions

    private var canAdd: Bool {
        !newWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func addWord() {
        guard UserAdaptation.shared.addCustomWord(newWord) else { return }
        newWord = ""
        customWords = UserAdaptation.shared.customWords()
    }

    private func remove(_ word: String) {
        UserAdaptation.shared.removeCustomWord(word)
        customWords = UserAdaptation.shared.customWords()
    }
}

#if DEBUG
#Preview { SuggestionsView().clinkPreview() }
#endif
