import Foundation
import UIKit

/// Offline autocomplete + auto-correct via `UITextChecker`. Lives in ClinkKit so
/// it's shared by the keyboard extension (which runs it from a debounced work
/// item, off the hot typing path) and the in-app device showcase (which runs it
/// as the typing simulator fills the bubble, so the suggestion bar is live).
@MainActor
public final class SuggestionEngine {
    private let checker = UITextChecker()
    private let language = "en_US"

    /// The user's supplementary lexicon (Contacts names + Settings → text
    /// replacements), fetched by the keyboard via `requestSupplementaryLexicon`.
    /// `exact` maps a lowercased shortcut → its expansion (for autocorrect-style
    /// substitution: "omw" → "On my way!"); `entries` is the same set kept for
    /// prefix completion (half-typed contact name → full name). The native
    /// keyboard folds these straight into its bar — this is the one extra hook
    /// Apple *does* hand a third-party keyboard, so we use it.
    private var lexiconExact: [String: String] = [:]
    private var lexiconEntries: [(prefix: String, text: String)] = []

    public init() {}

    /// Feed in the user's supplementary lexicon (call after
    /// `requestSupplementaryLexicon` resolves). Entries are (userInput → expansion).
    public func setLexicon(_ entries: [(String, String)]) {
        var exact: [String: String] = [:]
        var list: [(prefix: String, text: String)] = []
        for (input, text) in entries where !input.isEmpty && !text.isEmpty {
            exact[input.lowercased()] = text
            list.append((input.lowercased(), text))
        }
        lexiconExact = exact
        lexiconEntries = list
        // The lexicon feeds the exact-match correction path, so any cached
        // decision could now be wrong — drop it.
        correctionCache = nil
    }

    public struct Result {
        public var predictions: [String]
        public var correction: Autocorrection?
        /// Emoji matching the word being typed, shown as non-primary bar chips
        /// (never applied by space — only a deliberate tap inserts them).
        public var emoji: [String]
        public init(predictions: [String], correction: Autocorrection?, emoji: [String] = []) {
            self.predictions = predictions
            self.correction = correction
            self.emoji = emoji
        }
    }

    public func compute(partial: String, previousWord: String?, sentenceStart: Bool,
                        autocorrect: Bool, autoPunctuation: Bool, rejected: String?) -> Result {
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

        // Lexicon prefix matches (contact names, shortcuts) lead the bar so a
        // half-typed name/shortcut completes — the dictionary can't know these.
        if !lexiconEntries.isEmpty {
            let lower = partial.lowercased()
            let hits = lexiconEntries
                .filter { $0.prefix.hasPrefix(lower) && $0.text.caseInsensitiveCompare(partial) != .orderedSame }
                .map(\.text)
            if !hits.isEmpty { pool = hits + pool }
        }

        var seen = Set<String>()
        pool = pool.filter { seen.insert($0.lowercased()).inserted }

        // Auto-correction / -complete: the most likely intended word, applied on
        // space when the typed text isn't itself a complete valid word. The
        // decision logic lives in `resolveCorrection`, shared with the lean
        // `correction(for:)` path the space keypress uses — here we hand it the
        // completions / guesses / misspelled status we already computed for the
        // bar, so it does no extra checker work. Cache the result so a space hit
        // moments later (same word) is a free lookup.
        let correction = resolveCorrection(
            partial: partial, autocorrect: autocorrect, autoPunctuation: autoPunctuation,
            rejected: rejected, isMisspelled: isMisspelled,
            guesses: guesses, completions: completions)
        store(correction, partial: partial, autocorrect: autocorrect,
              autoPunctuation: autoPunctuation, rejected: rejected)

        // When we're not correcting, lead the bar with the literal so the user
        // can see/keep what they typed; otherwise the bar shows it as the "keep"
        // chip already, so leave it out of the alternatives.
        var predictions = pool
        if correction == nil { predictions.insert(partial, at: 0) }
        return Result(predictions: Array(predictions.prefix(4)), correction: correction,
                      emoji: EmojiData.emojiSuggestions(for: partial))
    }

