/**
 Localization page (Onboarding): pick the language(s) the suggestion bar,
 autocomplete, and auto-correction run in. Each choice is a `UITextChecker`
 language identifier; the set is stored on `KeyboardSettings.keyboardLanguages`
 and the keyboard extension feeds it to its `SuggestionEngine` on the next
 settings reload. Multiple languages run *simultaneously* — type Spanish and
 English in the same field and both get completions, with a word only
 auto-corrected when it's wrong in every active language. Only languages the
 device can actually spell-check are listed, so a pick is never a dead one. The
 physical key arrangement (QWERTY/AZERTY/…) is a separate setting under
 Style → Layout & Keys.
 */
import SwiftUI
import UIKit
import iUXiOS

struct LocalizationView: View {
    @Environment(AppModel.self) private var model
    @Environment(SidebarState.self) private var sidebar
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.cardCornerRadius) private var cardCornerRadius
    @Environment(\.specialKeyTint) private var specialKeyTint
    @State private var search = ""

    private var themeAccent: Color {
        model.settings.resolvedTheme(dark: colorScheme == .dark).accent.color
    }

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

    /// The active set, in priority order.
    private var active: [String] { model.settings.keyboardLanguages }

    private func displayName(for id: String) -> String {
        Locale.current.localizedString(forIdentifier: id) ?? id
    }

    /// Add or remove a language from the active set. Keeps at least one active
    /// (you can't end up with no spell-check language), and never reorders the
    /// survivors. Layout is intentionally left alone — it's an independent setting.
    private func toggle(_ id: String) {
        var langs = model.settings.keyboardLanguages
        if let idx = langs.firstIndex(of: id) {
            guard langs.count > 1 else { return }   // keep at least one
            langs.remove(at: idx)
        } else {
            langs.append(id)
        }
        model.settings.keyboardLanguages = langs
    }

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(spacing: UX.cardSpacing) {
                searchField

                Text("Choose one or more languages for your typing suggestions, autocomplete, and auto-correction. Pick several to type them at once — e.g. Spanish and English together — and a word is only corrected when it's wrong in every one. Only languages your device can spell-check are listed. The key layout (QWERTY/AZERTY/…) is a separate setting.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                CardSection("Input") {
                    ToggleRow("Accent popups",
                              subtitle: "Hold a letter for accents (é, ü, ñ …).",
                              isOn: $model.settings.accentPopupsEnabled)
                }

                CardSection(active.count > 1 ? "Active (\(active.count))" : "Active") {
                    ForEach(Array(active.enumerated()), id: \.element) { idx, id in
                        if idx > 0 { Divider() }
                        row(Language(id: id, name: displayName(for: id)))
                    }
                }

                let others = filtered.filter { !active.contains($0.id) }
                CardSection(search.isEmpty ? "All languages" : "Results") {
                    ForEach(Array(others.enumerated()), id: \.element.id) { idx, lang in
                        if idx > 0 { Divider() }
                        row(lang)
                    }
                    if others.isEmpty {
                        Text("No results for \"\(search)\"")
                            .foregroundStyle(.secondary)
                            .padding(.vertical, UX.rowVPadding)
                    }
                }

                Text("Don't see a language? Its spell-check dictionary ships with the system keyboard. Add it in **Settings → General → Keyboard → Keyboards** (e.g. Spanish), then return here — it'll appear in the list.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, UX.screenPadding)
            .padding(.top, UX.cardSpacing)
            .padding(.bottom, UX.screenPadding)
        }
        .navigationTitle("Localization")
        .navigationBarTitleDisplayMode(.inline)
        .navTrailingButton("textformat.abc") { sidebar.navigate?(.layout) }
        .tint(themeAccent)
        .themePageBackground()
    }

    /// In-content search field. Replaces the system `.searchable` drawer, whose
    /// full-width bar collided with the custom leading/trailing nav buttons that
    /// `RootView` overlays on the top row.
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search languages", text: $search)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !search.isEmpty {
                Button {
                    search = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .fill(specialKeyTint ?? Color(.secondarySystemBackground))
        )
    }

    @ViewBuilder
    private func row(_ lang: Language) -> some View {
        let isActive = active.contains(lang.id)
        // The last remaining active language can't be turned off — there's always
        // at least one spell-check language.
        let isLocked = isActive && active.count == 1
        Button {
            toggle(lang.id)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(lang.name).foregroundStyle(.primary)
                    Text(lang.id).font(.caption).foregroundStyle(.tertiary)
                }
                Spacer()
                if isActive {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(isLocked ? Color.secondary : themeAccent)
                }
            }
            .padding(.vertical, UX.rowVPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isLocked)
    }
}

#if DEBUG
#Preview { LocalizationView().clinkPreview() }
#endif
