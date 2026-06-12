# Changelog

All notable changes to Clink are recorded here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.0]

### Added
- **Swipe / glide typing** — trace a continuous path across the letter keys and
  it decodes into ranked words. The decoder scores each candidate by symmetric
  key-proximity: a *forward* term (every letter visited in order) so an `h→e→y`
  flick doesn't become "happy", plus a *reverse coverage* term (every traced
  point explained) so a short word can't win by matching only the trace's
  endpoints. First/last-letter anchoring prunes the dictionary before the
  compare; word frequency breaks ties toward the commoner word. (`SwipeDecoder`,
  `KeyTouchRouter`)
- **Next-word prediction & completion** — predictions and completions are
  ranked from bundled n-gram lexicons (unigrams + bigrams across en/fr/es/de/
  it/pt/ru, built by `make lexicons` from open frequency corpora). The `.clex`
  files are memory-mapped, so a loaded language costs near-zero resident memory
  until queried — cheap enough to run synchronously on the typing path.
  (`Lexicon`, `Tools/GenerateLexicons.swift`)
- **On-device learning** — opt-in adaptive store that remembers words you
  actually commit, boosts ones you accept from the bar, and permanently
  suppresses corrections you reject, so the keyboard stops fighting your
  vocabulary. One JSON file in the App Group; nothing leaves the device, gated
  by the `learningEnabled` setting. (`UserAdaptation`)
- **Apple Intelligence backend** — optional on-device AI via the
  `FoundationModels` framework (iOS 26+, A17 Pro / M-series), used for the
  auto-shown inline suggestion picker. Inference runs in an Apple system process
  so it works inside the extension without counting against its memory cap. Off
  by default (`aiEnabled`), with full availability probing for older OS /
  ineligible hardware / Apple Intelligence disabled. (`AIEngine`)
- **Custom keys** — build your own keys in *Layout → Custom*: insert text (with
  optional Gboard-style long-press alternates) or act as a function key (cursor
  nudge, plane switch, emoji, backspace), placed beside the space bar or in
  whole custom rows above/below the letters. Cap shows a literal string or an SF
  Symbol. (`CustomKey`, `CustomKeysView`)
- **Grid clipboard** — the clipboard panel can render as a grid in addition to
  the list, with per-row swipe actions (pin / delete). (`ClipboardPanel`,
  `SwipeRow`)
- **Motion engine** — a dedicated animation layer (`Motion`, `MotionProfile`,
  `MotionSequence`, `MotionDiagnostics`) backing key-press and panel animations,
  with tunable profiles and a diagnostics path.
- **Key previews & key faces** — per-key preview rendering and customizable key
  faces, surfaced in the container's *Keys* settings.
- **Suggestion-bar font** setting, a richer interactive in-app keyboard preview,
  and a suggestion-bar padding control.
- **Auto keyboard height** — height auto-adjusts for the default icon set, with
  an option to hide the suggestion bar entirely.
- New app icon.
- **Multi-language typing** — pick more than one language in *Localization* and
  type them at once (e.g. Spanish **and** English in the same field). Offline
  completions, next-word predictions, and swipe-typing vocabulary are merged
  across every active language, and a word is only auto-corrected when it's
  misspelled in *all* of them — so `como` is left alone while English autocorrect
  still fixes `teh` → `the`. The active set is a flat multi-select (at least one
  always on); the physical key layout is now an independent setting rather than
  being force-switched to match the language. All on-device via `UITextChecker`,
  no network. (`KeyboardSettings.keyboardLanguages`, `SuggestionEngine.setLanguages`)
- **Revert auto-correct on delete** — pressing delete immediately after an
  auto-correction restores the word you actually typed (type `Dawg`, space
  corrects it to `Done`, delete brings back `Dawg`), and that word is left
  un-corrected on the next space. Mirrors the native keyboard. New toggle in both
  *Suggestions* and *Automation*, on by default.

### Changed
- Settings that don't apply to the current configuration are now hidden rather
  than shown disabled, in both the container app and the in-extension controls.

