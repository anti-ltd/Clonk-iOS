# File index

Every Swift source file under `Sources/`, grouped by directory. One line each —
for the full story on a module, see the linked doc.

---

## ClinkKeyboard/

| File | Purpose |
|---|---|
| `KeyboardViewController.swift` | Extension principal class — hosts canvas, proxy, suggestions, sound → [10-extension-host](10-extension-host.md) |

---

## Clink/

| File | Purpose |
|---|---|
| `ClinkApp.swift` | `@main` entry; URL import; SHOWCASE/AppStage routing |
| `AppModel.swift` | App-wide state; settings persistence; theme/config import |
| `AppStage.swift` | DEBUG `--appstage` marketing screenshot routing |
| `MotionHUD.swift` | DEBUG FPS overlay (`--motion-hud`) |
| `MotionMetrics.swift` | DEBUG MetricKit hitch subscriber |

### Clink/UI/

| File | Purpose |
|---|---|
| `RootView.swift` | Collapsible sidebar shell + destination routing → [09-app-ui](09-app-ui.md) |
| `ThemedSheet.swift` | Themed bottom sheet with drag-to-expand |
| `LogoMark.swift` | Vector Clink logo |
| `TuningPresets.swift` | Preset chips and tuned section helpers |
| `EnableFlowView.swift` | Keyboard enable + Full Access onboarding |
| `KeyboardPreview.swift` | Live preview widget + layout helpers |
| `ThemeEditorView.swift` | Theme grid, export/import → [THEMING.md](../THEMING.md) |
| `ThemeBuilderView.swift` | Custom theme editor + gradient editor |
| `AnimationView.swift` | Key/space/popup spring tuning |
| `PopupsView.swift` | Key popup settings |
| `KeysView.swift` | Key geometry settings |
| `OverlaysView.swift` | Debug overlay toggles |
| `LayoutView.swift` | Layout + custom keys tabs |
| `LayoutPickerView.swift` | Row toggles with preview |
| `CustomKeysView.swift` | Custom key builder |
| `GesturesView.swift` | Swipe typing + backspace repeat |
| `HitboxView.swift` | Hitbox tuning |
| `ResponseView.swift` | Hold/slide timing |
| `CursorView.swift` | Space-bar cursor mode |
| `TypingView.swift` | Smart text settings |
| `SuggestionsView.swift` | Suggestion bar settings |
| `AutomationView.swift` | Auto-cap, punctuation, returns |
| `AdaptationView.swift` | On-device learning UI |
| `LocalizationView.swift` | Checker language picker |
| `ArtificialIntelligenceView.swift` | Apple Intelligence opt-in |
| `ClipboardHistoryView.swift` | Clipboard settings + history |
| `NotepadView.swift` | Notepad settings + notes |
| `CalculatorSettingsView.swift` | Calculator panel toggle |
| `EmojiSettingsView.swift` | Emoji preferences |
| `SoundsView.swift` | Sound settings |
| `SoundPickerView.swift` | Sound + haptics picker |
| `HapticsView.swift` | Haptic settings |
| `PerformanceView.swift` | Compute budget tuning |
| `BackupView.swift` | Config export/import |
| `AdvancedSettingsView.swift` | Legacy tuning tab layout |
| `ShowcaseView.swift` | SHOWCASE typing simulator |
| `StagedHeroView.swift` | AppStage hero shot |

### Clink/UI/Panels/

| File | Purpose |
|---|---|
| `PanelsView.swift` | Custom panel list → [07-custom-panels](07-custom-panels.md) |
| `PanelEditorView.swift` | Panel script editor + preview |

### Clink/UI/Extensions/

| File | Purpose |
|---|---|
| `ExtensionsView.swift` | Custom action list → [EXTENSIONS-SDK.md](../EXTENSIONS-SDK.md) |
| `ExtensionEditorView.swift` | Action script editor + run console |

---

## ClinkKit/

### Settings & storage

| File | Purpose |
|---|---|
| `KeyboardSettings.swift` | Single Codable config blob → [01-settings-and-storage](01-settings-and-storage.md) |
| `SharedStore.swift` | App Group file I/O + Darwin notify |
| `FeatureFlags.swift` | Launch-arg debug flags |

