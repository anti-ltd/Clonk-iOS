#!/usr/bin/env swift
import Foundation

// Generates Resources/Lexicons/<lang>.clex (frequency lexicon) and
// <lang>.cngm (word-bigram model) for every supported keyboard language,
// from the vendored word lists under Tools/wordlists/.
//
//   swift Tools/GenerateLexicons.swift   (or `make lexicons`)
//
// Sources (see Tools/wordlists/README.md for download commands + licenses):
//   - <xx>_50k.txt        hermitdave/FrequencyWords (OpenSubtitles 2018, CC-BY-SA 4.0)
//   - <xx>_sentences.tsv  Tatoeba per-language sentence exports (CC-BY 2.0 FR)
//
// ── CLEX1 layout (little-endian) ────────────────────────────────────────────
//   "CLEX"                magic
//   u32 version = 1
//   u32 wordCount W
//   u32 alphabetCount N   (≤ 48)
//   N × u32               alphabet scalars, descending letter frequency
//   (N+1) × N u8          letter-bigram rows, each scaled so its max = 255:
//                         row 0 = word-INITIAL letter distribution,
//                         row r = distribution of the letter after alphabet[r-1]
//   (W+1) × u32           word byte offsets into the blob (last = blob length)
//   W × u8                quantized log10 word probability:
//                         q = clamp(round((log10(p) + 9) * 28), 0, 255)
//   W × u8                character count (clamped to 255)
//   blob                  UTF-8 lowercased words, sorted BYTEWISE (memcmp order,
//                         so any byte prefix maps to one contiguous index range)
//
// ── CNGM1 layout (little-endian) ────────────────────────────────────────────
//   "CNGM"                magic
//   u32 version = 1
//   u32 pairCount P
//   P × u32               prevID   (index into the language's .clex word table)
//   P × u32               nextID
//   P × u8                quantized conditional log10 P(next|prev):
//                         q = clamp(round((log10(p) + 6) * 42), 0, 255)
//   Pairs sorted by (prevID asc, raw count desc) so one binary search yields a
//   follower block already in best-first order.

let scriptURL = URL(fileURLWithPath: #filePath)
let toolsDir = scriptURL.deletingLastPathComponent()
let repoRoot = toolsDir.deletingLastPathComponent()
let wordlists = toolsDir.appendingPathComponent("wordlists")
let outDir = repoRoot.appendingPathComponent("Resources/Lexicons")

enum BigramSource {
    case tatoeba(String)     // Tatoeba "id\tlang\tsentence" TSV
}

struct LangConfig {
    let code: String         // resource name, e.g. "en"
    let unigrams: String     // file in wordlists/
    let wordCap: Int
    let bigrams: BigramSource?
    let pairCap: Int
}

let configs: [LangConfig] = [
    .init(code: "en", unigrams: "en_50k.txt", wordCap: 50_000,
          bigrams: .tatoeba("en_sentences.tsv"), pairCap: 100_000),
    .init(code: "fr", unigrams: "fr_50k.txt", wordCap: 30_000,
          bigrams: .tatoeba("fr_sentences.tsv"), pairCap: 40_000),
    .init(code: "es", unigrams: "es_50k.txt", wordCap: 30_000,
          bigrams: .tatoeba("es_sentences.tsv"), pairCap: 40_000),
    .init(code: "de", unigrams: "de_50k.txt", wordCap: 30_000,
          bigrams: .tatoeba("de_sentences.tsv"), pairCap: 40_000),
    .init(code: "it", unigrams: "it_50k.txt", wordCap: 30_000,
          bigrams: .tatoeba("it_sentences.tsv"), pairCap: 40_000),
    .init(code: "pt", unigrams: "pt_50k.txt", wordCap: 30_000,
          bigrams: .tatoeba("pt_sentences.tsv"), pairCap: 40_000),
    .init(code: "ru", unigrams: "ru_50k.txt", wordCap: 30_000,
          bigrams: .tatoeba("ru_sentences.tsv"), pairCap: 40_000),
]

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write(Data("error: \(msg)\n".utf8))
    exit(1)
}

