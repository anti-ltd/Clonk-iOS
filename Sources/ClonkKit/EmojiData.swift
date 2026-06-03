import Foundation

/// One section of the emoji keyboard: a tab icon + its emoji.
public struct EmojiCategory: Identifiable, Sendable {
    public let id: String
    /// SF Symbol shown in the category tab bar.
    public let icon: String
    public let emoji: [String]
}

/// The complete Unicode emoji set, grouped into the standard categories. The
/// actual emoji arrays live in `EmojiData.generatedCategories` (generated from
/// Unicode's `emoji-test.txt` by `Tools/GenerateEmojiData.swift`); this enum
/// adds the offline name-based search/suggestion logic on top.
public enum EmojiData {
    /// Every category, in canonical Unicode order. Skin tones are applied at
    /// render time, so these are the neutral base glyphs.
    public static var categories: [EmojiCategory] { generatedCategories }

    // MARK: - Search
    //
    // No keyword table to maintain: every emoji is matched against the official
    // Unicode *names* of its scalars (e.g. "🐶" → "dog face", "❤️" → "red heart",
    // "🏳️‍🌈" → "white flag rainbow"), read straight from `Unicode.Scalar.Properties`.
    // That's offline, zero-data, and tracks the OS's emoji set for free.

    /// Every emoji once, in category order, de-duplicated (hearts appear in both
    /// smileys and symbols) — the corpus the search scans.
    public static let allEmoji: [String] = {
        var seen = Set<String>()
        return categories.flatMap { $0.emoji }.filter { seen.insert($0).inserted }
    }()

    /// emoji → its searchable text (the lowercased Unicode names of its scalars).
    private static let nameIndex: [(emoji: String, name: String)] = allEmoji.map { e in
        let name = e.unicodeScalars
            .compactMap { $0.properties.name }
            .joined(separator: " ")
            .lowercased()
        return (e, name)
    }

    /// Emoji whose Unicode names contain *every* whitespace-separated token in the
    /// query (so "red heart" narrows, it doesn't widen). Empty query → no results.
    public static func search(_ query: String) -> [String] {
        let tokens = query.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !tokens.isEmpty else { return [] }
        return nameIndex
            .filter { entry in tokens.allSatisfy { entry.name.contains($0) } }
            .map(\.emoji)
    }

    /// Emoji to surface in the predictive bar for a just-typed *word*. Matches the
    /// word against the emoji's Unicode name as a whole token (so "dog" → 🐶 from
    /// "dog face", but "do" matches nothing — we wait for a complete word). Results
    /// keep curated order, where the iconic variants are listed first, so "dog"
    /// surfaces 🐶 ahead of 🐕. Bounded to a couple so the bar stays tidy.
    public static func emojiSuggestions(for word: String, limit: Int = 2) -> [String] {
        let w = word.lowercased()
        // Skip stopwords: Unicode names are verbose phrases ("rolling on THE
        // floor laughing", "I LOVE YOU hand sign"), so a bare token match would
        // pop an emoji for everyday function words. Only content words qualify.
        guard w.count >= 2, !stopwords.contains(w) else { return [] }
        var out: [String] = []
        for entry in nameIndex where entry.name.split(separator: " ").map(String.init).contains(w) {
            out.append(entry.emoji)
            if out.count >= limit { break }
        }
        return out
    }

    /// Function words that should never surface an emoji (they only ever match as
    /// incidental words buried in a Unicode name).
    private static let stopwords: Set<String> = [
        "the", "and", "for", "are", "but", "not", "you", "all", "any", "can", "her",
        "was", "one", "our", "out", "his", "has", "had", "him", "she", "who", "its",
        "did", "yes", "let", "put", "say", "too", "use", "this", "that", "with",
        "have", "from", "they", "been", "were", "what", "when", "your", "said",
        "them", "than", "then", "into", "just", "like", "over", "also", "back",
        "after", "other", "their", "there", "these", "would", "could", "about",
        "which", "while", "where", "being", "doing", "going", "new", "old", "off",
        "now", "how", "why", "who", "get", "got", "see", "way", "day", "two", "ten",
    ]
}