### Fixed
- **Function-key flash** — fixed a flash on the function keys during plane
  switches, alongside App Store compliance for ITMS-90737 / ITMS-90788.
- Settings schema is backward-compatible across upgrades — older saved configs
  decode without loss (covered by `SettingsBackCompatTests`).
- `make device` now installs onto an iPhone paired over Wi-Fi, not just one
  cabled in. The device-detection step only matched the `connected` state, but a
  wireless pairing reports `available (paired)`, so it falsely reported "No
  paired iPhone found"; it now accepts both states.

### Security
- Stopped tracking `.wrangler/cache/wrangler-account.json` (contained a Cloudflare
  account id and email) and added `.wrangler/` to `.gitignore`.

## [1.0.0] — 2026-06-04

First production release. A fully customizable, offline-first, privacy-first iOS
keyboard — two targets (container app + `ClinkKeyboard` extension) sharing one
`ClinkKit` so the in-app preview is the exact SwiftUI view the extension renders.

### Added
- **Themes** — 30 built-in presets across dark, light, and six **Liquid Glass**
  variants (iOS 26; `.ultraThinMaterial` fallback below 26). Match-system mode
  auto-switches between a chosen light and dark theme.
- **Custom theme builder** — solid or Liquid Glass material, sans/serif font
  design, per-color pickers, a multi-stop gradient editor (linear / radial), and
  photo backgrounds. Duplicate any preset as a starting point, and export / import
  themes as `.clink` files.
- **Layouts & keys** — four layouts (QWERTY, AZERTY, QWERTZ, Dvorak); optional
  number row and home-row inset; adjustable key height / width / spacing /
  roundness; standard-balloon or Liquid Glass key popups with tunable position and
  size; a liquid key-press bloom + warp animation with independently tunable
  springs.
- **Offline text assistance** — autocomplete and auto-correction via
  `UITextChecker` with a Damerau-Levenshtein ranker (no network, no telemetry);
  smart punctuation (curly quotes, double-space → period, contraction
  apostrophes); auto-capitalize and auto-return-to-letters after symbols.
- **Emoji keyboard** — full Unicode 16.0 set as an internal mode (instant swap,
  no system keyboard transition), name-based search, skin-tone picking with
  per-emoji tone memory, and a recents tab.
- **Clipboard history** — FIFO list with pinning, shown as an inline bar or a
  full-keyboard overlay (requires Full Access to read the pasteboard).
- **Quick notepad** — a scratchpad buffer or a saved-notes archive you can drop
  text into and re-insert anywhere.
- **Panel switcher** — open clipboard / notepad / emoji panels from the
  suggestion-bar icon or by sliding up on the 123 key; cards or cycling-picker
  style.
- **Sound & haptics** — per-keypress sound packs (the standard system click works
  without Full Access) with a volume slider; per-keypress haptics (requires Full
  Access).
- **Spacebar cursor** — slide to move the cursor, in three modes (slide /
  trackpad / combined), with configurable activation delay, scroll sensitivity,
  and line stride.
- **Container app** — onboarding and a step-by-step enable flow, all settings
  across a four-tab root (Style / Typing / Feel / Setup), a live interactive
  keyboard preview, and whole-config export / import as `.clinkconfig`.
- Device install pipeline (`make device`) and a DEBUG-only marketing-capture
  routing layer (`AppStage`, the [AppStage](../appstage) pipeline) that never
  ships in Release.

### Security & privacy
- **Private by default** — the keyboard works completely without Full Access
  (you get the standard system click) and never transmits anything; there is no
  network code on the typing path.
- All text assistance runs on-device through `UITextChecker`; nothing typed,
  completed, or corrected leaves the device.
- **Full Access is optional** and only gates the two features iOS restricts to it
  — per-keypress haptics and clipboard reads — and nothing else.
- Settings cross the app ↔ extension boundary as a JSON file in the App Group
  (`group.ltd.anti.clink`) via `SharedStore`, not `UserDefaults(suiteName:)`
  (which `cfprefsd` can serve stale across processes).
- No analytics, no crash reporters, no accounts, no identifiers.
