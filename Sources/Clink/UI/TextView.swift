/**
 Text settings — everything about the words the keyboard produces, under one page
 with three tabs:

   • Suggestions — the suggestion bar, auto-correction, and the custom dictionary.
   • Automation  — auto-capitalize, smart punctuation, symbol-page returns.
   • Adaptation  — opt-in on-device learning and the learned-word list.

 Merges the former Suggestions, Automation, and Adaptation pages to cut Home cards
 and sidebar rows. `$model.settings` bindings persist via `AppModel.settings`
 `didSet`; custom + learned words live in `UserAdaptation` (App Group file).


 Module: app-ui · Target: Clink
 Learn: docs/04-prediction.md
 */
import SwiftUI
import iUXiOS

/// Suggestions, automation, and adaptation — three tabs sharing one pinned preview.
struct TextView: View {
    private enum Tab { case suggestions, automation, adaptation }

    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedTab: Tab = .suggestions

    private var themeAccent: Color {
        model.settings.resolvedTheme(dark: colorScheme == .dark).accent.color
    }

    var body: some View {
        @Bindable var model = model
        PinnedPreviewLayout(settings: model.settings,
                            bottomBar: AnyView(
                                ThemedTabPicker(
                                    options: [("Suggestions", Tab.suggestions),
                                              ("Automation", Tab.automation),
                                              ("Adaptation", Tab.adaptation)],
                                    selection: $selectedTab)
                            )) {
            switch selectedTab {
            case .suggestions: SuggestionsControls()
            case .automation:  AutomationControls()
            case .adaptation:  AdaptationControls()
            }
        }
        .tint(themeAccent)
        .navigationTitle("Text")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Suggestions

/// Suggestion bar + auto-correction settings, then the custom dictionary inline.
struct SuggestionsControls: View {
    @Environment(AppModel.self) private var model
    @Environment(\.cardCornerRadius) private var cardCornerRadius
    @State private var newWord = ""
    @State private var customWords: [String] = []
    @State private var openRow: Int? = nil
    @FocusState private var fieldFocused: Bool

    var body: some View {
        @Bindable var model = model
        Group {
        CardSection("Suggestions") {
            ToggleRow("Suggestion bar",
                      subtitle: "Offline autocomplete above the keys.",
                      isOn: $model.settings.suggestionsEnabled)
            Divider()
            SliderRow("Top padding",
                      tooltip: "Extra space above the suggestion bar.",
                      value: $model.settings.suggestionTopPadding,
                      in: 0...20, step: 1) {
                $0 == 0 ? "None" : "\(Int($0)) pt"
            }
            .gated(model.settings.suggestionsEnabled,
                   reason: "Turn on the Suggestion bar to adjust this.")
            Divider()
            ToggleRow("Auto-correction",
                      subtitle: "Fix the word when you type a space or punctuation.",
                      isOn: $model.settings.autocorrectEnabled)
            Divider()
            ToggleRow("Revert on delete",
                      subtitle: "Press delete after a correction to restore the word you typed.",
                      isOn: $model.settings.revertAutocorrectOnDelete)
            .gated(model.settings.autocorrectEnabled,
                   reason: "Turn on Auto-correction to use this.")
        }

        CardSection("Add word") {
            HStack(spacing: 8) {
                TextField("New word", text: $newWord)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($fieldFocused)
                    .submitLabel(.done)
                    .onSubmit(addWord)
                Button(action: addWord) {
                    Image(systemName: "plus.circle.fill").font(.title3)
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
                           cardBackground: { swipeRowBackground(cardCornerRadius) }) {
                            HStack {
                                Text(word).font(.subheadline).foregroundStyle(.primary)
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
        .onAppear { customWords = UserAdaptation().customWords() }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "character.book.closed")
                .font(.system(size: 36)).foregroundStyle(.secondary)
            Text("No custom words").font(.subheadline.weight(.medium))
            Text("Add names, slang, or jargon the keyboard keeps fighting.")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var canAdd: Bool {
        !newWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // Edits go through a *fresh* `UserAdaptation`, never `.shared`: the keyboard
    // extension writes the store from another process, so `.shared` is an
    // app-launch snapshot that would clobber words learned since.
    private func addWord() {
        let store = UserAdaptation()
        guard store.addCustomWord(newWord) else { return }
        newWord = ""
        customWords = store.customWords()
    }

    private func remove(_ word: String) {
        let store = UserAdaptation()
        store.removeCustomWord(word)
        customWords = store.customWords()
    }
}

// MARK: - Automation

/// Auto-capitalize, smart punctuation, and symbol-page return behaviour.
struct AutomationControls: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        CardSection("Text") {
            ToggleRow("Auto-capitalize",
                      subtitle: "Capitalize the first letter of a sentence.",
                      isOn: $model.settings.autoCapitalize)
            Divider()
            ToggleRow("Auto punctuation",
                      subtitle: "Add apostrophes to contractions like \u{201C}dont\u{201D} → \u{201C}don\u{2019}t\u{201D}.",
                      isOn: $model.settings.autoPunctuationEnabled)
            Divider()
            ToggleRow("Revert auto-correct on delete",
                      subtitle: "Press delete after a correction to restore the word you typed.",
                      isOn: $model.settings.revertAutocorrectOnDelete)
            .gated(model.settings.autocorrectEnabled,
                   reason: "Turn on Auto-correction (Suggestions) to use this.")
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
}

// MARK: - Adaptation

/// On-device learning toggle and the learned-word list (history shown disabled
/// until learning is on).
struct AdaptationControls: View {
    @Environment(AppModel.self) private var model
    @Environment(\.cardCornerRadius) private var cardCornerRadius
    @State private var learnedWords: [String] = []
    @State private var justCleared = false
    @State private var openRow: Int? = nil

    private var learnedCount: Int { learnedWords.count }

    var body: some View {
        @Bindable var model = model
        Group {
        CardSection("Learning") {
            ToggleRow("Learn from your typing",
                      subtitle: "Remember words you use often, favour the ones you pick from the bar, and stop re-applying corrections you reject.",
                      isOn: $model.settings.learningEnabled)
        }

        GatedCard("History", enabled: model.settings.learningEnabled,
                  reason: "Turn on learning to manage learned words.") {
            HStack {
                Text(countLabel).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.vertical, UX.rowVPadding)
            Divider()
            Button(role: .destructive) {
                UserAdaptation().clear()
                learnedWords = []
                justCleared = true
            } label: {
                HStack {
                    Text(justCleared ? "Learned words cleared" : "Clear learned words")
                        .foregroundStyle(justCleared || learnedCount == 0
                                         ? AnyShapeStyle(.secondary)
                                         : AnyShapeStyle(Color.red))
                    Spacer()
                }
                .contentShape(Rectangle())
                .padding(.vertical, UX.rowVPadding)
            }
            .buttonStyle(.plain)
            .disabled(justCleared || learnedCount == 0)
        }

        if model.settings.learningEnabled, !learnedWords.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Learned words")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                VStack(spacing: 8) {
                    ForEach(Array(learnedWords.enumerated()), id: \.element) { index, word in
                        SwipeRow(id: index, cornerRadius: cardCornerRadius, actions: [
                            SwipeAction(icon: "trash.fill", label: "Forget",
                                        tint: .red) { forget(word) },
                        ], openID: $openRow,
                           cardBackground: { swipeRowBackground(cardCornerRadius) }) {
                            HStack {
                                Text(word).font(.subheadline).foregroundStyle(.primary)
                                Spacer()
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                        }
                    }
                }
            }
        }

        Text("Learning happens entirely on this device. Nothing you type is uploaded, and clearing wipes the learned words immediately.")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 4)
        }
        .onAppear {
            learnedWords = UserAdaptation().organicLearnedWords()
            if learnedCount > 0 { justCleared = false }
        }
    }

    private func forget(_ word: String) {
        UserAdaptation().forgetLearnedWord(word)
        learnedWords.removeAll { $0 == word }
    }

    private var countLabel: String {
        switch learnedCount {
        case 0:  "No words learned yet"
        case 1:  "1 word learned"
        default: "\(learnedCount) words learned"
        }
    }
}

// MARK: - Shared

/// The standard inset background for a swipeable list row (custom + learned words).
@ViewBuilder
private func swipeRowBackground(_ corner: CGFloat) -> some View {
    RoundedRectangle(cornerRadius: corner, style: .continuous)
        .fill(Color(.secondarySystemGroupedBackground))
        .overlay(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
}

#if DEBUG
#Preview { TextView().clinkPreview() }
#endif
