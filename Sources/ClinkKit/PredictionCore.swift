/**
 `PredictionCore`: the engine's background worker. `UITextChecker` is pinned
 to the main actor (iOS 26 SDK), but everything built on the mmapped lexicons
 is not — so the scans that would otherwise stall a keystroke land here.

 Today it owns the swipe-vocabulary build (decoding ~20k words per active
 language out of the `.clex` blobs); `SuggestionEngine` kicks a prebuild off
 the main actor on every language/learning change and falls back to building
 synchronously on first swipe if the prebuild hasn't landed yet.
 

 Module: prediction · Target: ClinkKit
 Learn: docs/04-prediction.md
 */
import Foundation

/// Off-main worker for lexicon scans that would stall the main actor if run
/// inline (today: the swipe-decoder vocabulary prebuild).
public actor PredictionCore {
    public init() {}

    /// Build the swipe decoder's vocabulary off-main. `extras` carries the
    /// main-actor-only contributions (heuristic tables, learned words).
    public func swipeVocabulary(lexicon: MergedLexicon, perLanguage: Int,
                                extras: [String]) -> [String] {
        Self.makeSwipeVocabulary(lexicon: lexicon, perLanguage: perLanguage, extras: extras)
    }

    /// The shared build, callable synchronously from any isolation (the
    /// engine's first-swipe fallback) or via the actor (prebuild).
    public static func makeSwipeVocabulary(lexicon: MergedLexicon, perLanguage: Int,
                                           extras: [String]) -> [String] {
        var set = Set<String>()
        for lex in lexicon.lexicons {
            set.formUnion(lex.topWords(limit: perLanguage))
        }
        for w in extras { set.insert(w.lowercased()) }
        return Array(set)
    }
}
