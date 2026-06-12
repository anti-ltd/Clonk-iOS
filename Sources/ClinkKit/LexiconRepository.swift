/**
 `LexiconRepository`: loads and caches the bundled `.clex` lexicons, keyed by
 base language code, and builds the merged multi-language view matching
 `SuggestionEngine.setLanguages` semantics (multiple languages active at once,
 priority order preserved).
 

 Module: prediction · Target: ClinkKit
 Learn: docs/04-prediction.md
 */
import Foundation

/// Process-wide cache of loaded lexicons. Loading is an mmap + header parse,
/// so misses are cheap, but the cache keeps repeat lookups allocation-free and
/// lets every consumer (engine, prediction core, hitboxes) share one instance.
public final class LexiconRepository: @unchecked Sendable {
    public static let shared = LexiconRepository()

    private let lock = NSLock()
    private var cache: [String: Lexicon?] = [:]
    private var ngramCache: [String: NgramModel?] = [:]
    private let bundle: Bundle

    public init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    /// "en_US" / "en-GB" / "en" → "en". The `.clex` resources are per base
    /// language; regional variants share one lexicon.
    public static func baseCode(_ identifier: String) -> String {
        let normalized = identifier.replacingOccurrences(of: "-", with: "_")
        return String(normalized.prefix(while: { $0 != "_" })).lowercased()
    }

    /// The lexicon for a checker-style identifier, or nil when no `.clex` is
    /// bundled for that language (everything degrades to checker-only behavior).
    public func lexicon(for identifier: String) -> Lexicon? {
        let code = Self.baseCode(identifier)
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[code] { return cached }
        let loaded = Lexicon.bundled(code, in: bundle)
        cache[code] = loaded
        return loaded
    }

    /// The word-bigram model paired with a language's lexicon, when bundled.
    public func ngram(for identifier: String) -> NgramModel? {
        let code = Self.baseCode(identifier)
        lock.lock()
        defer { lock.unlock() }
        if let cached = ngramCache[code] { return cached }
        let loaded = NgramModel.bundled(code, in: bundle)
        ngramCache[code] = loaded
        return loaded
    }

    /// Lexicons (+ paired bigram models) for the active language set, priority
    /// order, misses dropped.
    public func merged(for identifiers: [String]) -> MergedLexicon {
        var seen = Set<String>()
        var lexicons: [Lexicon] = []
        var ngrams: [NgramModel?] = []
        for id in identifiers {
            let code = Self.baseCode(id)
            guard seen.insert(code).inserted else { continue }
            if let lex = lexicon(for: id) {
                lexicons.append(lex)
                ngrams.append(ngram(for: id))
            }
        }
        return MergedLexicon(lexicons: lexicons, ngrams: ngrams)
    }
}

/// The active language set as one queryable view. Same semantics as the
/// engine's checker fan-out: a word is known if any language knows it, and
/// ranking uses the best probability across languages.
public struct MergedLexicon: Sendable {
    public let lexicons: [Lexicon]
    /// Bigram models index-aligned with `lexicons` (nil where not bundled).
    public let ngrams: [NgramModel?]

    public init(lexicons: [Lexicon], ngrams: [NgramModel?] = []) {
        self.lexicons = lexicons
        self.ngrams = ngrams.count == lexicons.count
            ? ngrams
            : Array(repeating: nil, count: lexicons.count)
    }

    /// True when no `.clex` resources resolved — callers keep legacy behavior.
    public var isEmpty: Bool { lexicons.isEmpty }

    public func contains(_ word: String) -> Bool {
        lexicons.contains { $0.contains(word) }
    }

    /// Best (highest) log10 probability across the active languages.
    public func logProbability(of word: String) -> Double? {
        lexicons.compactMap { $0.logProbability(of: word) }.max()
    }

    /// Frequency-ranked completions merged across languages, best first,
    /// de-duplicated case-insensitively.
    public func topCompletions(prefix: String, limit: Int) -> [String] {
        guard !lexicons.isEmpty else { return [] }
        var scored: [(word: String, logP: Double)] = []
        for lex in lexicons {
            for w in lex.topCompletions(prefix: prefix, limit: limit) {
                scored.append((w, lex.logProbability(of: w) ?? -9))
            }
        }
        var seen = Set<String>()
        return scored.sorted { $0.logP > $1.logP }
            .filter { seen.insert($0.word.lowercased()).inserted }
            .prefix(limit).map(\.word)
    }

    /// Most likely next words after `previous`, merged across languages by
    /// blended score: conditional bigram probability plus a small unigram
    /// prior, so among equally-likely followers the more common word leads.
    public func nextWords(after previous: String, limit: Int) -> [String] {
        let prev = previous.lowercased()
        var scored: [(word: String, score: Double)] = []
        for (i, lex) in lexicons.enumerated() {
            guard let ngram = ngrams[i], let prevID = lex.index(of: prev) else { continue }
            for f in ngram.followers(of: prevID, limit: limit * 2) {
                let word = lex.word(at: f.wordID)
                scored.append((word, f.logP + 0.2 * lex.logProbability(at: f.wordID)))
            }
        }
        var seen = Set<String>()
        return scored.sorted { $0.score > $1.score }
            .filter { seen.insert($0.word).inserted }
            .prefix(limit).map(\.word)
    }

    /// log10 P(`word` | `previous`) — best across languages; nil when no model
    /// has the pair.
    public func contextLogProbability(of word: String, given previous: String) -> Double? {
        let prev = previous.lowercased(), next = word.lowercased()
        var best: Double?
        for (i, lex) in lexicons.enumerated() {
            guard let ngram = ngrams[i],
                  let prevID = lex.index(of: prev),
                  let nextID = lex.index(of: next),
                  let p = ngram.logProbability(next: nextID, given: prevID) else { continue }
            best = max(best ?? -.infinity, p)
        }
        return best
    }

    /// Next-letter distribution for the current partial word: per-language
    /// completion-derived distributions blended by each language's share of
    /// total completion mass (a prefix that's clearly French shifts the blend
    /// to the French continuation letters automatically).
    public func nextLetterDistribution(prefix: String) -> [Character: Double]? {
        var blended: [Character: Double] = [:]
        for lex in lexicons {
            guard let dist = lex.nextLetterDistribution(prefix: prefix) else { continue }
            // Weight by the prefix's total probability mass in this language.
            let mass = lex.prefixRange(prefix).reduce(0.0) { $0 + pow(10, lex.logProbability(at: $1)) }
            for (ch, p) in dist { blended[ch, default: 0] += p * mass }
        }
        guard !blended.isEmpty else { return nil }
        let total = blended.values.reduce(0, +)
        return blended.mapValues { $0 / total }
    }

    /// Letter-level fallback distribution (word start or unknown prefix),
    /// averaged across the active languages.
    public func letterDistribution(after letter: Character?) -> [Character: Double]? {
        var blended: [Character: Double] = [:]
        var contributors = 0.0
        for lex in lexicons {
            guard let dist = lex.letterDistribution(after: letter) else { continue }
            contributors += 1
            for (ch, p) in dist { blended[ch, default: 0] += p }
        }
        guard contributors > 0 else { return nil }
        return blended.mapValues { $0 / contributors }
    }
}
