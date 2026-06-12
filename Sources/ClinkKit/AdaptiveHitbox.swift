/**
 Adaptive hitboxes — a lightweight replication of iOS's native trick of quietly
 resizing each key's touch target to favour the letter you're most likely to type
 next. We never move the *visual* keys; we only grow the likely keys' hit regions
 and shrink the unlikely ones, then let `KeyTouchRouter`'s nearest-key routing do
 the rest.

 Prediction is a tiny on-device letter bigram model (`LetterPredictor`): given the
 previously typed letter, it scores every letter a..z; `AdaptiveHitbox.factorMap`
 turns those scores into a per-letter frame multiplier centred on 1.0 (the most
 likely next letter swells toward `maxFactor`, the least likely toward
 `minFactor`, an average letter stays put). Cheap enough to run on every touch.
 

 Module: touch · Target: ClinkKit
 Learn: docs/03-touch-and-input.md
 */
import SwiftUI

/// Per-letter hit-target sizing driven by next-letter prediction. All the knobs
/// (grow/shrink ceilings, prediction strength) are passed in from
/// `KeyboardSettings` so the user can tune the feel.
public enum AdaptiveHitbox {
    /// Default grow ceiling — a likely letter's frame may swell to this.
    public static let defaultGrow = 1.35
    /// Default shrink floor — an unlikely letter's frame may contract to this.
    public static let defaultShrink = 0.80
    /// Default prediction strength: how strongly the bigram context overrides the
    /// base letter frequency (0 = ignore context, 1 = context only).
    public static let defaultPredictionWeight = 0.65

    /// Multiplier for every letter a..z given the previous letter. Letters above
    /// the mean predicted probability grow (up to `grow`), letters below it shrink
    /// (down to `shrink`); the mean letter stays at 1.0. Non-letter keys aren't in
    /// the map — callers leave them at 1.0.
    public static func factorMap(prev: Character?,
                                 grow: Double = defaultGrow,
                                 shrink: Double = defaultShrink,
                                 predictionWeight: Double = defaultPredictionWeight) -> [Character: Double] {
        factorMap(distribution: LetterPredictor.distribution(prev: prev, predictionWeight: predictionWeight),
                  grow: grow, shrink: shrink)
    }

    /// Same mapping, but from a precomputed next-letter distribution — the
    /// engine derives one from the actual completion candidates of the word
    /// being typed (see `Lexicon.nextLetterDistribution`), which is per-language
    /// and word-aware where `LetterPredictor`'s tables are English-only.
    public static func factorMap(distribution probs: [Character: Double],
                                 grow: Double = defaultGrow,
                                 shrink: Double = defaultShrink) -> [Character: Double] {
        let vals = Array(probs.values)
        guard let mx = vals.max(), let mn = vals.min(), !vals.isEmpty else { return [:] }
        let mean = vals.reduce(0, +) / Double(vals.count)
        var out: [Character: Double] = [:]
        for (c, p) in probs { out[c] = factor(p: p, mean: mean, mx: mx, mn: mn, grow: grow, shrink: shrink) }
        return out
    }

    /// Convenience single-letter lookup. Returns 1.0 for non-letters.
    public static func factor(forLetter c: Character?, prev: Character?,
                              grow: Double = defaultGrow,
                              shrink: Double = defaultShrink,
                              predictionWeight: Double = defaultPredictionWeight) -> Double {
        guard let c, let ch = c.lowercased().first, ch.isLetter else { return 1.0 }
        return factorMap(prev: prev, grow: grow, shrink: shrink, predictionWeight: predictionWeight)[ch] ?? 1.0
    }

    /// Overlay tint: green = enlarged (likely), orange = shrunk (unlikely),
    /// cyan = unchanged.
    public static func tint(_ factor: Double) -> Color {
        if factor > 1.02 { return .green }
        if factor < 0.98 { return .orange }
        return .cyan
    }