// A keyboard word: letters only, with internal apostrophes/hyphens allowed
// ("c'est", "auto-stop"). Anything with digits or other symbols is tokenizer
// noise from the subtitle corpus, not something the keyboard should predict.
func isKeyboardWord(_ w: String) -> Bool {
    guard let first = w.unicodeScalars.first, let last = w.unicodeScalars.last else { return false }
    let letters = CharacterSet.letters
    guard letters.contains(first), letters.contains(last) else { return false }
    for s in w.unicodeScalars {
        if letters.contains(s) { continue }
        if s == "'" || s == "\u{2019}" || s == "-" { continue }
        return false
    }
    return true
}

// Normalise curly apostrophe to straight for storage; the engine compares
// typed text the same way.
func normalise(_ w: String) -> String {
    w.lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
        .precomposedStringWithCanonicalMapping
}

func quantizeLog(_ p: Double, floorExp: Double, scale: Double) -> UInt8 {
    guard p > 0 else { return 0 }
    let q = (log10(p) - floorExp) * scale
    return UInt8(max(0, min(255, q.rounded())))
}

func appendU32(_ v: UInt32, to data: inout Data) {
    withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) }
}

try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

for cfg in configs {
    let t0 = Date()

    // ── Unigrams ────────────────────────────────────────────────────────────
    let uniURL = wordlists.appendingPathComponent(cfg.unigrams)
    guard let uniText = try? String(contentsOf: uniURL, encoding: .utf8) else {
        fail("cannot read \(uniURL.path) — see Tools/wordlists/README.md")
    }
    var counts: [String: Double] = [:]
    counts.reserveCapacity(cfg.wordCap + 1024)
    for line in uniText.split(separator: "\n") {
        let parts = line.split(separator: " ", maxSplits: 1)
        guard parts.count == 2, let c = Double(parts[1]) else { continue }
        let w = normalise(String(parts[0]))
        guard isKeyboardWord(w), w.count <= 32 else { continue }
        counts[w, default: 0] += c
        if counts.count >= cfg.wordCap { break }
    }
    let total = counts.values.reduce(0, +)
    guard total > 0 else { fail("\(cfg.code): empty unigram list") }

    // Bytewise sort (memcmp order) so byte prefixes are contiguous ranges.
    let entries: [(word: String, bytes: [UInt8], p: Double)] = counts
        .map { (word: $0.key, bytes: Array($0.key.utf8), p: $0.value / total) }
        .sorted { a, b in
            for i in 0..<min(a.bytes.count, b.bytes.count) {
                if a.bytes[i] != b.bytes[i] { return a.bytes[i] < b.bytes[i] }
            }
            return a.bytes.count < b.bytes.count
        }
    var idOf: [String: Int] = [:]
    idOf.reserveCapacity(entries.count)
    for (i, e) in entries.enumerated() { idOf[e.word] = i }

    // ── Letter alphabet + letter-bigram matrix ─────────────────────────────
    var letterFreq: [Character: Double] = [:]
    for e in entries {
        for ch in e.word where ch.isLetter { letterFreq[ch, default: 0] += e.p }
    }
    let alphabet = letterFreq.sorted { $0.value > $1.value }.prefix(48).map(\.key)
    var letterIndex: [Character: Int] = [:]
    for (i, ch) in alphabet.enumerated() { letterIndex[ch] = i }
    let n = alphabet.count

    // rows[0] = word-initial distribution; rows[1+i] = after alphabet[i].
    var rows = Array(repeating: Array(repeating: 0.0, count: n), count: n + 1)
    for e in entries {
        let chars = Array(e.word)
        if let first = chars.first, let fi = letterIndex[first] { rows[0][fi] += e.p }
        for i in 1..<max(chars.count, 1) {
            guard let prev = letterIndex[chars[i - 1]], let cur = letterIndex[chars[i]] else { continue }
            rows[prev + 1][cur] += e.p
        }
    }
    let rowBytes: [[UInt8]] = rows.map { row in
        let mx = row.max() ?? 0
        guard mx > 0 else { return Array(repeating: 0, count: n) }
        return row.map { UInt8(max(0, min(255, ($0 / mx * 255).rounded()))) }
    }

    // ── Write .clex ─────────────────────────────────────────────────────────
    var clex = Data()
    clex.append(contentsOf: Array("CLEX".utf8))
    appendU32(1, to: &clex)
    appendU32(UInt32(entries.count), to: &clex)
    appendU32(UInt32(n), to: &clex)
    for ch in alphabet {
        appendU32(ch.unicodeScalars.first!.value, to: &clex)
    }
    for row in rowBytes { clex.append(contentsOf: row) }
    var offset: UInt32 = 0
    for e in entries { appendU32(offset, to: &clex); offset += UInt32(e.bytes.count) }
    appendU32(offset, to: &clex)
    for e in entries { clex.append(quantizeLog(e.p, floorExp: -9, scale: 28)) }
    for e in entries { clex.append(UInt8(min(255, e.word.count))) }
    for e in entries { clex.append(contentsOf: e.bytes) }
    let clexURL = outDir.appendingPathComponent("\(cfg.code).clex")
    try! clex.write(to: clexURL)

    // ── Word bigrams ────────────────────────────────────────────────────────
    var pairStats = "no bigrams"
    if let source = cfg.bigrams {
        var pairCounts: [UInt64: Double] = [:]   // (prevID << 32 | nextID) → count
        func record(_ a: String, _ b: String, _ c: Double) {
            guard let pa = idOf[a], let pb = idOf[b] else { return }
            pairCounts[UInt64(pa) << 32 | UInt64(pb), default: 0] += c
        }
        switch source {
        case .tatoeba(let file):
            let url = wordlists.appendingPathComponent(file)
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                fail("cannot read \(url.path)")
            }
            let separators = CharacterSet.letters
                .union(CharacterSet(charactersIn: "'\u{2019}-")).inverted
            for line in text.split(separator: "\n") {
                // id \t lang \t sentence
                guard let lastTab = line.lastIndex(of: "\t") else { continue }
                let sentence = line[line.index(after: lastTab)...]
                var prev: String?
                for raw in sentence.components(separatedBy: separators) where !raw.isEmpty {
                    let w = normalise(raw)
                    if let p = prev { record(p, w, 1) }
                    prev = w
                }
            }
        }

        // Keep the strongest pairs, then order (prev asc, count desc).
        let top = pairCounts.sorted { $0.value > $1.value }.prefix(cfg.pairCap)
        var perPrevTotal: [UInt32: Double] = [:]
        for (k, c) in top { perPrevTotal[UInt32(k >> 32), default: 0] += c }
        let ordered = top.sorted {
            let pa = UInt32($0.key >> 32), pb = UInt32($1.key >> 32)
            if pa != pb { return pa < pb }
            return $0.value > $1.value
        }

        var cngm = Data()
        cngm.append(contentsOf: Array("CNGM".utf8))
        appendU32(1, to: &cngm)
        appendU32(UInt32(ordered.count), to: &cngm)
        for (k, _) in ordered { appendU32(UInt32(k >> 32), to: &cngm) }
        for (k, _) in ordered { appendU32(UInt32(k & 0xFFFF_FFFF), to: &cngm) }
        for (k, c) in ordered {
            let p = c / (perPrevTotal[UInt32(k >> 32)] ?? c)
            cngm.append(quantizeLog(p, floorExp: -6, scale: 42))
        }
        let cngmURL = outDir.appendingPathComponent("\(cfg.code).cngm")
        try! cngm.write(to: cngmURL)
        pairStats = "\(ordered.count) pairs (\(cngm.count / 1024) KB)"
    }

    let dt = String(format: "%.1fs", -t0.timeIntervalSinceNow)
    print("\(cfg.code): \(entries.count) words (\(clex.count / 1024) KB), \(pairStats) [\(dt)]")
}
print("wrote \(outDir.path)")
