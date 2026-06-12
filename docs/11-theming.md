# Clink Theme Guide

How to add built-in (preset) themes and convert `.clink` user exports into presets.

---

## Theme anatomy

All themes live in `Sources/ClinkKit/Theme.swift`. The `Theme` struct is `Codable` and travels between the container app and keyboard extension through a shared App Group JSON file.

| Field | Type | Default | Purpose |
|---|---|---|---|
| `id` | `String` | — | Stable identifier. **Never change once shipped** — users' saved `themeID` references it. |
| `name` | `String` | — | Display name in the picker. |
| `isDark` | `Bool` | — | Drives `UIInputView` appearance and the light/dark preset filters. |
| `material` | `KeyMaterial` | `.solid` | `.solid` or `.liquidGlass`. |
| `background` | `RGBA` | — | Keyboard backdrop (solid colour fallback). |
| `keyFill` | `RGBA` | — | Letter/number key face. On glass themes, used as a translucent tint. |
| `keyText` | `RGBA` | — | Glyph colour on character keys. |
| `specialKeyFill` | `RGBA` | — | Function-key face (shift, delete, return, mode switch). |
| `specialKeyText` | `RGBA` | — | Glyph colour on function keys. |
| `accent` | `RGBA` | — | Pressed-state highlight and popup background. |
| `backgroundGradient` | `ThemeGradient?` | `nil` | Optional gradient behind keys, overrides solid `background`. |
| `backgroundImageID` | `String?` | `nil` | App Group photo ID. Leave `nil` for presets — photo files don't ship in the bundle. |
| `keyGradient` | `ThemeGradient?` | `nil` | Glass only: gradient masked to each key shape. |
| `keyImageID` | `String?` | `nil` | Glass only: photo masked to each key shape. Leave `nil` for presets. |
| `glassVariant` | `GlassVariant` | `.regular` | Glass only: `.regular` (frosty) or `.clear` (thin, more refractive). |
| `glassInteractive` | `Bool` | `false` | Glass only: warp lens on every key press, not just shift. |
| `glassTintStrength` | `Double` | `1.0` | Glass only: 0–1 multiplier on key-fill tint opacity. |
| `keyFontDesign` | `ThemeFontDesign` | `.default` | `.default` / `.rounded` / `.serif` / `.monospaced` |
| `keyFontWeight` | `ThemeFontWeight` | `.regular` | `.thin` → `.black` |

### RGBA

Two initialisers:

```swift
RGBA(hex: 0xD4614A)          // opaque hex
RGBA(hex: 0x1C1C1E, a: 0.28) // hex + alpha (0–1, for glass)
RGBA(0.83, 0.70, 1.0, 0.94)  // raw sRGB components
```

---

## Adding a preset theme

Presets are declared in the `Theme.presets` array inside `Sources/ClinkKit/Theme.swift`. The array is ordered — first entry is the app default.

### 1. Pick a unique ID

Use a short lowercase slug. **IDs already taken:**
`graphite`, `snow`, `paper`, `mechanical`, `synthwave`, `forest`, `midnight`, `carbon`, `dracula`, `nord`, `solarized-dark`, `ocean`, `ember`, `crimson`, `matrix`, `royal`, `sakura`, `mint`, `lavender`, `solarized-light`, `bubblegum`, `latte`, `coral`, `cinder`, `liquid-dark`, `liquid-light`, `liquid-mint`, `liquid-ember`, `dobble`, `snobble`

### 2. Write the Theme initialiser

Add it to the `presets` array in `Theme.swift`. Solid example:

```swift
Theme(
    id: "slate",
    name: "Slate",
    background: RGBA(hex: 0x1E2A38),
    keyFill:    RGBA(hex: 0x2E3D52),
    keyText:    RGBA(hex: 0xE8EDF4),
    specialKeyFill: RGBA(hex: 0x18222E),
    specialKeyText: RGBA(hex: 0xA8B8CC),
    accent:     RGBA(hex: 0x4A9EFF),
    isDark:     true
),
```

Liquid Glass example:

```swift
Theme(
    id: "liquid-slate",
    name: "Liquid Slate",
    background:  RGBA(hex: 0x1E2A38, a: 0.25),
    keyFill:     RGBA(hex: 0xFFFFFF, a: 0.10),
    keyText:     RGBA(hex: 0xE8EDF4),
    specialKeyFill: RGBA(hex: 0xFFFFFF, a: 0.06),
    specialKeyText: RGBA(hex: 0xC0CEDE),
    accent:      RGBA(hex: 0x4A9EFF),
    isDark:      true,
    material:    .liquidGlass,
    glassVariant: .regular,
    glassTintStrength: 0.8
),
```

With custom font:

```swift
Theme(
    id: "typewriter",
    name: "Typewriter",
    background: RGBA(hex: 0xF0EBE0),
    keyFill:    RGBA(hex: 0xFAF6EE),
    keyText:    RGBA(hex: 0x2A2318),
    specialKeyFill: RGBA(hex: 0xD8D0C0),
    specialKeyText: RGBA(hex: 0x2A2318),
    accent:     RGBA(hex: 0x8B4513),
    isDark:     false,
    keyFontDesign: .serif,
    keyFontWeight: .light
),
```

