/**
 `Lexicon`: zero-copy reader for the compiled `.clex` frequency dictionaries
 bundled under Resources/Lexicons (built by `Tools/GenerateLexicons.swift`,
 `make lexicons` — the format is documented at the top of that script).

 The file is memory-mapped, so a loaded lexicon costs near-zero resident
 memory until pages are touched, and every query here is a point lookup or a
 short contiguous walk — cheap enough to call synchronously on the main actor
 from the hot typing paths (space-press correction, per-touch hitboxes).
 

 Module: prediction · Target: ClinkKit
 Learn: docs/04-prediction.md
 */
import Foundation

/// Immutable view over one language's compiled frequency lexicon. Words are
/// stored lowercased and bytewise-sorted, so any UTF-8 prefix maps to one
/// contiguous index range — prefix completion, membership, frequency lookup
/// and next-letter distributions are all binary search + a bounded walk.
public struct Lexicon: Sendable {
    private let data: Data
    public let wordCount: Int
    /// Letters of this language by descending frequency (drives hitboxes).
    public let alphabet: [Character]

    private let alphabetCount: Int
    private let matrixStart: Int     // (N+1) × N letter-bigram rows
    private let offsetsStart: Int    // (W+1) × u32
    private let freqStart: Int       // W × u8 quantized log10 probability
    private let charCountStart: Int  // W × u8
    private let blobStart: Int

    /// Quantization inverse: q → log10(probability). Matches the generator.
    @inline(__always)
    public static func logProbability(fromQuantized q: UInt8) -> Double {
        Double(q) / 28.0 - 9.0
    }

    // MARK: - Loading

    /// Parse a `.clex` payload. Returns nil on any structural mismatch so a
    /// truncated or foreign file can never crash the keyboard.
    public init?(data: Data) {
        guard data.count >= 16,
              data[0] == UInt8(ascii: "C"), data[1] == UInt8(ascii: "L"),
              data[2] == UInt8(ascii: "E"), data[3] == UInt8(ascii: "X") else { return nil }
        func u32(_ offset: Int) -> Int {
            Int(data[offset]) | Int(data[offset + 1]) << 8
                | Int(data[offset + 2]) << 16 | Int(data[offset + 3]) << 24
        }
        guard u32(4) == 1 else { return nil }
        let w = u32(8), n = u32(12)
        guard w > 0, n > 0, n <= 64 else { return nil }

        var cursor = 16
        var letters: [Character] = []
        letters.reserveCapacity(n)
        guard data.count >= cursor + n * 4 else { return nil }
        for i in 0..<n {
            guard let scalar = Unicode.Scalar(UInt32(u32(cursor + i * 4))) else { return nil }
            letters.append(Character(scalar))
        }
        cursor += n * 4

        let matrix = cursor
        cursor += (n + 1) * n
        let offsets = cursor
        cursor += (w + 1) * 4
        let freqs = cursor
        cursor += w
        let charCounts = cursor
        cursor += w
        let blob = cursor
        guard data.count > blob,
              data.count >= blob + u32(offsets + w * 4) else { return nil }

        self.data = data
        self.wordCount = w
        self.alphabet = letters
        self.alphabetCount = n
        self.matrixStart = matrix
        self.offsetsStart = offsets
        self.freqStart = freqs
        self.charCountStart = charCounts
        self.blobStart = blob
    }

    /// Load `<code>.clex` from a bundle, memory-mapped. `code` is a base
    /// language code ("en"), not a checker identifier — see `LexiconRepository`.
    public static func bundled(_ code: String, in bundle: Bundle = .main) -> Lexicon? {
        let url = bundle.url(forResource: code, withExtension: "clex")
            ?? bundle.url(forResource: code, withExtension: "clex", subdirectory: "Lexicons")
        guard let url,
              let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        return Lexicon(data: data)
    }

    // MARK: - Raw accessors

    @inline(__always)
    private func wordOffset(_ index: Int) -> Int {
        let o = offsetsStart + index * 4
        return Int(data[o]) | Int(data[o + 1]) << 8 | Int(data[o + 2]) << 16 | Int(data[o + 3]) << 24
    }

    /// The word at `index` (indices follow bytewise-sorted order).
    public func word(at index: Int) -> String {
        let start = blobStart + wordOffset(index)
        let end = blobStart + wordOffset(index + 1)
        return String(decoding: data[start..<end], as: UTF8.self)
    }

    /// Quantized log-frequency byte — the cheap ranking key (higher = more common).
    @inline(__always)
    public func quantizedFrequency(at index: Int) -> UInt8 { data[freqStart + index] }

    /// log10 of the word's corpus probability, e.g. "the" ≈ -1.6, rare ≈ -8.
    public func logProbability(at index: Int) -> Double {
        Self.logProbability(fromQuantized: quantizedFrequency(at: index))
    }

    public func characterCount(at index: Int) -> Int { Int(data[charCountStart + index]) }

    /// UTF-8 byte length of the word at `index` — a free length filter for scans.
    @inline(__always)
    public func byteCount(at index: Int) -> Int { wordOffset(index + 1) - wordOffset(index) }

    // MARK: - Lookup

    /// Bytewise compare of the stored word at `index` against `query`,
    /// optionally only the first `query.count` bytes (prefix mode).
    private func compare(_ index: Int, to query: [UInt8], prefixOnly: Bool) -> Int {
        let start = blobStart + wordOffset(index)
        let len = wordOffset(index + 1) - wordOffset(index)
        let common = min(len, query.count)
        for i in 0..<common {
            let b = data[start + i]
            if b != query[i] { return b < query[i] ? -1 : 1 }
        }
        if prefixOnly { return len >= query.count ? 0 : -1 }
        if len == query.count { return 0 }
        return len < query.count ? -1 : 1
    }

