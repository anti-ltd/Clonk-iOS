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
///
/// Necessarily `@MainActor`: the iOS 26 SDK annotates `UITextChecker` (and
/// even `UITextChecker.availableLanguages`) as main-actor, so the checker work
/// CANNOT be moved to a background queue — a dual-engine attempt didn't
/// compile under Swift 6. The extension compensates by *scheduling*: the
/// debounced bar compute waits for a quiet window after the last keystroke
/// (see `KeyboardViewController.quietGatedCompute`) so its tens-of-ms stall
/// never lands in the middle of a key press/release animation.
@MainActor
public final class SuggestionEngine {
    private let checker = UITextChecker()
    /// The active `UITextChecker` languages driving completions/guesses/spell-check,
    /// in priority order. Set via `setLanguages`; every entry is guaranteed to be a
    /// value the device can actually check. Multiple languages run simultaneously
    /// (bilingual typing) — completions/guesses are merged across them, and a word
    /// counts as misspelled only when it's misspelled in *every* active language,
    /// so a valid word in any of them is left alone.
    private var languages = [SuggestionEngine.resolveLanguage("en_US")]
    /// The language-specific next-word/contraction/ranking tables layered on top
    /// of `UITextChecker` (the checker is language-agnostic; these aren't), merged
    /// across all active languages. Kept in sync with `languages` by `setLanguages`.
    /// See `LanguageHeuristics`.
    private var heuristics = LanguageHeuristics.forLanguages(["en_US"])
    /// The compiled frequency lexicons for the active languages (see `Lexicon`).
    /// Empty when no `.clex` resources are bundled — every consumer degrades to
    /// the checker-only behavior in that case.
    private var lexicon = LexiconRepository.shared.merged(for: ["en_US"])
    /// Opt-in user learning (see `UserAdaptation`). nil when the learning
    /// setting is off — every read below treats nil as "no adaptation".
    private var adaptation: UserAdaptation?
    /// Confidence model for spelling fixes (see `CorrectionScorer`). Its
    /// adjacency table tracks the active layout via `setLayout`.
    private var scorer = CorrectionScorer()

    /// Tell the scorer which physical layout is active so adjacent-key typos
    /// ("hwllo" → "hello") cost less than arbitrary substitutions.
    public func setLayout(_ layout: KeyboardLayout) {
        scorer.adjacency = KeyAdjacency.forLayout(layout)
        correctionCache = nil
    }

    /// Attach/detach the learning store (driven by the `learningEnabled`
    /// setting). Clears caches whose contents depend on learned words.
    public func setAdaptation(_ adaptation: UserAdaptation?) {
        guard (self.adaptation == nil) != (adaptation == nil) else {
            self.adaptation = adaptation
            return
        }
        self.adaptation = adaptation
        correctionCache = nil
        swipeVocabCache = nil
        prebuildSwipeVocabulary()
    }

    /// Point the engine at one or more spelling/completion languages (`UITextChecker`
    /// identifiers such as "en_US" / "fr_FR"). Each is resolved to a language the
    /// device actually has (UITextChecker silently returns nothing for a language it
    /// can't load — which would leave the bar AND autocorrect dead), de-duplicated,
    /// and order is preserved. Empty input falls back to English. Clears the caches,
    /// whose entries were resolved against the old language set.
    public func setLanguages(_ identifiers: [String]) {
        var resolved: [String] = []
        var seen = Set<String>()
        for id in identifiers {
            let r = Self.resolveLanguage(id)
            if seen.insert(r).inserted { resolved.append(r) }
        }
        if resolved.isEmpty { resolved = [Self.resolveLanguage("en_US")] }
        guard resolved != languages else { return }
        languages = resolved
        heuristics = LanguageHeuristics.forLanguages(resolved)
        lexicon = LexiconRepository.shared.merged(for: resolved)
        correctionCache = nil
        swipeVocabCache = nil
        prebuildSwipeVocabulary()
    }

    /// Single-language convenience — sets the active set to just `identifier`.
    public func setLanguage(_ identifier: String) { setLanguages([identifier]) }

    // MARK: - Multi-language checker fan-out
    //
    // Each helper runs `UITextChecker` against every active language and combines
    // the results. With one language active they cost exactly what the old single
    // calls did; with two they're a linear 2× — fine on the debounced/per-word
    // paths these feed.

