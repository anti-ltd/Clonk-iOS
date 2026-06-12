/**
 `NgramModel`: zero-copy reader for the compiled `.cngm` word-bigram models
 bundled next to the `.clex` lexicons (built by `Tools/GenerateLexicons.swift`;
 format documented there). Word IDs are indices into the same language's
 lexicon word table — the two files are a matched pair.

 Memory-mapped like `Lexicon`; a follower lookup is one binary search plus a
 short walk of a contiguous, already-best-first block.
 

 Module: prediction · Target: ClinkKit
 Learn: docs/04-prediction.md
 */
import Foundation

public struct NgramModel: Sendable {
    private let data: Data
    public let pairCount: Int
    private let prevStart: Int   // P × u32, sorted ascending
    private let nextStart: Int   // P × u32, block-aligned with prev
    private let qStart: Int      // P × u8 quantized conditional log10 P(next|prev)

    /// Quantization inverse: q → log10 P(next|prev). Matches the generator.
    @inline(__always)
    public static func logProbability(fromQuantized q: UInt8) -> Double {
        Double(q) / 42.0 - 6.0
    }

    public init?(data: Data) {
        guard data.count >= 12,
              data[0] == UInt8(ascii: "C"), data[1] == UInt8(ascii: "N"),
              data[2] == UInt8(ascii: "G"), data[3] == UInt8(ascii: "M") else { return nil }
        func u32(_ offset: Int) -> Int {
            Int(data[offset]) | Int(data[offset + 1]) << 8
                | Int(data[offset + 2]) << 16 | Int(data[offset + 3]) << 24
        }
        guard u32(4) == 1 else { return nil }
        let p = u32(8)
        guard p > 0, data.count >= 12 + p * 9 else { return nil }
        self.data = data
        self.pairCount = p
        self.prevStart = 12
        self.nextStart = 12 + p * 4
        self.qStart = 12 + p * 8
    }

    public static func bundled(_ code: String, in bundle: Bundle = .main) -> NgramModel? {
        let url = bundle.url(forResource: code, withExtension: "cngm")
            ?? bundle.url(forResource: code, withExtension: "cngm", subdirectory: "Lexicons")
        guard let url,
              let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        return NgramModel(data: data)
    }

    @inline(__always)
    private func prevID(at i: Int) -> Int {
        let o = prevStart + i * 4
        return Int(data[o]) | Int(data[o + 1]) << 8 | Int(data[o + 2]) << 16 | Int(data[o + 3]) << 24
    }

    @inline(__always)
    private func nextID(at i: Int) -> Int {
        let o = nextStart + i * 4
        return Int(data[o]) | Int(data[o + 1]) << 8 | Int(data[o + 2]) << 16 | Int(data[o + 3]) << 24
    }

    /// First pair index whose prevID is ≥ `id` (the start of `id`'s block).
    private func blockStart(of id: Int) -> Int {
        var lo = 0, hi = pairCount
        while lo < hi {
            let mid = (lo + hi) / 2
            if prevID(at: mid) < id { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    /// The most likely followers of `prevID`, best first (the block is stored
    /// pre-sorted by count), as (lexicon word ID, log10 conditional probability).
    public func followers(of prevID: Int, limit: Int) -> [(wordID: Int, logP: Double)] {
        var i = blockStart(of: prevID)
        var out: [(Int, Double)] = []
        while i < pairCount, out.count < limit, self.prevID(at: i) == prevID {
            out.append((nextID(at: i), Self.logProbability(fromQuantized: data[qStart + i])))
            i += 1
        }
        return out
    }

    /// log10 P(next|prev), or nil when the pair isn't in the model. Blocks are
    /// sorted by count (not ID), so this walks the block — capped, since the
    /// fattest blocks ("the" in English) are exactly where a long walk could hurt.
    public func logProbability(next: Int, given prevID: Int) -> Double? {
        var i = blockStart(of: prevID)
        var steps = 0
        while i < pairCount, steps < 512, self.prevID(at: i) == prevID {
            if nextID(at: i) == next {
                return Self.logProbability(fromQuantized: data[qStart + i])
            }
            i += 1
            steps += 1
        }
        return nil
    }
}