    /// Just the auto-correction for a finished word — no predictions, no emoji,
    /// no pool building. This is the hot path: it runs *synchronously on the space
    /// keypress* (see `applyPendingAutocorrect`), so it must stay lean. The common
    /// cases cost zero or one `UITextChecker` call — a contraction/lexicon match
    /// returns before touching the checker, and a correctly-spelled word bails
    /// after a single `rangeOfMisspelledWord`. Only an actually-misspelled word
    /// pays for guesses/completions, and that's exactly when the work is wanted.
    ///
    /// Returns the same correction `compute` would, and shares its cache — so if
    /// the debounced bar already evaluated this word, this is a dictionary hit.
    public func correction(for partial: String, autocorrect: Bool,
                           autoPunctuation: Bool, rejected: String?) -> Autocorrection? {
        guard !partial.isEmpty else { return nil }
        let key = CorrectionKey(partial: partial, autocorrect: autocorrect,
                                autoPunctuation: autoPunctuation, rejected: rejected)
        if let c = correctionCache, c.key == key { return c.value }
        // Compute the checker inputs lazily: `resolveCorrection` only forces them
        // if the cheap contraction/lexicon paths miss and the word is misspelled.
        let range = NSRange(location: 0, length: partial.utf16.count)
        let result = resolveCorrection(
            partial: partial, autocorrect: autocorrect, autoPunctuation: autoPunctuation,
            rejected: rejected,
            isMisspelled: self.checker.rangeOfMisspelledWord(
                in: partial, range: range, startingAt: 0, wrap: false,
                language: self.language).location != NSNotFound,
            guesses: self.checker.guesses(forWordRange: range, in: partial, language: self.language) ?? [],
            completions: self.rank(self.checker.completions(
                forPartialWordRange: range, in: partial, language: self.language) ?? []))
        store(result, partial: partial, autocorrect: autocorrect,
              autoPunctuation: autoPunctuation, rejected: rejected)
        return result
    }

    /// The shared correction decision, used by both `compute` (which passes its
    /// already-computed checker results) and `correction(for:)` (which passes
    /// autoclosures that hit the checker only if reached). The `@autoclosure`
    /// params are what make the lean path lean — `isMisspelled`/`guesses`/
    /// `completions` aren't evaluated until the logic actually needs them.
    private func resolveCorrection(
        partial: String, autocorrect: Bool, autoPunctuation: Bool, rejected: String?,
        isMisspelled: @autoclosure () -> Bool,
        guesses: @autoclosure () -> [String],
        completions: @autoclosure () -> [String]
    ) -> Autocorrection? {
        // Auto-punctuation: turn an apostrophe-less contraction into its real
        // form (ive → I've, dont → don't). Takes precedence over the spelling
        // path; no length floor, so 2-char "im" works. No checker needed.
        if autoPunctuation, partial != rejected,
           let fix = Self.contractions[partial.lowercased()],
           fix.caseInsensitiveCompare(partial) != .orderedSame {
            // Honour a typed leading capital; never downcase (I-forms keep their I).
            let cased = partial.first?.isUppercase == true
                ? fix.prefix(1).uppercased() + fix.dropFirst() : fix
            // Curly apostrophe so it matches the smart-quotes a manually typed
            // contraction would get (both ride the auto-punctuation switch).
            let curly = cased.replacingOccurrences(of: "'", with: "\u{2019}")
            return Autocorrection(from: partial, to: curly)
        }

        // A user lexicon shortcut that exactly matches what's typed expands like
        // the native keyboard's text replacement ("omw" → "On my way!"). Also no
        // checker — a plain dictionary lookup.
        if autocorrect, partial != rejected,
           let expansion = lexiconExact[partial.lowercased()],
           expansion.caseInsensitiveCompare(partial) != .orderedSame {
            return Autocorrection(from: partial, to: expansion)
        }

        // Everything past here is a spelling fix: needs autocorrect on, the word
        // not rejected, and — first checker touch — the word actually misspelled.
        // A correctly-spelled word stops right here, one cheap call in.
        guard autocorrect, partial != rejected, isMisspelled() else { return nil }

        // Highest-confidence spelling fix: a single adjacent-letter transposition
        // that yields a real word ("teh" → "the", "adn" → "and"). This is the
        // signature typo of fast typing, and a one-swap-to-valid match is
        // unambiguous enough to apply with NO length floor.
        if let swap = transpositionFix(for: partial) {
            return Autocorrection(from: partial, to: swap)
        }

        // General spelling correction — only when the candidate is *close* to what
        // was typed. We gate on Damerau-Levenshtein distance so a far-flung guess
        // still shows in the bar (the user can tap it) but is never silently
        // committed on space. The ≥3 floor stays: 2-char fragments are too
        // ambiguous for a generic guess (transpositions/contractions above handle
        // the confident short cases).
        if partial.count >= 3,
           let best = guesses().first ?? completions().first,
           best.caseInsensitiveCompare(partial) != .orderedSame,
           editDistance(partial, best) <= 2 {
            return Autocorrection(from: partial, to: best)
        }
        return nil
    }

