/**
 CorrectionScorer goldens against the real bundled English lexicon + bigram
 model: the typos that must silently fix, the lookalikes that must stay
 bar-only, and the context cases the old distance-2 rule couldn't rank.
 */
import Foundation
import Testing

private final class BundleToken {}

private func english() -> (MergedLexicon, CorrectionScorer)? {
    let repo = LexiconRepository(bundle: Bundle(for: BundleToken.self))
    let merged = repo.merged(for: ["en_US"])
    guard !merged.isEmpty else { return nil }
    var scorer = CorrectionScorer()
    scorer.adjacency = KeyAdjacency.forLayout(KeyboardLayout.preset(id: "qwerty"))
    return (merged, scorer)
}

private func verdict(_ typed: String, _ candidate: String, context: String? = nil) throws -> CorrectionScorer.Verdict {
    let (merged, scorer) = try #require(english())
    return scorer.score(
        candidate: candidate, typed: typed,
        logFrequency: merged.logProbability(of: candidate),
        contextLogP: context.flatMap { merged.contextLogProbability(of: candidate, given: $0) }
    ).verdict
}

@Suite struct CorrectionScorerTests {
    @Test func signatureTyposAutocorrect() throws {
        #expect(try verdict("teh", "the") == .autocorrect)
        #expect(try verdict("adn", "and") == .autocorrect)
        #expect(try verdict("recieve", "receive") == .autocorrect)
        #expect(try verdict("thier", "their") == .autocorrect)
    }

    @Test func adjacentKeyTypoBeatsEqualDistanceNonAdjacent() throws {
        // w sits next to e on QWERTY — "hwllo" is a fat-finger, not a new word.
        #expect(try verdict("hwllo", "hello") == .autocorrect)
        let (merged, scorer) = try #require(english())
        let adjacent = scorer.weightedEditCost("hwllo", "hello")
        let nonAdjacent = scorer.weightedEditCost("hzllo", "hello")  // z not next to e
        #expect(adjacent < nonAdjacent)
        _ = merged
    }

    @Test func obscureCandidateStaysBarOnly() throws {
        // Both are edit-plausible for "aboot"; only the common one may commit
        // silently. The old rule treated these identically.
        #expect(try verdict("aboot", "about") == .autocorrect)
        #expect(try verdict("aboot", "abbot") == .suggest)
        #expect(try verdict("helo", "halo") == .suggest)
        #expect(try verdict("helo", "hello") == .autocorrect)
    }

    @Test func farFetchedCandidateRejected() throws {
        #expect(try verdict("xylograph", "xylophone") == .reject)
    }

    @Test func bigramContextRaisesScore() throws {
        let (merged, scorer) = try #require(english())
        func score(_ cand: String, ctx: String?) -> Double {
            scorer.score(candidate: cand, typed: "ther",
                         logFrequency: merged.logProbability(of: cand),
                         contextLogP: ctx.flatMap { merged.contextLogProbability(of: cand, given: $0) }).score
        }
        // "of their" is a strong bigram; context must improve the candidate.
        #expect(score("their", ctx: "of") > score("their", ctx: nil))
    }

    @Test func nextWordModelKnowsObviousFollowers() throws {
        let (merged, _) = try #require(english())
        #expect(merged.nextWords(after: "thank", limit: 3).first == "you")
        #expect(merged.nextWords(after: "going", limit: 3).first == "to")
        #expect(!merged.nextWords(after: "i", limit: 3).isEmpty)
        // Unknown previous word → empty, caller falls back to heuristics.
        #expect(merged.nextWords(after: "zzzzzzz", limit: 3).isEmpty)
    }

    @Test func adjacencyDerivationCoversLayouts() {
        let qwerty = KeyAdjacency.forLayout(KeyboardLayout.preset(id: "qwerty"))
        #expect(qwerty["q"]?.contains("w") == true)
        #expect(qwerty["g"]?.contains("h") == true)
        #expect(qwerty["g"]?.contains("t") == true)   // row above, staggered
        #expect(qwerty["g"]?.contains("v") == true)   // row below
        #expect(qwerty["q"]?.contains("p") != true)
        // Cyrillic layout works through the same generic derivation.
        let ru = KeyAdjacency.forLayout(KeyboardLayout.preset(id: "russian"))
        #expect(ru["й"]?.contains("ц") == true)
    }
}
