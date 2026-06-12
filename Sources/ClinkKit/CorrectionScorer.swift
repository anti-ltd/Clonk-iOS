/**
 `CorrectionScorer`: the confidence model deciding whether a spelling fix is
 safe to apply silently on space, should only be offered in the bar, or isn't
 worth showing at all. Replaces the old "first checker guess within distance 2"
 rule, which ranked an obscure distance-2 guess the same as a common one.

 score = −(keyboard-aware edit cost)
         + freqWeight · (log10 wordProb + 9)        // 0…9, one unit per decade
         + contextWeight · (log10 P(word|prev) + 6) // 0…6 when a bigram is known

 Pure and Sendable — fully unit-testable without UIKit.
 

 Module: prediction · Target: ClinkKit
 Learn: docs/04-prediction.md
 */
import Foundation

public struct CorrectionScorer: Sendable {
    /// Adjacent-key substitutions ("hwllo" → "hello", w next to e) cost less
    /// than a full edit: they're the signature of a fat-fingered tap.
    public var adjacentSubstitutionCost: Double = 0.45
    public var substitutionCost: Double = 1.0
    public var insertDeleteCost: Double = 0.9
    /// Transposing neighbors ("teh") is fast typing's signature typo.
    public var transpositionCost: Double = 0.7
    /// Frequency term weight: ~4 decades of frequency outweigh one full edit.
    public var freqWeight: Double = 0.25
    /// Context term weight: a known "prev → word" bigram adds up to ~0.9.
    public var contextWeight: Double = 0.15

    /// Scores at or above this are committed silently on space.
    public var autoThreshold: Double = 0.0
    /// Scores at or above this (but below auto) are offered in the bar only.
    public var showThreshold: Double = -1.5

    /// Letter adjacency on the active layout, from `KeyAdjacency.forLayout`.
    /// Empty = no adjacency discounts (all substitutions cost full price).
    public var adjacency: [Character: Set<Character>] = [:]

    public init() {}

    public enum Verdict: Equatable, Sendable {
        case autocorrect    // commit silently on space
        case suggest        // bar-only; never silently committed
        case reject
    }

    public struct Scored: Equatable, Sendable {
        public let word: String
        public let score: Double
        public let verdict: Verdict
    }

    /// Score one candidate fix for `typed`. `logFrequency` is the candidate's
    /// corpus log10 probability (nil = unknown word, floored); `contextLogP`
    /// is log10 P(candidate | previous word) when a bigram is known.
    public func score(candidate: String, typed: String,
                      logFrequency: Double?, contextLogP: Double?) -> Scored {
        let edit = weightedEditCost(typed.lowercased(), candidate.lowercased())
        var s = -edit
        s += freqWeight * ((logFrequency ?? -9) + 9)
        if let contextLogP { s += contextWeight * (contextLogP + 6) }
        let verdict: Verdict = s >= autoThreshold ? .autocorrect
            : s >= showThreshold ? .suggest : .reject
        return Scored(word: candidate, score: s, verdict: verdict)
    }

    /// Pick the best candidate, best-score first. Ties keep input order (the
    /// checker's own confidence ordering).
    public func best(candidates: [String], typed: String,
                     logFrequency: (String) -> Double?,
                     contextLogP: (String) -> Double?) -> Scored? {
        var bestScored: Scored?
        for c in candidates where c.caseInsensitiveCompare(typed) != .orderedSame {
            let s = score(candidate: c, typed: typed,
                          logFrequency: logFrequency(c), contextLogP: contextLogP(c))
            if s.verdict == .reject { continue }
            if bestScored == nil || s.score > bestScored!.score { bestScored = s }
        }
        return bestScored
    }

    /// Damerau-Levenshtein with per-operation weights and adjacency-discounted
    /// substitutions. Words are short (≤ ~20 chars), so the plain O(n·m) table
    /// is fine — this runs once per finished word, not per keystroke.
    public func weightedEditCost(_ a: String, _ b: String) -> Double {
        let s = Array(a), t = Array(b)
        let n = s.count, m = t.count
        if n == 0 { return Double(m) * insertDeleteCost }
        if m == 0 { return Double(n) * insertDeleteCost }
        // Early out: a length gap > 2 can never be a plausible typo fix.
        if abs(n - m) > 2 { return .infinity }
        var d = Array(repeating: Array(repeating: 0.0, count: m + 1), count: n + 1)
        for i in 0...n { d[i][0] = Double(i) * insertDeleteCost }
        for j in 0...m { d[0][j] = Double(j) * insertDeleteCost }
        for i in 1...n {
            for j in 1...m {
                let subCost: Double
                if s[i - 1] == t[j - 1] {
                    subCost = 0
                } else if adjacency[s[i - 1]]?.contains(t[j - 1]) == true {
                    subCost = adjacentSubstitutionCost
                } else {
                    subCost = substitutionCost
                }
                d[i][j] = min(d[i - 1][j] + insertDeleteCost,
                              d[i][j - 1] + insertDeleteCost,
                              d[i - 1][j - 1] + subCost)
                if i > 1, j > 1, s[i - 1] == t[j - 2], s[i - 2] == t[j - 1] {
                    d[i][j] = min(d[i][j], d[i - 2][j - 2] + transpositionCost)
                }
            }
        }
        return d[n][m]
    }
}

/// Letter adjacency derived from a `KeyboardLayout`'s rows — same row
/// neighbors plus the staggered overlaps on the rows above/below. Works for
/// any preset (QWERTY, AZERTY, ЙЦУКЕН, …) without per-layout tables.
public enum KeyAdjacency {
    public static func forLayout(_ layout: KeyboardLayout) -> [Character: Set<Character>] {
        var adj: [Character: Set<Character>] = [:]
        let rows: [[Character]] = layout.rows.map { row in row.compactMap(\.first) }
        func link(_ a: Character, _ b: Character) {
            guard a != b else { return }
            adj[a, default: []].insert(b)
            adj[b, default: []].insert(a)
        }
        for (r, row) in rows.enumerated() {
            for (c, ch) in row.enumerated() {
                if c + 1 < row.count { link(ch, row[c + 1]) }
                guard r + 1 < rows.count else { continue }
                let below = rows[r + 1]
                // Rows are centred; map this key onto the row below by offset
                // and link the one or two keys it overlaps.
                let shift = Double(row.count - below.count) / 2
                let projected = Double(c) - shift
                for cc in [Int(projected.rounded(.down)), Int(projected.rounded(.up))]
                where cc >= 0 && cc < below.count {
                    link(ch, below[cc])
                }
            }
        }
        return adj
    }
}