    /// Completions across all active languages, first-seen order, de-duplicated.
    private func mergedCompletions(_ partial: String, _ range: NSRange) -> [String] {
        var out: [String] = []
        var seen = Set<String>()
        for lang in languages {
            for w in checker.completions(forPartialWordRange: range, in: partial, language: lang) ?? []
            where seen.insert(w.lowercased()).inserted { out.append(w) }
        }
        return out
    }

    /// Spelling guesses across all active languages, first-seen order, de-duplicated.
    private func mergedGuesses(_ partial: String, _ range: NSRange) -> [String] {
        var out: [String] = []
        var seen = Set<String>()
        for lang in languages {
            for w in checker.guesses(forWordRange: range, in: partial, language: lang) ?? []
            where seen.insert(w.lowercased()).inserted { out.append(w) }
        }
        return out
    }

    /// A word is "misspelled" only when it's misspelled in *every* active language —
    /// so a word valid in any one of them (e.g. Spanish "como" while English is also
    /// on) is never flagged or auto-corrected.
    private func misspelledEverywhere(_ partial: String, _ range: NSRange) -> Bool {
        for lang in languages {
            let loc = checker.rangeOfMisspelledWord(
                in: partial, range: range, startingAt: 0, wrap: false, language: lang).location
            if loc == NSNotFound { return false }
        }
        return true
    }

