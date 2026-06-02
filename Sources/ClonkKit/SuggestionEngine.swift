import Foundation
import UIKit

/// Offline autocomplete + auto-correct via `UITextChecker`. Lives in ClonkKit so
/// it's shared by the keyboard extension (which runs it from a debounced work
/// item, off the hot typing path) and the in-app device showcase (which runs it
/// as the typing simulator fills the bubble, so the suggestion bar is live).
@MainActor
public final class SuggestionEngine {
    private let checker = UITextChecker()
    private let language = "en_US"

    public init() {}

    public struct Result {
        public var predictions: [String]
        public var correction: Autocorrection?
        public init(predictions: [String], correction: Autocorrection?) {
            self.predictions = predictions
            self.correction = correction
        }
    }

    public func compute(partial: String, previousWord: String?, sentenceStart: Bool,
                        autocorrect: Bool, rejected: String?) -> Result {
        // No partial yet → predict the next word so the bar is never blank.
        guard !partial.isEmpty else {
            return Result(predictions: nextWords(previousWord: previousWord, sentenceStart: sentenceStart),
                          correction: nil)
        }

        let range = NSRange(location: 0, length: partial.utf16.count)

        // Completions = words that START WITH the prefix (e.g. "almo" → almost,
        // almond). Guesses = spelling fixes (e.g. "almo" → also). For a prefix,
        // a completion is usually what's intended, so completions lead — and we
        // rank them so common words ("almost") beat rare ones ("almoner").
        let completions = rank(checker.completions(forPartialWordRange: range, in: partial, language: language) ?? [])
        let guesses = checker.guesses(forWordRange: range, in: partial, language: language) ?? []
        let isMisspelled = checker.rangeOfMisspelledWord(
            in: partial, range: range, startingAt: 0, wrap: false, language: language).location != NSNotFound

        // Bar candidates: common-ranked pool of completions + guesses, minus the
        // literal (the bar shows that itself).
        var pool = rank(completions + guesses).filter { $0.caseInsensitiveCompare(partial) != .orderedSame }
        var seen = Set<String>()
        pool = pool.filter { seen.insert($0.lowercased()).inserted }

        // Auto-correction / -complete: the most likely intended word, applied on
        // space when the typed text isn't itself a complete valid word. Prefer a
        // completion (autocomplete) over a spelling guess (autocorrect). Skips
        // case-only changes and anything the user just rejected.
        var correction: Autocorrection?
        if autocorrect, isMisspelled, partial.count >= 3, partial != rejected {
            if let best = completions.first ?? guesses.first,
               best.caseInsensitiveCompare(partial) != .orderedSame {
                correction = Autocorrection(from: partial, to: best)
            }
        }

        // When we're not correcting, lead the bar with the literal so the user
        // can see/keep what they typed; otherwise the bar shows it as the "keep"
        // chip already, so leave it out of the alternatives.
        var predictions = pool
        if correction == nil { predictions.insert(partial, at: 0) }
        return Result(predictions: Array(predictions.prefix(4)), correction: correction)
    }

    /// Stable sort putting common words first (so "almost" outranks "almond"),
    /// preserving the checker's original order among equally-common words.
    private func rank(_ words: [String]) -> [String] {
        words.enumerated().sorted { l, r in
            let lc = Self.commonWords.contains(l.element.lowercased())
            let rc = Self.commonWords.contains(r.element.lowercased())
            if lc != rc { return lc }
            return l.offset < r.offset
        }.map(\.element)
    }

    // MARK: - Next-word prediction (offline, dictionary-based)

    /// Up to three predictions for the next word, so the bar is never empty.
    /// Sentence starters at a sentence start; otherwise words that commonly
    /// follow `previousWord`, falling back to high-frequency words.
    private func nextWords(previousWord: String?, sentenceStart: Bool) -> [String] {
        if sentenceStart || previousWord == nil {
            return Self.sentenceStarters
        }
        let picks = Self.bigrams[previousWord!.lowercased()] ?? Self.commonFallback
        return Array(picks.prefix(3))
    }

    /// Capitalised openers shown at the start of a sentence.
    private static let sentenceStarters = ["I", "I'm", "The"]

    /// High-frequency words shown when we have no specific follow-on.
    private static let commonFallback = ["the", "to", "and"]