### Theme

| File | Purpose |
|---|---|
| `Theme.swift` | Core Theme struct → [THEMING.md](../THEMING.md) |
| `ThemeTypes.swift` | Gradient, material, glass, font enums |
| `RGBA.swift` | Codable color bridging SwiftUI/UIKit |
| `ThemeBackgroundStore.swift` | App Group photo JPEG storage |
| `ThemePresets.swift` | Built-in preset catalog |
| `Theme+Bubblegum.swift` | Preset: bright pink |
| `Theme+Carbon.swift` | Preset: pure black |
| `Theme+Cinder.swift` | Preset: dark serif coral |
| `Theme+Coral.swift` | Preset: light serif coral |
| `Theme+Crimson.swift` | Preset: burgundy |
| `Theme+Dracula.swift` | Preset: Dracula palette |
| `Theme+Ember.swift` | Preset: charred red |
| `Theme+Forest.swift` | Preset: deep green |
| `Theme+Graphite.swift` | Preset: near-black slate (default dark) |
| `Theme+Latte.swift` | Preset: tawny cream |
| `Theme+Lavender.swift` | Preset: lilac |
| `Theme+LiquidDark.swift` | Preset: dark Liquid Glass |
| `Theme+LiquidEmber.swift` | Preset: Liquid Glass ember |
| `Theme+LiquidLight.swift` | Preset: light Liquid Glass (default) |
| `Theme+LiquidMint.swift` | Preset: Liquid Glass mint |
| `Theme+Matrix.swift` | Preset: terminal green |
| `Theme+Mechanical.swift` | Preset: vintage keycap |
| `Theme+Midnight.swift` | Preset: navy-black |
| `Theme+Mint.swift` | Preset: solid mint |
| `Theme+Nord.swift` | Preset: Nord arctic |
| `Theme+Ocean.swift` | Preset: deep teal |
| `Theme+Paper.swift` | Preset: warm off-white |
| `Theme+Royal.swift` | Preset: dark warm gold |
| `Theme+Sakura.swift` | Preset: cherry blossom |
| `Theme+Snow.swift` | Preset: cool light grey (default light) |
| `Theme+SolarizedDark.swift` | Preset: Solarized Dark |
| `Theme+SolarizedLight.swift` | Preset: Solarized Light |
| `Theme+Synthwave.swift` | Preset: neon 80s |

### Keyboard core

| File | Purpose |
|---|---|
| `KeyboardCanvas.swift` | Full keyboard view → [02-keyboard-core](02-keyboard-core.md) |
| `KeyboardController.swift` | Plane/shift/emoji session state |
| `KeyboardLayout.swift` | QWERTY/AZERTY/QWERTZ/Dvorak layouts |
| `KeyboardLiveState.swift` | Live suggestions + ActionPanel enum |
| `KeyView.swift` | Individual key rendering |
| `KeyGlyphLayer.swift` | Unified glyph draw pass |
| `KeySpec.swift` | Key identity and action |
| `KeyPopup.swift` | Press popup balloon |
| `CustomKey.swift` | User-defined keys |
| `InputViewHeight.swift` | Extension height constraint tame |
| `SmartPunctuation.swift` | Curly quotes, double-space period |

### Touch & input

| File | Purpose |
|---|---|
| `KeyTouchRouter.swift` | Multitouch UIKit router → [03-touch-and-input](03-touch-and-input.md) |
| `AdaptiveHitbox.swift` | Next-letter hit target sizing |
| `AccentMap.swift` | Long-press diacritic tables |
| `AccentPicker.swift` | Accent variant bar UI |
| `SwipeDecoder.swift` | Glide trace → words |
| `SwipeLexicon.swift` | Bundled swipe word list |
| `TrackpadPanel.swift` | Space-bar trackpad overlay |
| `SwipeRow.swift` | Swipe-to-reveal list row (app history views) |

### Prediction

