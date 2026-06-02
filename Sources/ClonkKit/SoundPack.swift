import Foundation

/// A "clonk" key-sound pack. Each pack maps to a set of short audio samples
/// bundled in the keyboard extension under `Sounds/<file>`. The keyboard plays
/// them on key press — but ONLY when the user has granted Full Access (iOS
/// blocks an extension's audio session otherwise). Without Full Access, Clonk
/// silently falls back to the standard system input click.
///
/// v0.1 ships the plumbing and pack definitions; curated samples drop into
/// `Resources/Sounds/` over time. A pack whose files aren't present yet just
/// no-ops at playback, so the app always builds and runs.
public struct SoundPack: Identifiable, Codable, Equatable, Sendable, Hashable {
    public var id: String
    public var name: String
    /// Short blurb for the picker.
    public var blurb: String
    /// Base filenames (without extension) for the press samples. The player
    /// rotates through them so repeated keys don't sound robotic. Empty means
    /// "system click only".
    public var sampleNames: [String]
    /// File extension of the bundled samples (e.g. "wav", "m4a").
    public var fileExtension: String

    public init(id: String, name: String, blurb: String, sampleNames: [String], fileExtension: String = "wav") {
        self.id = id; self.name = name; self.blurb = blurb
        self.sampleNames = sampleNames; self.fileExtension = fileExtension
    }

    /// True when this pack relies on bundled audio (and therefore Full Access).
    public var needsFullAccess: Bool { !sampleNames.isEmpty }
}

public extension SoundPack {
    static let presets: [SoundPack] = [
        SoundPack(
            id: "system", name: "System Click",
            blurb: "The standard iOS click. Works without Full Access.",
            sampleNames: []
        ),
        SoundPack(
            id: "tactile", name: "Tactile Brown",
            blurb: "Deep, rounded thock of a lubed brown switch.",
            sampleNames: ["tactile-1", "tactile-2", "tactile-3"]
        ),
        SoundPack(
            id: "clicky", name: "Clicky Blue",
            blurb: "Sharp, springy click with a crisp tail.",
            sampleNames: ["clicky-1", "clicky-2", "clicky-3"]
        ),
        SoundPack(
            id: "typewriter", name: "Typewriter",
            blurb: "Mechanical hammer strike and carriage ring.",
            sampleNames: ["typewriter-1", "typewriter-2"]
        ),
        SoundPack(
            id: "marble", name: "Marble",
            blurb: "Soft, glassy tap. Understated and quiet.",
            sampleNames: ["marble-1", "marble-2", "marble-3"]
        ),
    ]

    static let `default`: SoundPack = presets[0]

    static func preset(id: String) -> SoundPack {
        presets.first { $0.id == id } ?? .default
    }
}
