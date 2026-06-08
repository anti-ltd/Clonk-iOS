/**
 Offline suggestion engine: autocomplete predictions, auto-correction, and emoji
 suggestions. Uses `UITextChecker` for spell/correction data and a custom
 Damerau-Levenshtein + bigram ranker for predictions. Shared between the keyboard
 extension and the in-app showcase typer.
 */
import Foundation
import UIKit

/// Offline autocomplete + auto-correct via `UITextChecker`. Lives in ClinkKit so
/// it's shared by the keyboard extension (which runs it from a debounced work
/// item, off the hot typing path) and the in-app device showcase (which runs it
/// as the typing simulator fills the bubble, so the suggestion bar is live).
@MainActor
public final class SuggestionEngine {
    private let checker = UITextChecker()
    /// The `UITextChecker` language driving completions/guesses/spell-check.
    /// Set via `setLanguage`; guaranteed to be a value the device can check.
    private var language = "en_US"
    /// The language-specific next-word/contraction/ranking tables layered on top
    /// of `UITextChecker` (the checker is language-agnostic; these aren't). Kept
    /// in sync with `language` by `setLanguage`. See `LanguageHeuristics`.
    private var heuristics = LanguageHeuristics.forLanguage("en_US")

    /// Point the engine at a spelling/completion language (a `UITextChecker`
    /// identifier such as "en_US" or "fr_FR"). Unsupported identifiers fall back
    /// to "en_US" — UITextChecker silently returns nothing for a language it
    /// can't load, which would leave the bar dead, so we guard against it here.
    /// Clears the correction cache (its entries were resolved in the old tongue).
    public func setLanguage(_ identifier: String) {
        let resolved = UITextChecker.availableLanguages.contains(identifier) ? identifier : "en_US"
        guard resolved != language else { return }
        language = resolved
        heuristics = LanguageHeuristics.forLanguage(resolved)
        correctionCache = nil
    }

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
           let fix = heuristics.contractions[partial.lowercased()],
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
            let lc = heuristics.commonWords.contains(l.element.lowercased())
            let rc = heuristics.commonWords.contains(r.element.lowercased())
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
            return heuristics.sentenceStarters
        }
        let picks = heuristics.bigrams[previousWord!.lowercased()] ?? heuristics.commonFallback
        return Array(picks.prefix(3))
    }

    // MARK: - Swipe / glide typing

    private let swipeDecoder = SwipeDecoder()
    /// Lowercased word pool for swipe decoding, built from the current language's
    /// heuristics. Cached and rebuilt only when the language changes (the tables
    /// are static per language).
    private var swipeVocabCache: (language: String, words: [String])?

    private func swipeVocabulary() -> [String] {
        if let c = swipeVocabCache, c.language == language { return c.words }
        var set = Set<String>()
        set.formUnion(heuristics.commonWords)
        set.formUnion(heuristics.commonFallback.map { $0.lowercased() })
        set.formUnion(heuristics.sentenceStarters.map { $0.lowercased() })
        for (k, vs) in heuristics.bigrams {
            set.insert(k)
            for v in vs { set.insert(v.lowercased()) }
        }
        let words = Array(set)
        swipeVocabCache = (language, words)
        return words
    }

    /// Decode a glide/swipe trace into ranked word candidates. `keyCenters` maps
    /// each lowercased letter to its key's centre in the trace's coordinate space.
    /// Context (`previousWord` / `sentenceStart`) gently biases plausible
    /// next-words upward. The first result is the best guess; the rest are
    /// alternates. An empty array means nothing plausible matched.
    public func swipeCandidates(path: [CGPoint],
                                keyCenters: [Character: CGPoint],
                                previousWord: String?,
                                sentenceStart: Bool,
                                limit: Int = 4) -> [String] {
        let bias = Set(nextWords(previousWord: previousWord, sentenceStart: sentenceStart)
                        .map { $0.lowercased() })
        let words = swipeDecoder.decode(path: path,
                                        keyCenters: keyCenters,
                                        vocabulary: swipeVocabulary(),
                                        bias: bias,
                                        limit: limit)
        // Capitalise the lead candidate at a sentence start, matching the bar's
        // auto-capitalisation so a swiped sentence opener reads correctly.
        guard sentenceStart, let first = words.first, !first.isEmpty else { return words }
        var result = words
        result[0] = first.prefix(1).uppercased() + first.dropFirst()
        return result
    }
}