### 3. Position in the array

- Solid themes go before the `// Liquid Glass` comment.
- Light/dark ordering doesn't matter — `lightPresets` / `darkPresets` are filtered at runtime by `isDark`.
- Keep paired light+dark themes adjacent for readability.

### 4. No other changes needed

`allThemes`, `lightPresets`, `darkPresets`, and `theme(withID:)` all derive from `presets` automatically. The keyboard extension reads from the shared JSON, so it picks up presets without any extension-side changes.

---

## Converting a `.clink` file into a preset

A `.clink` file is a JSON-encoded `Theme`. Export any custom theme from **Theme → long-press → Export…** then decode it to extract the values.

### Step 1 — read the JSON

```sh
cat MyTheme.clink | python3 -m json.tool
```

Typical output:

```json
{
  "id": "custom-a1b2c3d4",
  "name": "My Theme",
  "isDark": false,
  "material": "solid",
  "background": { "r": 0.976, "g": 0.961, "b": 0.937, "a": 1.0 },
  "keyFill":    { "r": 1.0,   "g": 1.0,   "b": 1.0,   "a": 1.0 },
  "keyText":    { "r": 0.165, "g": 0.122, "b": 0.102, "a": 1.0 },
  "specialKeyFill": { "r": 0.929, "g": 0.894, "b": 0.847, "a": 1.0 },
  "specialKeyText": { "r": 0.165, "g": 0.122, "b": 0.102, "a": 1.0 },
  "accent":     { "r": 0.831, "g": 0.380, "b": 0.290, "a": 1.0 },
  "backgroundGradient": null,
  "keyFontDesign": "rounded",
  "keyFontWeight": "medium"
}
```

### Step 2 — convert components to hex (optional)

`r * 255` rounds to an integer, then to hex. For the accent above:
`0.831 × 255 ≈ 212 = 0xD4`, `0.380 × 255 ≈ 97 = 0x61`, `0.290 × 255 ≈ 74 = 0x4A` → `0xD4614A`.

Use raw components directly when precision matters or when alpha ≠ 1:

```swift
RGBA(0.831, 0.380, 0.290, 1.0)
```

### Step 3 — write the preset

```swift
Theme(
    id:   "coral",           // replace the custom-XXXXXXXX id with a stable slug
    name: "Coral",           // rename as desired
    background:     RGBA(hex: 0xF9F5EF),
    keyFill:        RGBA(hex: 0xFFFFFF),
    keyText:        RGBA(hex: 0x2A1F1A),
    specialKeyFill: RGBA(hex: 0xEDE4D8),
    specialKeyText: RGBA(hex: 0x2A1F1A),
    accent:         RGBA(hex: 0xD4614A),
    isDark:         false,
    keyFontDesign:  .rounded,
    keyFontWeight:  .medium
),
```

### Step 4 — handle gradients (if present)

If `backgroundGradient` is non-null in the JSON:

```json
"backgroundGradient": {
  "type": "linear",
  "rotation": 180,
  "stops": [
    { "color": { "r": 0.12, "g": 0.08, "b": 0.20, "a": 1 }, "position": 0 },
    { "color": { "r": 0.24, "g": 0.16, "b": 0.40, "a": 1 }, "position": 1 }
  ]
}
```

Translate to:

```swift
backgroundGradient: ThemeGradient(
    type: .linear,
    rotation: 180,
    stops: [
        GradientStop(color: RGBA(0.12, 0.08, 0.20, 1), position: 0),
        GradientStop(color: RGBA(0.24, 0.16, 0.40, 1), position: 1),
    ]
),
```

`backgroundImageID` and `keyImageID` reference files in the App Group — they cannot be bundled. Omit them (or set to `nil`) when converting to a preset; the theme will fall back to `backgroundGradient` then `background`.

### Step 5 — handle Liquid Glass

If `"material": "liquidGlass"`, include:

```swift
material:          .liquidGlass,
glassVariant:      .regular,           // or .clear
glassTintStrength: 0.85,               // from JSON, or tune manually
glassInteractive:  false,              // from JSON
```

Keep `keyFill` and `specialKeyFill` alpha well below 1 (typically 0.06–0.32) — opaque fills kill the glass effect.

---

## Field reference for font design and weight

```
ThemeFontDesign   .default   SF Pro (system default)
                  .rounded   SF Pro Rounded
                  .serif     New York
                  .monospaced SF Mono

ThemeFontWeight   .thin .ultraLight .light .regular
                  .medium .semibold .bold .heavy .black
```

Font design difference is most visible in **lowercase** letterforms. Uppercase keys look nearly identical between `.default` and `.rounded`.

---

## Checklist

- [ ] ID is unique and lowercase-slug
- [ ] `isDark` is correct (affects status bar tint and light/dark preset filters)
- [ ] `accent` is readable against both `keyFill` (pressed state) and `background` (popup)
- [ ] Glass themes: `keyFill` / `specialKeyFill` alpha < 0.4
- [ ] No `backgroundImageID` or `keyImageID` (images don't ship in the bundle)
- [ ] Build succeeds (`xcodebuild -scheme Clink -destination 'generic/platform=iOS' build`)