    /// Map any requested identifier onto one `UITextChecker` actually supports on
    /// this device, so completions/guesses are never silently empty:
    /// 1. exact match; 2. hyphen→underscore normalised match ("en-US" → "en_US");
    /// 3. any available variant of the same base language ("en_US" → "en_GB");
    /// 4. a system English variant; 5. whatever the device lists first.
    /// Falls back to the raw identifier only if the device lists nothing at all.
    static func resolveLanguage(_ identifier: String) -> String {
        let available = UITextChecker.availableLanguages
        guard !available.isEmpty else { return identifier }
        if available.contains(identifier) { return identifier }

        let normalized = identifier.replacingOccurrences(of: "-", with: "_")
        if available.contains(normalized) { return normalized }

        let base = String(normalized.prefix(while: { $0 != "_" })).lowercased()
        if let sameBase = available.first(where: {
            String($0.lowercased().prefix(while: { $0 != "_" })) == base
        }) {
            return sameBase
        }
        if let english = available.first(where: { $0.lowercased().hasPrefix("en") }) {
            return english
        }
        return available.first ?? identifier
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

    public struct Result: Sendable {
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

    /// `previousWord` is the completed word before the cursor (drives next-word
    /// prediction when there's no partial); `context` is the word before the
    /// *partial* being typed (drives correction confidence via bigrams).
    public func compute(partial: String, previousWord: String?, sentenceStart: Bool,
                        autocorrect: Bool, autoPunctuation: Bool, rejected: String?,
                        context: String? = nil) -> Result {
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
        // The bundled frequency lexicon surfaces everyday words the device
        // checker is too shallow for ("hey", "lol", "yeah") and provides the
        // frequency ranking; checker completions add the long tail (names,
        // locale words) on top.
        let lexiconCompletions = lexicon.topCompletions(prefix: partial, limit: 6)
        // Learned words complete too — a name typed daily beats the dictionary.
        let learnedCompletions = adaptation?.completions(prefix: partial, limit: 3) ?? []
        let completions = rank(learnedCompletions + lexiconCompletions + mergedCompletions(partial, range))
        let guesses = mergedGuesses(partial, range)
        let isMisspelled = misspelledEverywhere(partial, range)

        // Bar candidates: frequency-ranked pool of completions + guesses, minus
        // the literal (the bar shows that itself).
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
            rejected: rejected, context: context, isMisspelled: isMisspelled,
            guesses: guesses, completions: completions)
        store(correction, partial: partial, autocorrect: autocorrect,
              autoPunctuation: autoPunctuation, rejected: rejected, context: context)

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
                           autoPunctuation: Bool, rejected: String?,
                           context: String? = nil) -> Autocorrection? {
        guard !partial.isEmpty else { return nil }
        let key = CorrectionKey(partial: partial, autocorrect: autocorrect,
                                autoPunctuation: autoPunctuation, rejected: rejected,
                                context: context)
        if let c = correctionCache, c.key == key { return c.value }
        // Compute the checker inputs lazily: `resolveCorrection` only forces them
        // if the cheap contraction/lexicon paths miss and the word is misspelled.
        let range = NSRange(location: 0, length: partial.utf16.count)
        let result = resolveCorrection(
            partial: partial, autocorrect: autocorrect, autoPunctuation: autoPunctuation,
            rejected: rejected, context: context,
            isMisspelled: self.misspelledEverywhere(partial, range),
            guesses: self.mergedGuesses(partial, range),
            completions: self.rank(self.mergedCompletions(partial, range)))
        store(result, partial: partial, autocorrect: autocorrect,
              autoPunctuation: autoPunctuation, rejected: rejected, context: context)
        return result
    }

    /// The shared correction decision, used by both `compute` (which passes its
    /// already-computed checker results) and `correction(for:)` (which passes
    /// autoclosures that hit the checker only if reached). The `@autoclosure`
    /// params are what make the lean path lean — `isMisspelled`/`guesses`/
    /// `completions` aren't evaluated until the logic actually needs them.
    private func resolveCorrection(
        partial: String, autocorrect: Bool, autoPunctuation: Bool, rejected: String?,
        context: String?,
        isMisspelled: @autoclosure () -> Bool,
        guesses: @autoclosure () -> [String],
        completions: @autoclosure () -> [String]
    ) -> Autocorrection? {
        // Auto-punctuation: turn an apostrophe-less contraction into its real
        // form (ive → I've, dont → don't). Takes precedence over the spelling
        // path; no length floor, so 2-char "im" works. No checker needed.
        // A correction the user has repeatedly rejected (reverted or cancelled)
        // is suppressed permanently, not just for the session.
        let persistentlyRejected = adaptation?.isRejected(partial) == true

        if autoPunctuation, partial != rejected, !persistentlyRejected,
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
        if autocorrect, partial != rejected, !persistentlyRejected,
           let expansion = lexiconExact[partial.lowercased()],
           expansion.caseInsensitiveCompare(partial) != .orderedSame {
            return Autocorrection(from: partial, to: expansion)
        }

        // Everything past here is a spelling fix: needs autocorrect on, the word
        // not rejected, not one the user has *taught* the keyboard (a learned
        // word is treated as correctly spelled even if every checker disagrees),
        // and — first checker touch — actually misspelled. A correctly-spelled
        // word stops right here, one cheap call in.
        guard autocorrect, partial != rejected, !persistentlyRejected,
              adaptation?.isLearned(partial) != true,
              isMisspelled() else { return nil }

        // Highest-confidence spelling fix: a single adjacent-letter transposition
        // that yields a real word ("teh" → "the", "adn" → "and"). This is the
        // signature typo of fast typing, and a one-swap-to-valid match is
        // unambiguous enough to apply with NO length floor.
        if let swap = transpositionFix(for: partial) {
            return Autocorrection(from: partial, to: swap)
        }

        // General spelling correction. The ≥3 floor stays: 2-char fragments are
        // too ambiguous for a generic guess (transpositions/contractions above
        // handle the confident short cases).
        guard partial.count >= 3 else { return nil }

        // With no frequency data (no .clex bundled) fall back to the legacy
        // rule: first checker guess within Damerau-Levenshtein distance 2.
        guard !lexicon.isEmpty else {
            if let best = guesses().first ?? completions().first,
               best.caseInsensitiveCompare(partial) != .orderedSame,
               editDistance(partial, best) <= 2 {
                return Autocorrection(from: partial, to: best)
            }
            return nil
        }

        // Confidence-scored correction: pool the checker's guesses and
        // completions, score each by keyboard-aware edit cost + frequency +
        // bigram context, and only silently commit a fix that clears the auto
        // threshold. A merely-plausible fix stays in the bar (the pool already
        // contains it) where a deliberate tap can choose it — never a silent
        // replacement the user has to fight.
        let candidates = Array(guesses().prefix(6)) + Array(completions().prefix(4))
        let best = scorer.best(
            candidates: candidates, typed: partial,
            logFrequency: { [lexicon, adaptation] word in
                let lower = word.lowercased()
                let logP = lexicon.logProbability(of: lower)
                // A learned word ranks at least like a moderately-common one.
                if adaptation?.isLearned(lower) == true { return max(logP ?? -9, -5) }
                return logP
            },
            contextLogP: { [lexicon] word in
                guard let context else { return nil }
                return lexicon.contextLogProbability(of: word, given: context)
            })
        if let best, best.verdict == .autocorrect {
            return Autocorrection(from: partial, to: best.word)
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
        let context: String?
    }
    private var correctionCache: (key: CorrectionKey, value: Autocorrection?)?

    private func store(_ value: Autocorrection?, partial: String, autocorrect: Bool,
                       autoPunctuation: Bool, rejected: String?, context: String?) {
        correctionCache = (CorrectionKey(partial: partial, autocorrect: autocorrect,
                                         autoPunctuation: autoPunctuation, rejected: rejected,
                                         context: context), value)
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
            // Valid (correctly spelled) in any active language → an accepted fix.
            if !misspelledEverywhere(candidate, r) { return candidate }
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

    /// Stable sort by corpus frequency (so "almost" outranks "almond"),
    /// preserving the checker's original order among equally-ranked words.
    /// Words the lexicon doesn't know sort below known ones, with the old
    /// `commonWords` membership as the tie-break so behavior degrades to the
    /// pre-lexicon ranking when no `.clex` resources are bundled.
    private func rank(_ words: [String]) -> [String] {
        words.enumerated().sorted { l, r in
            let ls = rankScore(l.element), rs = rankScore(r.element)
            if ls != rs { return ls > rs }
            return l.offset < r.offset
        }.map(\.element)
    }

    /// Ranking key for one bar candidate: lexicon log10 probability when known
    /// (−9…0), else a floor that still lets `commonWords` members beat unknowns.
    /// Learned words ride on top — a word the user types often outranks a
    /// merely-common one, and a learned word the corpus has never seen still
    /// surfaces (floor −7 puts it above rare dictionary words).
    private func rankScore(_ word: String) -> Double {
        let lower = word.lowercased()
        let boost = adaptation?.rankBoost(for: lower) ?? 0
        if let logP = lexicon.logProbability(of: lower) { return logP + boost }
        if boost > 0 { return -7 + boost }
        return heuristics.commonWords.contains(lower) ? -10 : -12
    }

    /// Next-letter probability distribution for the adaptive hitboxes: derived
    /// from the lexicon's actual completion set for the partial word being
    /// typed (word-aware, per-language), falling back to the compiled
    /// letter-bigram matrix at a word start or off-dictionary prefix. nil when
    /// no lexicons are bundled — the router then uses its built-in English
    /// tables. Point lookups on the mmapped lexicon: safe to call per keystroke.
    public func nextLetterDistribution(partial: String) -> [Character: Double]? {
        guard !lexicon.isEmpty else { return nil }
        let lower = partial.lowercased()
        if !lower.isEmpty, let d = lexicon.nextLetterDistribution(prefix: lower) {
            return d
        }
        return lexicon.letterDistribution(after: lower.last)
    }

    // MARK: - Next-word prediction (offline, dictionary-based)

    /// Up to three predictions for the next word, so the bar is never empty.
    /// Sentence starters at a sentence start; otherwise the corpus bigram
    /// model's most likely followers of `previousWord`, then the hand-written
    /// heuristic bigrams, then high-frequency filler — in that order, so the
    /// real language model leads whenever it knows the word.
    private func nextWords(previousWord: String?, sentenceStart: Bool) -> [String] {
        if sentenceStart || previousWord == nil {
            return heuristics.sentenceStarters
        }
        let prev = previousWord!.lowercased()
        let modeled = lexicon.nextWords(after: prev, limit: 3)
        if !modeled.isEmpty { return modeled }
        let picks = heuristics.bigrams[prev] ?? heuristics.commonFallback
        return Array(picks.prefix(3))
    }

    // MARK: - Swipe / glide typing

    private let swipeDecoder = SwipeDecoder()
    /// Background worker for the heavier lexicon scans (vocab builds).
    private let core = PredictionCore()
    /// Per-language word budget for the swipe vocabulary when lexicons are
    /// bundled. ~20k covers everything realistically swipeable; the decoder's
    /// anchor buckets keep the per-swipe scan far smaller.
    private static let swipeWordsPerLanguage = 20_000
    /// Lowercased word pool for swipe decoding. With lexicons bundled it's the
    /// per-language top words + heuristics + learned words, prebuilt off-main
    /// by `PredictionCore` whenever languages/learning change (with a sync
    /// first-swipe fallback). Without lexicons it's the legacy build:
    /// heuristics + bundled SwipeLexicon + a–z checker seeding.
    private var swipeVocabCache: (key: SwipeVocabKey, words: [String])?

    private struct SwipeVocabKey: Equatable {
        let languages: [String]
        let learnedCount: Int
    }

    private var swipeVocabKey: SwipeVocabKey {
        SwipeVocabKey(languages: languages,
                      learnedCount: adaptation?.learnedWords().count ?? 0)
    }

    /// Main-actor-only vocabulary contributions: the heuristic tables and the
    /// user's learned words. Cheap to gather.
    private func swipeExtras() -> [String] {
        var out: [String] = []
        out.append(contentsOf: heuristics.commonWords)
        out.append(contentsOf: heuristics.commonFallback)
        out.append(contentsOf: heuristics.sentenceStarters)
        for (k, vs) in heuristics.bigrams {
            out.append(k)
            out.append(contentsOf: vs)
        }
        if let adaptation { out.append(contentsOf: adaptation.learnedWords()) }
        return out
    }

    /// Kick an off-main vocabulary rebuild so the first swipe never pays for
    /// it. No-op when the cache is already current or no lexicons are bundled
    /// (the legacy build needs the main-actor checker anyway).
    private func prebuildSwipeVocabulary() {
        guard !lexicon.isEmpty else { return }
        let key = swipeVocabKey
        guard swipeVocabCache?.key != key else { return }
        let lex = lexicon
        let extras = swipeExtras()
        Task { [weak self, core] in
            let words = await core.swipeVocabulary(
                lexicon: lex, perLanguage: Self.swipeWordsPerLanguage, extras: extras)
            guard let self else { return }
            // Languages/learning may have moved on while we built — only a
            // result that still matches the current inputs may land.
            if self.swipeVocabKey == key { self.swipeVocabCache = (key, words) }
        }
    }

    private func swipeVocabulary() -> [String] {
        let key = swipeVocabKey
        if let c = swipeVocabCache, c.key == key { return c.words }

        // Lexicon-backed build (sync fallback for a swipe that beat the
        // prebuild): top words per language + the main-actor extras.
        if !lexicon.isEmpty {
            let words = PredictionCore.makeSwipeVocabulary(
                lexicon: lexicon, perLanguage: Self.swipeWordsPerLanguage,
                extras: swipeExtras())
            swipeVocabCache = (key, words)
            return words
        }

        // Legacy build (no .clex bundled): heuristics + bundled frequency list
        // + a light single-letter UITextChecker pass for device-/locale-specific
        // long-tail words (~26 calls per active language).
        var set = Set<String>()
        for w in swipeExtras() { set.insert(w.lowercased()) }
        set.formUnion(SwipeLexicon.words)
        for lang in languages {
            for ch in "abcdefghijklmnopqrstuvwxyz" {
                let seed = String(ch)
                let completions = checker.completions(
                    forPartialWordRange: NSRange(location: 0, length: seed.utf16.count),
                    in: seed, language: lang) ?? []
                for w in completions where w.count >= 2 { set.insert(w.lowercased()) }
            }
        }
        let words = Array(set)
        swipeVocabCache = (key, words)
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
        let lex = lexicon
        let adapt = adaptation
        let words = swipeDecoder.decode(path: path,
                                        keyCenters: keyCenters,
                                        vocabulary: swipeVocabulary(),
                                        bias: bias,
                                        logFrequency: lex.isEmpty ? nil : { word in
                                            // Learned words score like moderately
                                            // common ones, so they're swipeable
                                            // even when the corpus is silent.
                                            let logP = lex.logProbability(of: word)
                                            if adapt?.isLearned(word) == true {
                                                return max(logP ?? -9, -5)
                                            }
                                            return logP
                                        },
                                        frequencyRank: SwipeLexicon.rank,
                                        limit: limit)
        // Capitalise the lead candidate at a sentence start, matching the bar's
        // auto-capitalisation so a swiped sentence opener reads correctly.
        guard sentenceStart, let first = words.first, !first.isEmpty else { return words }
        var result = words
        result[0] = first.prefix(1).uppercased() + first.dropFirst()
        return result
    }
}
