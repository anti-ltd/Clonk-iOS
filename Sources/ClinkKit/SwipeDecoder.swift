/**
 Glide/swipe-typing decoder. Turns a continuous finger trace across the letter
 keys into ranked word candidates.

 The model is symmetric key-proximity. We resample the gesture to an arc-length-
 uniform point cloud, then score each candidate by two averaged terms:
   • forward — every letter visited, in order: each letter's distance to the
     closest gesture sample at or after the previous letter's match. Proximity to
     *every* letter (not just overall shape) stops an `h→e→y` flick decoding as
     "happy" — the trace never nears `p`, so happy's `p` term is large.
   • reverse (coverage) — every traced point explained: each gesture sample's
     distance to the nearest of the word's keys. Without it a tiny word wins by
     matching just the trace's endpoints ("me" for "maybe", "ll" for "lol"); the
     reverse term charges for the long swept middle such a word leaves uncovered.
 A first / last letter anchor prunes the dictionary hard before that compare, since
 a swipe reliably begins on its first letter and ends on its last; word frequency
 breaks otherwise-equal paths toward the commoner word.

 Pure geometry + the supplied vocabulary — no `UITextChecker`, no I/O — so it's
 cheap enough to run synchronously on lift. `SuggestionEngine.swipeCandidates`
 feeds it the language's common-word set as the vocabulary.
 */
import CoreGraphics

public struct SwipeDecoder {
    /// Arc-length samples the gesture is resampled to before scoring. Dense enough
    /// that every candidate letter key has a nearby sample to match against, without
    /// making the per-candidate compare costly.
    static let sampleCount = 96

    public init() {}

    /// Rank `vocabulary` words by how well each one's ideal key path matches the
    /// traced `path`. `keyCenters` maps each lowercased letter to its key's centre
    /// (in the same coordinate space as `path`). `bias` words (e.g. likely
    /// next-words for context) get a small score discount; `frequencyRank` (word →
    /// 0-based rank, most-common first) breaks otherwise-equal paths toward the more
    /// common word — so "hey" beats equally-traced "hew". Returns up to `limit`
    /// words, best first; returns an empty array when no dictionary word fits (the
    /// host then inserts nothing rather than committing a garbage key trace).
    public func decode(path: [CGPoint],
                       keyCenters: [Character: CGPoint],
                       vocabulary: [String],
                       bias: Set<String> = [],
                       frequencyRank: [String: Int] = [:],
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
            // Gather the word's letter-key centres; bail if any isn't on this plane.
            var centers: [CGPoint] = []
            centers.reserveCapacity(word.count)
            var ok = true
            for ch in word {
                guard let c = keyCenters[ch] else { ok = false; break }
                centers.append(c)
            }
            guard ok else { continue }
            // Symmetric cost: forward = every letter visited (in order); reverse =
            // every traced point explained by some letter. Forward alone lets a tiny
            // word win by matching just the trace's endpoints and ignoring its middle
            // ("me" for a "maybe" swipe, "ll" for "lol"); reverse penalises the long
            // stretch of path such a word leaves uncovered. Averaged so neither term
            // dominates by word length.
            let forward = orderedProximity(gesture, centers)
            let reverse = coverageCost(gesture, centers)
            var d = (forward + reverse) / 2 / scale
            if bias.contains(word) { d *= 0.85 }   // nudge context-likely words up
            // Frequency tie-break: scale the cost down for commoner words, by at
            // most ~6%. Small on purpose — it only decides genuine ties, never
            // overrides a clearly closer path (wrong words score far worse).
            if let r = frequencyRank[word] {
                d *= 1.0 - 0.06 / (1.0 + Double(r) / 600.0)
            }
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

    /// Mean cost that the gesture passes *near each of the word's letter keys, in
    /// order*. For each letter we take the closest gesture sample at or after the
    /// one matched to the previous letter (a monotonic march down the trace), so a
    /// candidate only scores low when the finger genuinely visited every one of its
    /// keys in sequence. This is what rejects "happy" for an `h→e→y` flick: the
    /// trace never nears `p`, so `p`'s term is large. The `gesture` is pre-resampled
    /// to a uniform arc-length density, so every key has a sample close by to match.
    ///
    /// `upper` reserves one remaining sample per still-unmatched later letter, so a
    /// greedy early match can't consume the tail and strand the word's final keys.
    private func orderedProximity(_ gesture: [CGPoint], _ centers: [CGPoint]) -> Double {
        guard !centers.isEmpty, !gesture.isEmpty else { return .greatestFiniteMagnitude }
        var gi = 0
        var sum: CGFloat = 0
        for (k, c) in centers.enumerated() {
            let remaining = centers.count - 1 - k
            let upper = min(gesture.count, max(gi + 1, gesture.count - remaining))
            var bestD = CGFloat.greatestFiniteMagnitude
            var bestJ = gi
            for j in gi..<upper {
                let d = dist(gesture[j], c)
                if d < bestD { bestD = d; bestJ = j }
            }
            sum += bestD
            gi = bestJ
        }
        return Double(sum) / Double(centers.count)
    }

    /// Mean distance from each gesture sample to the *nearest* of the word's letter
    /// keys — how well the word's keys cover the whole traced path. Large when a
    /// short word ignores a long swept middle (the path wanders far from its two or
    /// three keys), which is what stops "me" beating "maybe".
    private func coverageCost(_ gesture: [CGPoint], _ centers: [CGPoint]) -> Double {
        guard !centers.isEmpty, !gesture.isEmpty else { return .greatestFiniteMagnitude }
        var sum: CGFloat = 0
        for p in gesture {
            var bestD = CGFloat.greatestFiniteMagnitude
            for c in centers {
                let d = dist(p, c)
                if d < bestD { bestD = d }
            }
            sum += bestD
        }
        return Double(sum) / Double(gesture.count)
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

    /// No-match result: empty. A swipe that matches no dictionary word inserts
    /// nothing — never the raw sequence of keys the finger crossed, which is
    /// gibberish ("maybe" mis-traced → "mnbvfdsasdrtygvbgfre"), not a word. The
    /// host simply leaves the text untouched, like the system swipe keyboard.
    private func fallback(path: [CGPoint], keyCenters: [Character: CGPoint]) -> [String] {
        []
    }

    private func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}
