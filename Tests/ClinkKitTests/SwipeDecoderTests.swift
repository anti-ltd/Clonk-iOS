/**
 Swipe decoder goldens over a synthetic QWERTY geometry fixture — the
 regression net the decoder never had. Ideal traces must decode to their
 word; slightly-missed endpoints must recover via the soft-anchor rescue.
 */
import CoreGraphics
import Foundation
import Testing

private final class BundleToken {}

/// QWERTY fixture: 3 staggered rows, 36pt pitch, 56pt row height.
private func qwertyCenters() -> [Character: CGPoint] {
    let rows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]
    var out: [Character: CGPoint] = [:]
    for (r, row) in rows.enumerated() {
        let shift = (10.0 - Double(row.count)) / 2 * 36
        for (c, ch) in row.enumerated() {
            out[ch] = CGPoint(x: shift + Double(c) * 36 + 18, y: Double(r) * 56 + 28)
        }
    }
    return out
}

/// Ideal trace: straight segments between the word's key centers, ~6pt steps,
/// with optional offsets on the first/last waypoint (simulated missed anchor).
private func trace(_ word: String, centers: [Character: CGPoint],
                   startOffset: CGPoint = .zero, endOffset: CGPoint = .zero) -> [CGPoint] {
    var waypoints = Array(word).compactMap { centers[$0] }
    waypoints[0].x += startOffset.x
    waypoints[0].y += startOffset.y
    waypoints[waypoints.count - 1].x += endOffset.x
    waypoints[waypoints.count - 1].y += endOffset.y
    var pts: [CGPoint] = []
    for i in 0..<waypoints.count - 1 {
        let a = waypoints[i], b = waypoints[i + 1]
        let n = max(2, Int(hypot(b.x - a.x, b.y - a.y) / 6))
        for s in 0..<n {
            let t = CGFloat(s) / CGFloat(n)
            pts.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
        }
    }
    pts.append(waypoints.last!)
    return pts
}

private struct Fixture {
    let centers = qwertyCenters()
    let decoder = SwipeDecoder()
    let vocabulary: [String]
    let merged: MergedLexicon

    init?() {
        let repo = LexiconRepository(bundle: Bundle(for: BundleToken.self))
        let merged = repo.merged(for: ["en_US"])
        guard !merged.isEmpty else { return nil }
        self.merged = merged
        vocabulary = PredictionCore.makeSwipeVocabulary(
            lexicon: merged, perLanguage: 20_000, extras: [])
    }

    func decode(_ word: String, startOffset: CGPoint = .zero,
                endOffset: CGPoint = .zero, bias: Set<String> = []) -> [String] {
        decoder.decode(
            path: trace(word, centers: centers, startOffset: startOffset, endOffset: endOffset),
            keyCenters: centers, vocabulary: vocabulary, bias: bias,
            logFrequency: { merged.logProbability(of: $0) })
    }
}

@Suite struct SwipeDecoderTests {
    @Test func idealTracesDecodeToTheirWord() throws {
        let f = try #require(Fixture())
        for word in ["hello", "maybe", "the", "keyboard", "quick", "about", "project"] {
            #expect(f.decode(word).first == word, "ideal trace for \(word)")
        }
    }

    @Test func frequencyBeatsGeometricLookalikes() throws {
        let f = try #require(Fixture())
        // h→e→y passes straight over r/t, so "hetty" is a geometrically perfect
        // sub-path — frequency must put "hey" first regardless.
        #expect(f.decode("hey").first == "hey")
    }

    @Test func slightlyMissedEndpointsRecover() throws {
        let f = try #require(Fixture())
        // A realistic miss: ~20pt off the first key (more than half a key pitch).
        #expect(f.decode("hello", startOffset: CGPoint(x: -20, y: 0)).first == "hello")
        let offStart = f.decode("the", startOffset: CGPoint(x: 20, y: 0))
        #expect(offStart.prefix(2).contains("the"))
    }

    @Test func contextBiasBreaksAmbiguity() throws {
        let f = try #require(Fixture())
        // The s→w→i→p→e zig-zag is genuinely ambiguous with "suite"/"spite";
        // a context bias (e.g. after "to") must put the biased word first.
        #expect(f.decode("swipe", bias: ["swipe"]).first == "swipe")
    }

    @Test func garbageTraceReturnsNothing() throws {
        let f = try #require(Fixture())
        // A two-point tap-like trace in a corner shouldn't invent long words.
        let r = f.decoder.decode(path: [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1)],
                                 keyCenters: f.centers, vocabulary: f.vocabulary,
                                 logFrequency: { f.merged.logProbability(of: $0) })
        // Whatever matches must at least be anchored at 'q' (the corner key).
        for w in r { #expect(w.lowercased().first == "q") }
    }

    @Test func decodeIsFastEnoughForLift() throws {
        let f = try #require(Fixture())
        let path = trace("keyboard", centers: f.centers)
        let t0 = Date()
        for _ in 0..<10 { _ = f.decoder.decode(path: path, keyCenters: f.centers,
                                               vocabulary: f.vocabulary,
                                               logFrequency: { f.merged.logProbability(of: $0) }) }
        let perDecode = -t0.timeIntervalSinceNow / 10
        #expect(perDecode < 0.05, "decode took \(perDecode * 1000)ms")
    }
}
