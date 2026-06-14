/**
 `TranslateBar`: the inline Translate strip shown above the keys when the
 Translate panel is open and not yet showing a result. Keys type into the
 compose buffer; a language menu picks the target; the translate action runs it.


 Module: panels · Target: ClinkKit
 Learn: docs/13-extending-panels.md
 */
import SwiftUI

/// The Translate panel's inline compose strip — the keys type into `text` while
/// it's shown. Shows the buffer (tail-truncated so the caret end stays visible),
/// a paste button (Full Access only), a target-language menu, the translate
/// action, and clear.
struct TranslateBar: View {
    let text: String
    let language: TranslateLanguage
    let languages: [TranslateLanguage]
    /// Whether the paste-from-clipboard button is offered (needs Full Access).
    let canPaste: Bool
    let theme: Theme
    let onPaste: () -> Void
    let onPickLanguage: (TranslateLanguage) -> Void
    let onTranslate: () -> Void
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            if canPaste {
                iconButton("doc.on.clipboard", action: onPaste)
                chipDivider
            }
            Text(text.isEmpty ? "Type or paste to translate…" : text)
                .font(.system(size: 16))
                .lineLimit(1)
                .truncationMode(.head)
                .foregroundStyle(text.isEmpty
                    ? theme.keyText.color.opacity(0.35)
                    : theme.keyText.color)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
            chipDivider
            languageMenu
            chipDivider
            // Distinct (accent) translate action — the primary thing here.
            Button(action: onTranslate) {
                Image(systemName: "character.bubble.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(text.isEmpty
                        ? theme.keyText.color.opacity(0.3)
                        : theme.accent.color)
                    .frame(width: 44)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // Not disabled even when empty: in panel mode this button also returns
            // to the full panel, so it must stay tappable (the dim colour is hint
            // enough). The empty case is handled downstream ("Nothing to translate").
            chipDivider
            iconButton("xmark", action: onClear)
        }
    }

    // MARK: - Pieces

    private var languageMenu: some View {
        Menu {
            ForEach(languages) { lang in
                Button { onPickLanguage(lang) } label: {
                    if lang.id == language.id {
                        Label(lang.name, systemImage: "checkmark")
                    } else {
                        Text(lang.name)
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Text(language.name)
                    .font(.system(size: 14, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(theme.keyText.color.opacity(0.7))
            .padding(.horizontal, 8)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
        }
    }

    private func iconButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button { action() } label: {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .foregroundStyle(theme.keyText.color.opacity(0.5))
                .frame(width: 40)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var chipDivider: some View {
        Rectangle()
            .fill(theme.keyText.color.opacity(0.15))
            .frame(width: 0.5)
            .padding(.vertical, 11)
    }
}
