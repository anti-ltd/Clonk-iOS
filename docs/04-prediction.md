# Prediction & suggestions

## What it is

Offline autocomplete, autocorrect, and emoji-name suggestions. No network, no
telemetry. Built on `UITextChecker` for spell data, custom lexicons for ranking,
and a keyboard-aware edit-distance scorer for correction confidence.

The suggestion bar (`SuggestionBar`) displays output from `KeyboardLiveState`,
which the extension updates on a debounced, quiet-gated schedule so checker
work never lands mid key-press animation.

---

## Where it sits

```
KeyboardViewController
    ├── recentTail mirror (local document buffer)
    ├── scheduleSuggestionUpdate (debounce)
    ├── quietGatedCompute (wait for touch-free window)
    └── SuggestionEngine
            ├── UITextChecker (completions, guesses, spell)
            ├── LexiconRepository (.clex frequency dicts)
            ├── NgramModel (.cngm bigram models)
            ├── LanguageHeuristics (contractions, next-word)
            ├── CorrectionScorer (adjacent-key typos)
            ├── UserAdaptation (opt-in learning)
            └── SwipeDecoder candidates
                ↓
        KeyboardLiveState → SuggestionBar
```

---

## Files

| File | Role |
|---|---|
| `SuggestionEngine.swift` | Main `@MainActor` engine — fan-out across languages, caching, swipe vocab prebuild |
| `SuggestionBar.swift` | Autocomplete strip — correction chip, predictions, emoji suggestions, panel button |
| `KeyboardLiveState.swift` | Holds live `suggestions`, `autocorrection`, `emojiSuggestions` |
| `PredictionCore.swift` | Background actor for lexicon-heavy prebuild work |
| `Lexicon.swift` | Zero-copy mmap reader for `.clex` frequency dictionaries |
| `LexiconRepository.swift` | Process-wide lexicon cache; merged multi-language view |
| `NgramModel.swift` | Zero-copy mmap reader for `.cngm` word-bigram models |
| `CorrectionScorer.swift` | Edit-distance confidence — silent fix vs bar suggestion |
| `LanguageHeuristics.swift` | Per-language tables UITextChecker doesn't cover |
| `UserAdaptation.swift` | Opt-in on-device learning — word weights, rejected corrections |
| `SwipeDecoder.swift` | Glide trace → ranked words (shared with touch module) |
| `SwipeLexicon.swift` | Bundled English frequency list for swipe fallback |
| `SmartPunctuation.swift` | Applied on insert, not in engine — curly quotes, etc. |
| `AIEngine.swift` | Apple Intelligence / FoundationModels facade (iOS 26+); lazy session |

App settings:

| File | Role |
|---|---|
| `TypingView.swift` | Smart text master toggles |
| `SuggestionsView.swift` | Bar + autocorrect settings |
| `AdaptationView.swift` | Learning on/off, reset |
| `LocalizationView.swift` | Language picker for `UITextChecker` |
| `ArtificialIntelligenceView.swift` | Apple Intelligence opt-in |
| `PerformanceView.swift` | Suggestion compute budget tuning |

Generated resources (not Swift):

| Resource | Built by |
|---|---|
| `Resources/Lexicons/*.clex` | `make lexicons` (`Tools/GenerateLexicons.swift`) |
| `Resources/Lexicons/*.cngm` | same |

---

## How it works

### Why it's @MainActor

iOS 26 annotates `UITextChecker` as `@MainActor`. The engine can't move to a
background queue — a dual-engine attempt didn't compile under Swift 6.

Compensation: the extension doesn't run checker work on every keystroke.
Instead:

1. `scheduleSuggestionUpdate` coalesces — each new key cancels the pending work item.
2. `quietGatedCompute` waits until `suggestionQuietWindow` (0.45s) after last touch.
3. Checker stall lands in idle time, not during press/release springs.

### Multi-language fan-out

`setLanguages([...])` resolves each ID to one the device actually has (checker
silently returns nothing for unavailable languages). With multiple languages:

- Completions merged across all active languages
- Word is "misspelled" only if misspelled in *every* active language
- `LanguageHeuristics` and `LexiconRepository` merge similarly

### Lexicons (.clex)

Memory-mapped, near-zero resident cost until touched. Words sorted bytewise;
prefix completion is binary search + bounded walk. Also provides:

- Letter frequency alphabet (drives `AdaptiveHitbox`)
- Letter-bigram matrix (same)
- Word frequency for ranking

Format documented at top of `Tools/GenerateLexicons.swift`.

### Correction tiers

`CorrectionScorer` uses layout adjacency (`KeyAdjacency.forLayout`) so
"hwllo" → "hello" scores higher than random substitutions.

Confidence determines:

- **Silent autocorrect** on space/return (high confidence)
- **Bar suggestion** with "keep" option (lower confidence)
- **No correction** (too far)

User tapping "keep" sets `rejectedCorrection` — suppressed until next word.

### Autocorrect revert

Native keyboard behaviour: backspace right after autocorrect restores original
word. `KeyboardViewController.pendingAutocorrectRevert` tracks this.

### Local text mirror

`documentContextBeforeInput` is a cross-process read that lags one runloop
tick. Extension keeps `recentTail` (last 32 chars) mirrored locally:

- Seeded from proxy on focus / external edit
- Updated synchronously on our own inserts
- `isApplyingEdit` prevents change callbacks from invalidating during our work

Space-press autocorrect reads the mirror synchronously — no async proxy round-trip.

### UserAdaptation

Opt-in (`learningEnabled`). Tracks:

- Words you type often (boost in ranking)
- Corrections you rejected (suppress)

Persisted separately; attached/detached via `SuggestionEngine.setAdaptation`.

### AIEngine

Placeholder for iOS 26+ Foundation Models integration. Lazy `LanguageModelSession`.
Currently gated behind settings + availability checks. Not on the hot typing path.

---

## Gotchas

- **Never run checker synchronously on every key-down.** That's the stutter the
  debounce + quiet gate exist to prevent.

- **Language resolution matters.** Passing `"en"` when device only has `"en_US"`
  kills the entire suggestion bar silently. `resolveLanguage` handles this.

- **Lexicon optional.** No bundled `.clex` for a language → checker-only behaviour.
  Everything degrades gracefully.

- **Swipe vocab cache invalidates** on language, layout, or adaptation change.
  Prebuild runs via `PredictionCore` actor.

- **Emoji suggestions** come from `EmojiData` name search, not the checker —
  separate path in engine, same bar slot.

---

## Read order

1. `SuggestionEngine.swift` — top doc comment, then `setLanguages`, then compute entry points
2. `KeyboardViewController.swift` — search `scheduleSuggestionUpdate`, `quietGatedCompute`, `recentTail`
3. `SuggestionBar.swift` — how live state renders
4. `Lexicon.swift` — if you need to understand `.clex` format
5. `CorrectionScorer.swift` — if you're tuning autocorrect behaviour

---

## See also

- [03-touch-and-input](03-touch-and-input.md) — swipe decoder, adaptive hitboxes
- [05-emoji](05-emoji.md) — emoji suggestions in the bar
- [10-extension-host](10-extension-host.md) — mirror + debounce wiring
