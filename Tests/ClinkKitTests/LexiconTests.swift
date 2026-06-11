/**
 Lexicon format + query tests, run against the real compiled `.clex`
 resources bundled into the test target (the same files the keyboard ships).
 */
import Foundation
import Testing

/// Anchor class for locating the test bundle (Swift Testing has no XCTestCase).
private final class BundleToken {}

private func bundledLexicon(_ code: String) -> Lexicon? {
    Lexicon.bundled(code, in: Bundle(for: BundleToken.self))
}

@Suite struct LexiconTests {
    @Test func parsesBundledEnglish() throws {
        let lex = try #require(bundledLexicon("en"))
        #expect(lex.wordCount > 40_000)
        #expect(lex.contains("the"))
        #expect(lex.contains("hello"))
        // Everyday informal words UITextChecker never surfaced — the reason
        // the bundled lexicon exists.
        #expect(lex.contains("hey"))
        #expect(lex.contains("lol"))
        #expect(!lex.contains("zzzzzzz"))
        // "the" is one of the most frequent words; sanity-check the quantized scale.
        let logP = try #require(lex.logProbability(of: "the"))
        #expect(logP > -3 && logP <= 0)
    }

    @Test func rejectsGarbageData() {
        #expect(Lexicon(data: Data()) == nil)
        #expect(Lexicon(data: Data("not a lexicon at all".utf8)) == nil)
        // Truncated header with a valid magic must not parse either.
        #expect(Lexicon(data: Data("CLEX".utf8)) == nil)
    }

    @Test func exactLookupRoundTrips() throws {
        let lex = try #require(bundledLexicon("en"))
        for i in stride(from: 0, to: lex.wordCount, by: 1_873) {
            let w = lex.word(at: i)
            #expect(lex.index(of: w) == i, "word \(w) at \(i) should round-trip")
        }
    }

    @Test func prefixRangeIsContiguousAndComplete() throws {
        let lex = try #require(bundledLexicon("en"))
        let range = lex.prefixRange("qu")
        #expect(!range.isEmpty)
        for i in range {
            #expect(lex.word(at: i).hasPrefix("qu"))
        }
        // Neighbors outside the range must not carry the prefix.
        if range.lowerBound > 0 { #expect(!lex.word(at: range.lowerBound - 1).hasPrefix("qu")) }
        if range.upperBound < lex.wordCount { #expect(!lex.word(at: range.upperBound).hasPrefix("qu")) }
    }

    @Test func completionsAreFrequencyOrdered() throws {
        let lex = try #require(bundledLexicon("en"))
        let completions = lex.topCompletions(prefix: "almo", limit: 4)
        #expect(completions.first == "almost")  // far more common than "almond"
        let qs = completions.compactMap { lex.logProbability(of: $0) }
        #expect(qs == qs.sorted(by: >))
        // The literal prefix is never its own completion.
        #expect(!lex.topCompletions(prefix: "the", limit: 5).contains("the"))
    }

    @Test func nextLetterDistributionFollowsCompletions() throws {
        let lex = try #require(bundledLexicon("en"))
        let dist = try #require(lex.nextLetterDistribution(prefix: "th"))
        // "the/this/that/they…" — 'e' must dominate after "th".
        let top = dist.max { $0.value < $1.value }
        #expect(top?.key == "e")
        #expect(abs(dist.values.reduce(0, +) - 1.0) < 1e-9)
    }

    @Test func letterMatrixFallback() throws {
        let lex = try #require(bundledLexicon("en"))
        // 'q' is followed by 'u' almost always.
        let afterQ = try #require(lex.letterDistribution(after: "q"))
        #expect(afterQ.max { $0.value < $1.value }?.key == "u")
        // Word-initial row exists and sums to 1.
        let initial = try #require(lex.letterDistribution(after: nil))
        #expect(abs(initial.values.reduce(0, +) - 1.0) < 1e-9)
        // Letters outside the alphabet degrade to nil, not garbage.
        #expect(lex.letterDistribution(after: "ж") == nil)
    }

    @Test func cyrillicLexiconWorks() throws {
        let lex = try #require(bundledLexicon("ru"))
        #expect(lex.contains("привет"))
        let range = lex.prefixRange("при")
        #expect(!range.isEmpty)
        for i in [range.lowerBound, range.upperBound - 1] {
            #expect(lex.word(at: i).hasPrefix("при"))
        }
    }

    @Test func mergedLexiconAcrossLanguages() {
        let repo = LexiconRepository(bundle: Bundle(for: BundleToken.self))
        let merged = repo.merged(for: ["en_US", "fr_FR"])
        #expect(!merged.isEmpty)
        #expect(merged.contains("hello"))
        #expect(merged.contains("bonjour"))
        // Unknown language codes are dropped, not fatal.
        let none = repo.merged(for: ["xx_XX"])
        #expect(none.isEmpty)
        #expect(none.topCompletions(prefix: "he", limit: 3).isEmpty)
        #expect(none.logProbability(of: "hello") == nil)
    }
}
