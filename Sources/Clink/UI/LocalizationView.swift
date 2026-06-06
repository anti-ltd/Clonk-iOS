/**
 Localization page (Onboarding): pick the language the suggestion bar,
 autocomplete, and auto-correction run in. The choice is a `UITextChecker`
 language identifier stored on `KeyboardSettings.keyboardLanguage`; the keyboard
 extension feeds it to its `SuggestionEngine` on the next settings reload. Only
 languages the device can actually spell-check are listed, so a pick is never
 a dead one. The physical key arrangement (QWERTY/AZERTY/…) is a separate
 setting under Style → Layout & Keys.
 */
import SwiftUI
import UIKit
import iUXiOS

struct LocalizationView: View {
    @Environment(AppModel.self) private var model
    @State private var search = ""

    /// One selectable language: the `UITextChecker` identifier plus a
    /// human-readable name resolved against the user's current locale.
    private struct Language: Identifiable {
        let id: String          // UITextChecker identifier, e.g. "en_US"
        let name: String        // localized display name, e.g. "English (US)"
    }

    /// Every language the device can spell-check, de-duplicated by display name
    /// and sorted alphabetically. Computed once per appearance — the available
    /// set is fixed for the process lifetime.
    private var allLanguages: [Language] {
        let locale = Locale.current
        var seen = Set<String>()
        return UITextChecker.availableLanguages
            .map { Language(id: $0, name: locale.localizedString(forIdentifier: $0) ?? $0) }
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var filtered: [Language] {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return allLanguages }
        return allLanguages.filter {
            $0.name.localizedCaseInsensitiveContains(q) || $0.id.localizedCaseInsensitiveContains(q)
        }
    }

    private var selected: String { model.settings.keyboardLanguage }

    private func displayName(for id: String) -> String {
        Locale.current.localizedString(forIdentifier: id) ?? id
    }

    var body: some View {
        List {
            Section {
                Text("Choose the language your typing suggestions, autocomplete, and auto-correction use. Only languages your device can spell-check are listed.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            }

            Section("Current") {
                row(Language(id: selected, name: displayName(for: selected)))
            }

            Section(search.isEmpty ? "All languages" : "Results") {
                ForEach(filtered) { lang in
                    if lang.id != selected { row(lang) }
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search languages")
        .navigationTitle("Localization")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func row(_ lang: Language) -> some View {
        Button {
            model.settings.keyboardLanguage = lang.id
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(lang.name).foregroundStyle(.primary)
                    Text(lang.id).font(.caption).foregroundStyle(.tertiary)
                }
                Spacer()
                if lang.id == selected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