    // MARK: - Correction cache
    //
    // A single slot is enough: corrections are resolved one finished word at a
    // time, and the win we want is the debounced bar compute priming the value
    // that the (synchronous) space keypress reads back a beat later. Keyed on
    // every input that affects the result, so a stale flag/rejection can't leak.
    // Cleared when the lexicon changes (it feeds the lexicon-exact path).

    private struct CorrectionKey: Equatable {
        let partial: String
        let autocorrect: Bool
        let autoPunctuation: Bool
        let rejected: String?
    }
    private var correctionCache: (key: CorrectionKey, value: Autocorrection?)?

    private func store(_ value: Autocorrection?, partial: String, autocorrect: Bool,
                       autoPunctuation: Bool, rejected: String?) {
        correctionCache = (CorrectionKey(partial: partial, autocorrect: autocorrect,
                                         autoPunctuation: autoPunctuation, rejected: rejected), value)
    }

    /// If swapping a single pair of adjacent letters turns a misspelled word into
    /// a correctly-spelled one, return that word — otherwise nil. Case rides along
    /// naturally (we swap the original characters, so "Teh" → "The"). Checks each
    /// neighbour pair left-to-right and returns the first valid result.
    private func transpositionFix(for word: String) -> String? {
        let chars = Array(word)
        guard chars.count >= 2 else { return nil }
        for i in 0..<(chars.count - 1) where chars[i] != chars[i + 1] {
            var swapped = chars
            swapped.swapAt(i, i + 1)
            let candidate = String(swapped)
            if candidate.caseInsensitiveCompare(word) == .orderedSame { continue }
            let r = NSRange(location: 0, length: candidate.utf16.count)
            let mis = checker.rangeOfMisspelledWord(
                in: candidate, range: r, startingAt: 0, wrap: false, language: language).location
            if mis == NSNotFound { return candidate }
        }
        return nil
    }

    /// Damerau-Levenshtein distance (substitution/insert/delete + adjacent
    /// transposition), case-insensitive. Used to gate auto-correction so we only
    /// silently commit a fix that's *near* what was typed. Runs once per word
    /// (off the per-keystroke path), so the simple O(n·m) table is fine.
    private func editDistance(_ a: String, _ b: String) -> Int {
        let s = Array(a.lowercased()), t = Array(b.lowercased())
        let n = s.count, m = t.count
        if n == 0 { return m }
        if m == 0 { return n }
        var d = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in 0...n { d[i][0] = i }
        for j in 0...m { d[0][j] = j }
        for i in 1...n {
            for j in 1...m {
                let cost = s[i - 1] == t[j - 1] ? 0 : 1
                d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost)
                if i > 1, j > 1, s[i - 1] == t[j - 2], s[i - 2] == t[j - 1] {
                    d[i][j] = min(d[i][j], d[i - 2][j - 2] + 1)
                }
            }
        }
        return d[n][m]
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

    /// Apostrophe-less → contraction, for auto-punctuation. Conservative: it
    /// deliberately omits forms that are also common standalone words (its,
    /// were, ill, well, wed, id, lets…), so we never rewrite a valid word.
    /// Keys are lowercased; values carry canonical casing (I-forms stay capital).
    private static let contractions: [String: String] = [
        "im": "I'm", "ive": "I've",
        "dont": "don't", "doesnt": "doesn't", "didnt": "didn't",
        "isnt": "isn't", "wasnt": "wasn't", "arent": "aren't", "werent": "weren't",
        "havent": "haven't", "hasnt": "hasn't", "hadnt": "hadn't",
        "cant": "can't", "couldnt": "couldn't", "wont": "won't",
        "wouldnt": "wouldn't", "shouldnt": "shouldn't", "mustnt": "mustn't",
        "youre": "you're", "youve": "you've", "youll": "you'll", "youd": "you'd",
        "theyre": "they're", "theyve": "they've", "theyll": "they'll", "theyd": "they'd",
        "weve": "we've",
        "hes": "he's", "shes": "she's",
        "thats": "that's", "whats": "what's", "whos": "who's", "wheres": "where's",
        "theres": "there's", "heres": "here's", "hows": "how's",
        "couldve": "could've", "wouldve": "would've", "shouldve": "should've",
    ]

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