    /// First index whose word does not compare less than `query`.
    private func lowerBound(_ query: [UInt8], prefixOnly: Bool) -> Int {
        var lo = 0, hi = wordCount
        while lo < hi {
            let mid = (lo + hi) / 2
            if compare(mid, to: query, prefixOnly: prefixOnly) < 0 { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    /// Index of `word` (lowercased exact match), or nil.
    public func index(of word: String) -> Int? {
        let q = Array(word.lowercased().utf8)
        guard !q.isEmpty else { return nil }
        let i = lowerBound(q, prefixOnly: false)
        return i < wordCount && compare(i, to: q, prefixOnly: false) == 0 ? i : nil
    }

    public func contains(_ word: String) -> Bool { index(of: word) != nil }

    /// log10 probability of `word`, or nil if absent.
    public func logProbability(of word: String) -> Double? {
        index(of: word).map { logProbability(at: $0) }
    }

    /// The contiguous index range of words starting with `prefix` (lowercased).
    /// Empty prefix → the whole table.
    public func prefixRange(_ prefix: String) -> Range<Int> {
        let q = Array(prefix.lowercased().utf8)
        guard !q.isEmpty else { return 0..<wordCount }
        let lo = lowerBound(q, prefixOnly: true)
        var hiQuery = q
        // Successor prefix: bump the last byte (UTF-8 lexicographic successor of
        // the prefix range). 0xFF never appears in UTF-8, so no carry is needed.
        hiQuery[hiQuery.count - 1] += 1
        let hi = lowerBound(hiQuery, prefixOnly: true)
        return lo..<max(lo, hi)
    }

    /// Top completions for `prefix` by frequency, most common first. Skips the
    /// prefix itself when it's a word (the caller shows the literal separately).
    public func topCompletions(prefix: String, limit: Int) -> [String] {
        let range = prefixRange(prefix)
        guard !range.isEmpty, limit > 0 else { return [] }
        let prefixBytes = prefix.lowercased().utf8.count
        // Small partial selection: keep the best `limit` (freq desc) of the range.
        var best: [(index: Int, q: UInt8)] = []
        for i in range where byteCount(at: i) > prefixBytes {
            let q = quantizedFrequency(at: i)
            if best.count < limit {
                best.append((i, q))
                best.sort { $0.q > $1.q }
            } else if q > best[best.count - 1].q {
                best[best.count - 1] = (i, q)
                best.sort { $0.q > $1.q }
            }
        }
        return best.map { word(at: $0.index) }
    }

    /// The `limit` most frequent words (unordered). Drives the swipe decoder's
    /// vocabulary: one counting pass over the frequency bytes finds the cutoff,
    /// a second pass collects the words — O(W), no sort.
    public func topWords(limit: Int) -> [String] {
        guard limit > 0 else { return [] }
        guard limit < wordCount else { return (0..<wordCount).map(word(at:)) }
        var counts = [Int](repeating: 0, count: 256)
        for i in 0..<wordCount { counts[Int(quantizedFrequency(at: i))] += 1 }
        var need = limit
        var cutoff = 255
        while cutoff > 0, need > counts[cutoff] {
            need -= counts[cutoff]
            cutoff -= 1
        }
        var atCutoff = need
        var out: [String] = []
        out.reserveCapacity(limit)
        for i in 0..<wordCount {
            let q = Int(quantizedFrequency(at: i))
            if q > cutoff {
                out.append(word(at: i))
            } else if q == cutoff, atCutoff > 0 {
                out.append(word(at: i))
                atCutoff -= 1
            }
        }
        return out
    }

    /// Probability distribution of the next letter after `prefix`, derived from
    /// the actual completion set: the weight of each continuation letter is the
    /// summed probability of the words continuing with it. Empty/unknown prefix
    /// → nil (callers fall back to `letterDistribution(after:)`).
    public func nextLetterDistribution(prefix: String) -> [Character: Double]? {
        let range = prefixRange(prefix)
        guard !range.isEmpty else { return nil }
        let prefixBytes = prefix.lowercased().utf8.count
        var weights: [Character: Double] = [:]
        for i in range where byteCount(at: i) > prefixBytes {
            let start = blobStart + wordOffset(i) + prefixBytes
            let end = blobStart + wordOffset(i + 1)
            // Decode the single continuation character after the prefix.
            guard let next = String(decoding: data[start..<min(end, start + 4)], as: UTF8.self).first
            else { continue }
            weights[next, default: 0] += pow(10, logProbability(at: i))
        }
        guard !weights.isEmpty else { return nil }
        let total = weights.values.reduce(0, +)
        return weights.mapValues { $0 / total }
    }

    /// Letter-level distribution from the compiled matrix: `nil` letter → the
    /// word-initial letter distribution; otherwise the distribution of letters
    /// following `letter` in this language. Returns nil for letters outside the
    /// language's alphabet.
    public func letterDistribution(after letter: Character?) -> [Character: Double]? {
        let row: Int
        if let letter {
            guard let i = alphabet.firstIndex(of: Character(letter.lowercased())) else { return nil }
            row = i + 1
        } else {
            row = 0
        }
        let base = matrixStart + row * alphabetCount
        var weights: [Character: Double] = [:]
        var total = 0.0
        for (i, ch) in alphabet.enumerated() {
            let v = Double(data[base + i])
            if v > 0 { weights[ch] = v; total += v }
        }
        guard total > 0 else { return nil }
        return weights.mapValues { $0 / total }
    }
}