    /// A set of common English words used to rank completions by likelihood —
    /// `UITextChecker` returns completions alphabetically, so without this "almo"
    /// surfaces "almond" before "almost". Membership (not exact frequency) is
    /// enough to float the everyday word to the top.
    private static let commonWords: Set<String> = [
        "a", "able", "about", "above", "after", "again", "against", "all", "almost",
        "alone", "along", "already", "also", "although", "always", "am", "among",
        "an", "and", "another", "answer", "any", "anyone", "anything", "are", "around",
        "as", "ask", "at", "away", "back", "bad", "be", "because", "become", "been",
        "before", "began", "begin", "behind", "being", "believe", "best", "better",
        "between", "big", "both", "bring", "business", "but", "buy", "by", "call",
        "came", "can", "cannot", "car", "care", "change", "child", "city", "close",
        "come", "company", "could", "country", "course", "day", "days", "did", "different",
        "do", "does", "done", "down", "during", "each", "early", "easy", "eat", "end",
        "enough", "even", "evening", "ever", "every", "everyone", "everything", "example",
        "eyes", "face", "fact", "family", "far", "feel", "feeling", "few", "find", "fine",
        "first", "follow", "food", "for", "found", "free", "friend", "friends", "from",
        "full", "fun", "general", "get", "give", "go", "going", "good", "got", "great",
        "group", "had", "hand", "happen", "happy", "hard", "has", "have", "he", "head",
        "hear", "heard", "hello", "help", "her", "here", "high", "him", "himself", "his",
        "home", "hope", "house", "how", "however", "i", "idea", "if", "important", "in",
        "into", "is", "it", "its", "just", "keep", "kind", "knew", "know", "land", "large",
        "last", "late", "later", "learn", "leave", "left", "less", "let", "life", "light",
        "like", "line", "little", "live", "long", "look", "lot", "love", "made", "make",
        "man", "many", "may", "maybe", "me", "mean", "might", "mind", "money", "more",
        "morning", "most", "mother", "move", "much", "must", "my", "name", "near", "need",
        "never", "new", "next", "nice", "night", "no", "not", "nothing", "now", "number",
        "of", "off", "often", "old", "on", "once", "one", "only", "open", "or", "order",
        "other", "our", "out", "over", "own", "part", "people", "perfect", "perhaps",
        "person", "place", "play", "please", "point", "possible", "probably", "problem",
        "put", "question", "quite", "rather", "really", "reason", "remember", "right",
        "room", "run", "said", "same", "saw", "say", "school", "second", "see", "seem",
        "seen", "send", "set", "several", "she", "should", "show", "side", "since",
        "small", "so", "some", "someone", "something", "sometimes", "soon", "sorry",
        "sound", "special", "start", "started", "still", "stop", "story", "such", "sure",
        "system", "take", "talk", "tell", "than", "thank", "thanks", "that", "the",
        "their", "them", "then", "there", "these", "they", "thing", "things", "think",
        "this", "those", "though", "thought", "three", "through", "time", "to", "today",
        "together", "told", "tomorrow", "tonight", "too", "took", "town", "true", "try",
        "turn", "two", "under", "understand", "until", "up", "upon", "us", "use", "used",
        "very", "wait", "walk", "want", "was", "watch", "water", "way", "we", "week",
        "well", "went", "were", "what", "when", "where", "whether", "which", "while",
        "white", "who", "whole", "why", "will", "with", "within", "without", "woman",
        "word", "words", "work", "world", "would", "write", "wrong", "year", "years",
        "yes", "yet", "you", "young", "your", "yourself",
    ]

    /// A compact common-bigram map: word → words that frequently follow it.
    /// Not a full language model — just enough that mid-sentence predictions
    /// feel plausible and the bar always has something useful.
    private static let bigrams: [String: [String]] = [
        "i": ["am", "have", "think", "don't", "was", "will"],
        "i'm": ["going", "not", "so", "just", "sorry"],
        "the": ["best", "same", "first", "most", "other"],
        "a": ["lot", "few", "little", "good", "great"],
        "to": ["be", "the", "do", "get", "go"],
        "you": ["are", "can", "have", "know", "want"],
        "what": ["is", "are", "do", "time", "happened"],
        "how": ["are", "do", "much", "many", "about"],
        "when": ["are", "you", "is", "the", "will"],
        "where": ["are", "is", "you", "the", "do"],
        "why": ["are", "is", "do", "not", "would"],
        "thanks": ["for", "so", "a"],
        "thank": ["you"],
        "good": ["morning", "luck", "idea", "to"],
        "is": ["the", "a", "that", "it", "this"],
        "are": ["you", "the", "we", "they", "going"],
        "have": ["a", "to", "been", "you", "the"],
        "can": ["you", "i", "we", "be", "do"],
        "do": ["you", "not", "the", "it", "that"],
        "it": ["is", "was", "will", "would", "should"],
        "this": ["is", "was", "will", "one", "weekend"],
        "that": ["is", "was", "the", "would", "i"],
        "we": ["are", "can", "will", "should", "need"],
        "of": ["the", "course", "my", "a", "them"],
        "and": ["the", "i", "then", "we", "a"],
        "on": ["the", "my", "a", "it", "your"],
        "in": ["the", "a", "my", "this", "order"],
        "for": ["the", "a", "you", "me", "your"],
        "my": ["friend", "name", "phone", "family", "house"],
        "see": ["you", "the", "if", "what", "that"],
        "let": ["me", "us", "them", "it"],
        "please": ["let", "send", "call", "find"],
        "hello": ["there", "everyone"],
        "hi": ["there", "everyone"],
        "no": ["problem", "worries", "i", "one"],
        "yes": ["i", "please", "it", "of"],
        "ok": ["i", "thanks", "sounds", "let"],
        "okay": ["i", "thanks", "sounds", "let"],
        "going": ["to", "out", "home", "back"],
        "want": ["to", "a", "some", "the"],
        "need": ["to", "a", "some", "the"],
    ]
}