    /// Map a probability to a frame multiplier, normalised two-sided so the most
    /// likely letter reaches `grow` and the least likely reaches `shrink`.
    private static func factor(p: Double, mean: Double, mx: Double, mn: Double,
                               grow: Double, shrink: Double) -> Double {
        if p >= mean {
            let denom = mx - mean
            let rel = denom > 0 ? (p - mean) / denom : 0
            return 1 + (grow - 1) * rel
        } else {
            let denom = mean - mn
            let rel = denom > 0 ? (mean - p) / denom : 0
            return 1 - (1 - shrink) * rel
        }
    }
}

/// A tiny English letter bigram model: P(next letter | previous letter). Just
/// enough to bias the keyboard the way the native one does, without shipping a
/// real language model into the (memory-tight) keyboard extension.
public enum LetterPredictor {
    static let alphabet = Array("abcdefghijklmnopqrstuvwxyz")

    /// English letter frequencies (percent). Normalised to a probability on load.
    static let unigram: [Character: Double] = normalised([
        "e": 12.7, "t": 9.1, "a": 8.2, "o": 7.5, "i": 7.0, "n": 6.7, "s": 6.3,
        "h": 6.1, "r": 6.0, "d": 4.3, "l": 4.0, "c": 2.8, "u": 2.8, "m": 2.4,
        "w": 2.4, "f": 2.2, "g": 2.0, "y": 2.0, "p": 1.9, "b": 1.5, "v": 0.98,
        "k": 0.77, "j": 0.15, "x": 0.15, "q": 0.095, "z": 0.074,
    ])

    /// Most common letters to follow each letter, in descending order. Used to
    /// build a ranked conditional distribution (earlier = more likely). Letters
    /// not listed fall back to the unigram floor.
    static let followers: [Character: [Character]] = [
        "a": Array("ntrlscdbimpgy"),
        "b": Array("eoaluryi"),
        "c": Array("oehatkilru"),
        "d": Array("eioasrud"),
        "e": Array("rnsdaltcmevxi"),
        "f": Array("orieauftl"),
        "g": Array("ehoraisul"),
        "h": Array("eaiotru"),
        "i": Array("nstocledgmarvfzpbkx"),
        "j": Array("uoae"),
        "k": Array("einsaloy"),
        "l": Array("elioaydsutfkmp"),
        "m": Array("eaoipumbsy"),
        "n": Array("gtdeosciankvyfl"),
        "o": Array("nrutfmoslwpvidcabg"),
        "p": Array("eroaliptuhs"),
        "q": Array("u"),
        "r": Array("eoiastydnmrlcukgvfp"),
        "s": Array("tesiohuapclmkwnf"),
        "t": Array("heoiartusywlc"),
        "u": Array("rsntlepcmagidb"),
        "v": Array("eiaouy"),
        "w": Array("aiehonsr"),
        "x": Array("ptcieahu"),
        "y": Array("oespiamtln"),
        "z": Array("eaiozyu"),
    ]

    /// The full a..z probability distribution for the next letter. With no prev
    /// (word start / after space) it's the raw unigram; otherwise it blends the
    /// ranked bigram followers with the unigram base. `predictionWeight` (0...1)
    /// controls the blend: 0 = pure unigram (ignore context), 1 = pure bigram.
    static func distribution(prev: Character?,
                             predictionWeight: Double = AdaptiveHitbox.defaultPredictionWeight) -> [Character: Double] {
        guard let prev, let p = prev.lowercased().first, p.isLetter,
              let fol = followers[p], !fol.isEmpty else {
            return unigram
        }
        let w = max(0, min(1, predictionWeight))
        // Rank → weight (first follower heaviest), then normalise.
        var total = 0.0
        var bigram: [Character: Double] = [:]
        let n = fol.count
        for (i, c) in fol.enumerated() {
            let weight = Double(n - i)
            bigram[c] = weight
            total += weight
        }
        var out: [Character: Double] = [:]
        for c in alphabet {
            let big = total > 0 ? (bigram[c] ?? 0) / total : 0
            out[c] = (1 - w) * (unigram[c] ?? 0) + w * big
        }
        return out
    }

    /// Scale a raw-frequency table so its values sum to 1.
    private static func normalised(_ raw: [Character: Double]) -> [Character: Double] {
        let total = raw.values.reduce(0, +)
        guard total > 0 else { return raw }
        return raw.mapValues { $0 / total }
    }
}
