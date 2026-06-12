/**
 `SuggestionBar`: the autocomplete / correction strip above the keys. Shows
 the pending correction (tap-to-keep vs accept) and up to three predictions,
 plus emoji suggestions when available.
 */
import SwiftUI

/// The autocomplete strip above the keys, à la the native iOS predictive bar.
/// When an auto-correction is pending it leads with the user's literal word in
/// quotes (tap to keep) and shows the fix as a highlighted "primary" chip that
/// `space` will apply — then fills the rest with predictions. With no pending
/// correction it's just the predictions. Empty slots hold space so the bar
/// always fills the top of the keyboard.
struct SuggestionBar: View {
    let suggestions: [String]
    let autocorrection: Autocorrection?
    /// Emoji matching the word being typed — rendered as plain chips on the right
    /// and inserted (replacing the word) only when tapped. Never space-applied.
    let emoji: [String]
    let theme: Theme
    let onTap: (String) -> Void
    let onKeepTyped: () -> Void
    let onEmoji: (String) -> Void
    /// Vertical hit-target multiplier — see `KeyboardSettings.suggestionHitboxScale`.
    var hitboxScale: Double = 1.0

    private enum Kind { case keep, primary, normal, emoji }
    private struct Candidate: Identifiable {
        let id = UUID()
        let text: String
        let kind: Kind
    }

    private var candidates: [Candidate] {
        var words: [Candidate] = []
        if let c = autocorrection {
            words.append(Candidate(text: c.from, kind: .keep))
            words.append(Candidate(text: c.to, kind: .primary))
            for s in suggestions
            where s.caseInsensitiveCompare(c.to) != .orderedSame
                && s.caseInsensitiveCompare(c.from) != .orderedSame {
                words.append(Candidate(text: s, kind: .normal))
            }
        } else {
            for s in suggestions { words.append(Candidate(text: s, kind: .normal)) }
        }
        // Reserve the right end for emoji chips when there are any, so they're
        // never crowded out — always leaving at least one word slot.
        let emojiCands = emoji.prefix(2).map { Candidate(text: $0, kind: .emoji) }
        let wordSlots = max(1, 3 - emojiCands.count)
        return Array(words.prefix(wordSlots)) + emojiCands
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(candidates.enumerated()), id: \.element.id) { idx, cand in
                if idx > 0 { divider }
                chip(cand)
            }
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private func chip(_ c: Candidate) -> some View {
        Button {
            switch c.kind {
            case .keep:  onKeepTyped()
            case .emoji: onEmoji(c.text)
            default:     onTap(c.text)
            }
        } label: {
            chipLabel(c)
                .font(.system(size: 17,
                              weight: theme.keyFontWeight.fontWeight,
                              design: theme.keyFontDesign.fontDesign))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .hitboxExpand(hitboxScale, baseHeight: KeyboardCanvas.Metrics.suggestionBarHeight)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private func chipLabel(_ c: Candidate) -> some View {
        switch c.kind {
        case .keep:
            // The literal typed word, quoted — tap to reject the correction.
            Text("“\(c.text)”")
                .foregroundStyle(theme.keyText.color.opacity(0.7))
        case .primary:
            // The correction `space` will apply — highlighted like iOS, and
            // matching the theme: a real glass pill on Liquid Glass, a tinted
            // capsule on solid.
            let pill = Text(c.text)
                .foregroundStyle(theme.keyText.color)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
            if theme.material == .liquidGlass, #available(iOS 26.0, *) {
                // No `.interactive()` here: that makes the glass layer respond to
                // touches itself, which swallows the tap before the enclosing
                // `Button` sees it — the highlighted correction chip then looks
                // tappable but does nothing. Plain (non-interactive) glass lets the
                // Button receive the tap and apply the correction.
                pill.glassEffect(.regular.tint(theme.accent.color.opacity(0.55)),
                                 in: Capsule())
            } else {
                pill.background(theme.accent.color.opacity(0.22), in: Capsule())
            }
        case .normal:
            Text(c.text).foregroundStyle(theme.keyText.color)
        case .emoji:
            // A plain (non-primary) emoji chip — slightly larger so the glyph
            // reads, and tinted nothing so it never looks like the space-applied
            // correction.
            Text(c.text).font(.system(size: 24))
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(theme.keyText.color.opacity(0.15))
            .frame(width: 0.5)
            .padding(.vertical, 11)
    }
}
