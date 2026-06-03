# Sound packs

Curated "clink" key-sound samples live here, one short file per strike. The
keyboard extension (`SoundPlayer`) loads them by the `sampleNames` declared in
`Sources/ClinkKit/SoundPack.swift` and rotates through a pack's samples so
repeated keys don't sound robotic.

Naming: `<pack-id>-<n>.<ext>` — e.g. `tactile-1.wav`, `tactile-2.wav`. Keep
them short (< 150 ms), mono, normalized. WAV or M4A.

When you add real samples, wire this folder into the `ClinkKeyboard` target's
resources in `project.yml`:

```yaml
  ClinkKeyboard:
    sources:
      - Sources/ClinkKeyboard
      - Sources/ClinkKit
      - path: Resources/Sounds
        type: folder        # blue folder → preserves the Sounds/ subdirectory
```

Until then the pipeline is fully wired but silent for custom packs — playback
falls back to the standard system click, so the keyboard always feels live.

Custom-sample playback (any pack but **System Click**) requires the user to
grant **Full Access** — iOS silences an extension's audio session otherwise.
That's why Full Access is presented as an optional, sounds-only opt-in.