| File | Purpose |
|---|---|
| `SuggestionEngine.swift` | Offline autocomplete engine → [04-prediction](04-prediction.md) |
| `SuggestionBar.swift` | Autocomplete strip UI |
| `PredictionCore.swift` | Background lexicon prebuild actor |
| `Lexicon.swift` | `.clex` mmap reader |
| `LexiconRepository.swift` | Process-wide lexicon cache |
| `NgramModel.swift` | `.cngm` bigram reader |
| `CorrectionScorer.swift` | Edit-distance confidence model |
| `LanguageHeuristics.swift` | Per-language checker supplements |
| `UserAdaptation.swift` | Opt-in on-device learning |
| `AIEngine.swift` | Apple Intelligence facade (iOS 26+) |

### Emoji

| File | Purpose |
|---|---|
| `EmojiCanvas.swift` | Full emoji keyboard → [05-emoji](05-emoji.md) |
| `EmojiCell.swift` | Grid cell + long-press tone |
| `EmojiData.swift` | Category model + name search |
| `EmojiData.generated.swift` | Generated Unicode set (`make emoji`) |
| `EmojiSkinTone.swift` | Fitzpatrick tone enum |
| `SkinTonePicker.swift` | Tone picker overlay |
| `EmojiTabTapSurface.swift` | UIKit category tab taps |
| `EmojiBarTouchSurface.swift` | UIKit suggestion bar taps |
| `EmojiDeleteTile.swift` | Hold-to-repeat delete |

### Built-in panels

| File | Purpose |
|---|---|
| `ActionPanelButton.swift` | Suggestion-bar panel icon → [EXTENDING.md](../EXTENDING.md) |
| `ClipboardPanel.swift` | Full clipboard overlay |
| `ClipboardBar.swift` | Inline clipboard strip |
| `ClipboardManager.swift` | FIFO history persistence |
| `ClipboardEntry.swift` | One history item |
| `NotepadBrowsePanel.swift` | Saved notes overlay |
| `NotepadBar.swift` | Inline notepad compose strip |
| `NotepadManager.swift` | Scratch + notes archive |
| `NotepadNote.swift` | One saved note |
| `CalculatorPanel.swift` | Arithmetic overlay |
| `PanelSwitcherPanel.swift` | Card-style panel picker |
| `PanelLeadingIcon.swift` | Panel header back icon |

### Motion

| File | Purpose |
|---|---|
| `Motion/Motion.swift` | Named animation tokens → [MOTION.md](../MOTION.md) |
| `Motion/MotionProfile.swift` | Reduce Motion / Low Power resolver |
| `Motion/MotionSequence.swift` | Multi-phase animation helper |
| `Motion/MotionDiagnostics.swift` | Instruments signposts |

### Sound

| File | Purpose |
|---|---|
| `SoundPlayer.swift` | Key click + haptics → [06-sound](06-sound.md) |
| `SoundPack.swift` | Named sample pack definitions |

### Extensions SDK

| File | Purpose |
|---|---|
| `Extensions/ClinkExtension.swift` | Custom action model |
| `Extensions/ExtensionManager.swift` | Action store + Darwin notify |
| `Extensions/ExtensionsPanel.swift` | Keyboard action list overlay |

### Custom panels SDK

| File | Purpose |
|---|---|
| `Panels/ClinkPanel.swift` | Panel definition model |
| `Panels/PanelManager.swift` | Panel store + Darwin notify |
| `Panels/PanelRuntime.swift` | MVU script bridge → [07-custom-panels](07-custom-panels.md) |
| `Panels/CustomPanelView.swift` | Native UI tree renderer |

### PyMini

| File | Purpose |
|---|---|
| `PyMini/PyEngine.swift` | Public run/validate facade → [08-pymini](08-pymini.md) |
| `PyMini/PyLexer.swift` | Tokenizer |
| `PyMini/PyParser.swift` | Parser |
| `PyMini/PyAST.swift` | AST node types |
| `PyMini/PyInterpreter.swift` | Evaluator |
| `PyMini/PyValue.swift` | Runtime values |
| `PyMini/PyProgram.swift` | Warm parsed module cache |

---

**Total: 153 Swift files**

Generated resources (not listed above):

| Path | Built by |
|---|---|
| `Resources/Lexicons/*.clex`, `*.cngm` | `make lexicons` |
| `Resources/Sounds/` | bundled samples |
| `Tools/emoji-test.txt` | input to `make emoji` |
