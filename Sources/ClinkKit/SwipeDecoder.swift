/**
 Glide/swipe-typing decoder. Turns a continuous finger trace across the letter
 keys into ranked word candidates.

 The model is the classic template match: each candidate word defines an *ideal*
 path — the polyline through its letters' key centres. We resample both the
 gesture and every candidate's ideal path to a fixed number of arc-length-uniform
 points, then score by mean point-to-point distance (lower is better). A first /
 last letter anchor prunes the dictionary hard before the (more expensive) path
 compare, since a swipe reliably begins on its first letter and ends on its last.

 Pure geometry + the supplied vocabulary — no `UITextChecker`, no I/O — so it's
 cheap enough to run synchronously on lift. `SuggestionEngine.swipeCandidates`
 feeds it the language's common-word set as the vocabulary.
 */
import CoreGraphics

public struct SwipeDecoder {
    /// Arc-length samples used for both the gesture and each template. Enough to
    /// capture a word's shape without making the per-candidate compare costly.
    static let sampleCount = 48

    public init() {}

    /// Rank `vocabulary` words by how well each one's ideal key path matches the
    /// traced `path`. `keyCenters` maps each lowercased letter to its key's centre
    /// (in the same coordinate space as `path`). `bias` words (e.g. likely
    /// next-words for context) get a small score discount. Returns up to `limit`
    /// words, best first; falls back to the literally-traced key sequence when no
    /// dictionary word fits.
    public func decode(path: [CGPoint],
                       keyCenters: [Character: CGPoint],
                       vocabulary: [String],
                       bias: Set<String> = [],
                       limit: Int = 4) -> [String] {
        guard path.count >= 2, !keyCenters.isEmpty,
              let start = path.first, let end = path.last else {
            return fallback(path: path, keyCenters: keyCenters)
        }
        let scale = fieldDiagonal(keyCenters)
        guard scale > 0 else { return [] }

        guard let firstKey = nearestLetter(to: start, centers: keyCenters),
              let lastKey  = nearestLetter(to: end,   centers: keyCenters) else {
            return []
        }

        let gesture = resample(path, count: Self.sampleCount)

        var scored: [(word: String, score: Double)] = []
        for raw in vocabulary {
            let word = raw.lowercased()
            guard word.count >= 2, let wf = word.first, let wl = word.last,
                  wf == firstKey, wl == lastKey else { continue }
            // Build the ideal polyline; bail if any letter isn't on this plane.
            var ideal: [CGPoint] = []
            ideal.reserveCapacity(word.count)
            var ok = true
            for ch in word {
                guard let c = keyCenters[ch] else { ok = false; break }
                ideal.append(c)
            }
            guard ok else { continue }
            let template = resample(ideal, count: Self.sampleCount)
            var d = meanDistance(gesture, template) / scale
            if bias.contains(word) { d *= 0.85 }   // nudge context-likely words up
            scored.append((raw, d))
        }
        guard !scored.isEmpty else { return fallback(path: path, keyCenters: keyCenters) }

        scored.sort { $0.score < $1.score }
        var seen = Set<String>()
        var out: [String] = []
        for s in scored where seen.insert(s.word.lowercased()).inserted {
            out.append(s.word)
            if out.count >= limit { break }
        }
        return out
    }

    // MARK: - Geometry helpers

    /// Resample a polyline to `count` points spaced evenly along its arc length.
    /// A zero-length path (all points coincident) returns the single point
    /// repeated, so a tap-like trace still compares cleanly.
    func resample(_ points: [CGPoint], count: Int) -> [CGPoint] {
        guard count > 1 else { return points }
        guard points.count > 1 else {
            return Array(repeating: points.first ?? .zero, count: count)
        }
        let total = pathLength(points)
        guard total > 0 else { return Array(repeating: points[0], count: count) }
        let step = total / CGFloat(count - 1)

        var out: [CGPoint] = [points[0]]
        var i = 1
        var prev = points[0]
        var accumulated: CGFloat = 0
        while out.count < count && i < points.count {
            let next = points[i]
            let seg = dist(prev, next)
            if seg <= 0 { i += 1; prev = next; continue }
            if accumulated + seg >= step {
                let t = (step - accumulated) / seg
                let p = CGPoint(x: prev.x + (next.x - prev.x) * t,
                                y: prev.y + (next.y - prev.y) * t)
                out.append(p)
                prev = p            // continue measuring from the inserted point
                accumulated = 0
            } else {
                accumulated += seg
                prev = next
                i += 1
            }
        }
        // Floating-point drift can leave us one short; pad with the last point.
        while out.count < count { out.append(points[points.count - 1]) }
        return out
    }

    private func pathLength(_ points: [CGPoint]) -> CGFloat {
        var len: CGFloat = 0
        for i in 1..<points.count { len += dist(points[i - 1], points[i]) }
        return len
    }

    private func meanDistance(_ a: [CGPoint], _ b: [CGPoint]) -> Double {
        let n = min(a.count, b.count)
        guard n > 0 else { return .greatestFiniteMagnitude }
        var sum: CGFloat = 0
        for i in 0..<n { sum += dist(a[i], b[i]) }
        return Double(sum) / Double(n)
    }

    /// Diagonal of the key field's bounding box — the natural scale for
    /// normalising distances so the score is layout-size-independent.
    private func fieldDiagonal(_ centers: [Character: CGPoint]) -> Double {
        guard !centers.isEmpty else { return 0 }
        var minX = CGFloat.greatestFiniteMagnitude, minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude, maxY = -CGFloat.greatestFiniteMagnitude
        for c in centers.values {
            minX = min(minX, c.x); minY = min(minY, c.y)
            maxX = max(maxX, c.x); maxY = max(maxY, c.y)
        }
        return Double(hypot(maxX - minX, maxY - minY))
    }

    private func nearestLetter(to point: CGPoint, centers: [Character: CGPoint]) -> Character? {
        var best: Character?
        var bestD = CGFloat.greatestFiniteMagnitude
        for (ch, c) in centers {
            let d = dist(point, c)
            if d < bestD { bestD = d; best = ch }
        }
        return best
    }

    /// Last-resort decode: map the trace to the sequence of letter keys it crossed,
    /// collapsing consecutive repeats — so the user gets *something* when no
    /// dictionary word matches the path.
    private func fallback(path: [CGPoint], keyCenters: [Character: CGPoint]) -> [String] {
        guard !path.isEmpty, !keyCenters.isEmpty else { return [] }
        var chars: [Character] = []
        for p in path {
            guard let ch = nearestLetter(to: p, centers: keyCenters) else { continue }
            if chars.last != ch { chars.append(ch) }
        }
        let word = String(chars)
        return word.isEmpty ? [] : [word]
    }

    private func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}
