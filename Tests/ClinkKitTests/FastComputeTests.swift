/**
 The lexicon-only fast pass that paints the suggestion bar instantly (no
 `UITextChecker`) before the quiet-gated checker enrichment lands. Proves it
 returns frequency-ranked completions + next-word predictions on its own.
 */
import Foundation
import Testing

@MainActor
@Suite struct FastComputeTests {
    private func engine() -> SuggestionEngine {
        let e = SuggestionEngine()
        e.setLanguages(["en_US"])
        return e
    }

    @Test func fastPassCompletesFromLexicon() {
        let r = engine().fastCompute(partial: "hel", previousWord: nil, sentenceStart: false)
        // Literal leads (no correction in the fast pass), then frequency-ranked
        // lexicon completions — the everyday words the checker is too shallow for.
        #expect(r.predictions.first == "hel")
        #expect(r.predictions.contains("hello"))
        #expect(r.correction == nil)
    }

    @Test func fastPassPredictsNextWord() {
        // No partial → next-word prediction from the bigram model.
        let r = engine().fastCompute(partial: "", previousWord: "thank", sentenceStart: false)
        #expect(r.predictions.first == "you")
    }

    @Test func fastPassSentenceStartOffersOpeners() {
        let r = engine().fastCompute(partial: "", previousWord: nil, sentenceStart: true)
        #expect(!r.predictions.isEmpty)   // sentence starters, never blank
    }

    @Test func fastPassNeverDuplicatesLiteral() {
        let r = engine().fastCompute(partial: "the", previousWord: nil, sentenceStart: false)
        #expect(r.predictions.filter { $0.caseInsensitiveCompare("the") == .orderedSame }.count == 1)
    }
}
