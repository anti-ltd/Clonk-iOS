/**
 Adaptive hitbox v2: the engine's lexicon-derived next-letter distributions
 and the factor mapping that turns them into hit-rect flex.
 */
import Foundation
import Testing

private final class BundleToken {}

@Suite struct AdaptiveHitboxTests {
    @Test func distributionFactorMapGrowsLikelyShrinksUnlikely() throws {
        let factors = AdaptiveHitbox.factorMap(
            distribution: ["e": 0.6, "a": 0.3, "z": 0.1],
            grow: 1.35, shrink: 0.8)
        #expect(factors["e"] == 1.35)   // max probability hits the grow ceiling
        #expect(factors["z"] == 0.8)    // min probability hits the shrink floor
        let mid = try #require(factors["a"])
        #expect(mid > 0.8 && mid < 1.35)
    }

    @Test func distributionOverloadMatchesLegacyForSameInput() {
        // Same distribution through both entry points → identical factors.
        let dist = LetterPredictor.distribution(prev: "t", predictionWeight: 0.65)
        let legacy = AdaptiveHitbox.factorMap(prev: "t")
        let direct = AdaptiveHitbox.factorMap(distribution: dist)
        #expect(legacy == direct)
    }

    @Test func lexiconNextLetterDistributionIsWordAware() throws {
        let lex = try #require(Lexicon.bundled("en", in: Bundle(for: BundleToken.self)))
        // Mid-word: after "kn" almost everything continues with a vowel —
        // knowledge the English letter-bigram tables (n-follower ranks) lack.
        let dist = try #require(lex.nextLetterDistribution(prefix: "kn"))
        let top = dist.max { $0.value < $1.value }?.key
        #expect(top == "o" || top == "e" || top == "i")  // know/knee/knife…
        // Distribution is normalized.
        #expect(abs(dist.values.reduce(0, +) - 1.0) < 1e-9)
        // Word start falls back to the compiled word-initial matrix row.
        let initial = try #require(lex.letterDistribution(after: nil))
        #expect((initial["t"] ?? 0) > (initial["z"] ?? 0))
    }

    @Test func unknownPrefixDegradesToNilNotGarbage() throws {
        let lex = try #require(Lexicon.bundled("en", in: Bundle(for: BundleToken.self)))
        #expect(lex.nextLetterDistribution(prefix: "qqqq") == nil)
    }
}
