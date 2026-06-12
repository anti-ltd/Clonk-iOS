/**
 `UserAdaptation`: the keyboard's opt-in, on-device learning store. Remembers
 words the user actually commits, boosts ones they accept from the bar, and
 permanently suppresses corrections they reject — so the keyboard stops
 fighting the user's vocabulary.

 Everything lives in one JSON file in the App Group container (same pattern
 as `SharedStore`; falls back to standard UserDefaults when the container is
 unavailable — fine, since the keyboard extension is the only real consumer).
 Nothing ever leaves the device. All reads/writes are gated by the
 `learningEnabled` setting at the call sites; this store is mechanism only.
 

 Module: prediction · Target: ClinkKit
 Learn: docs/04-prediction.md
 */
import Foundation

public final class UserAdaptation: @unchecked Sendable {
    public static let shared = UserAdaptation()

    /// One learned word: an exponentially-decaying usage weight plus the casing
    /// the user most recently typed (so "Felix" stays capitalized).
    private struct Entry: Codable {
        var weight: Double
        var lastUsed: Date
        var display: String
    }
    private struct Rejection: Codable {
        var to: String
        var count: Int
        var lastUsed: Date
    }
    private struct Payload: Codable {
        var words: [String: Entry] = [:]        // keyed by lowercased word
        var rejections: [String: Rejection] = [:] // keyed by lowercased original
    }

    /// Words seen at least this often count as "learned" (valid, rank-boosted,
    /// in the swipe vocabulary). A single stray typo never qualifies.
    private static let learnedThreshold = 2.0
    /// A correction reverted/rejected this many times is suppressed for good.
    private static let rejectionThreshold = 2
    /// Usage weights halve after this many days without use, so abandoned
    /// words fade out instead of polluting ranking forever.
    private static let decayHalfLifeDays = 30.0
    private static let wordCap = 2_000
    private static let rejectionCap = 500
    /// Commits between coalesced saves (plus an explicit `flush()` on hide).
    private static let saveEvery = 12

    private let lock = NSLock()
    private var payload = Payload()
    private var unsavedChanges = 0
    private let fileURL: URL?
    private let defaultsKey = "clink-learned-v1"

    public init(appGroupID: String = SharedStore.appGroupID) {
        fileURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent("clink-learned.v1.json")
        payload = Self.decayed(loadPayload(), now: Date())
    }

    // MARK: - Reads (cheap, called from ranking paths)

    /// Whether `word` has been typed often enough to be treated as a real word
    /// (never autocorrected away, boosted in the bar, swipeable).
    public func isLearned(_ word: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return (payload.words[word.lowercased()]?.weight ?? 0) >= Self.learnedThreshold
    }

    /// Additive log10-scale ranking boost for `word` (0 when unknown). Grows
    /// slowly with use: a handful of commits ≈ one decade of corpus frequency.
    public func rankBoost(for word: String) -> Double {
        lock.lock(); defer { lock.unlock() }
        guard let e = payload.words[word.lowercased()] else { return 0 }
        return log10(1 + e.weight) * 0.8
    }

    /// All learned words in their user-typed casing (for swipe vocab and
    /// prefix completion injection). Small by construction (≤ `wordCap`).
    public func learnedWords() -> [String] {
        lock.lock(); defer { lock.unlock() }
        return payload.words.values
            .filter { $0.weight >= Self.learnedThreshold }
            .map(\.display)
    }

    /// Learned words starting with `prefix`, best first.
    public func completions(prefix: String, limit: Int) -> [String] {
        guard !prefix.isEmpty else { return [] }
        let lower = prefix.lowercased()
        lock.lock(); defer { lock.unlock() }
        return payload.words
            .filter { $0.key.hasPrefix(lower) && $0.key != lower
                && $0.value.weight >= Self.learnedThreshold }
            .sorted { $0.value.weight > $1.value.weight }
            .prefix(limit).map(\.value.display)
    }

    /// True when correcting `original` has been rejected often enough that the
    /// keyboard should permanently leave it alone.
    public func isRejected(_ original: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return (payload.rejections[original.lowercased()]?.count ?? 0) >= Self.rejectionThreshold
    }

    // MARK: - Writes (event hooks; coalesced persistence)

    /// A word the user committed by typing a terminator. `weight` lets stronger
    /// signals (reverting an autocorrect back to it, tapping it in the bar)
    /// count for more than a plain commit.
    public func recordCommit(_ word: String, weight: Double = 1) {
        guard Self.isLearnable(word) else { return }
        let key = word.lowercased()
        lock.lock()
        var e = payload.words[key] ?? Entry(weight: 0, lastUsed: Date(), display: word)
        e.weight += weight
        e.lastUsed = Date()
        e.display = word
        payload.words[key] = e
        evictIfNeededLocked()
        lock.unlock()
        touch()
    }

    /// The user undid (or pre-emptively cancelled) the `from → to` correction.
    /// Also counts as a strong commit of `from` — they insisted on it.
    public func recordRejection(from: String, to: String) {
        let key = from.lowercased()
        lock.lock()
        var r = payload.rejections[key] ?? Rejection(to: to, count: 0, lastUsed: Date())
        r.count += 1
        r.to = to
        r.lastUsed = Date()
        payload.rejections[key] = r
        evictIfNeededLocked()
        lock.unlock()
        touch()
        recordCommit(from, weight: 2)
    }

    /// Persist any unsaved changes now (call when the keyboard hides).
    public func flush() {
        lock.lock()
        let dirty = unsavedChanges > 0
        unsavedChanges = 0
        let snapshot = payload
        lock.unlock()
        if dirty { save(snapshot) }
    }

    /// Wipe everything (the app's "Clear learned words" action).
    public func clear() {
        lock.lock()
        payload = Payload()
        unsavedChanges = 0
        lock.unlock()
        save(Payload())
    }

    // MARK: - Internals

    /// Words worth learning: real letter words (apostrophes/hyphens allowed),
    /// 2–32 chars. Numbers, codes, emails and one-letter noise never qualify.
    static func isLearnable(_ word: String) -> Bool {
        guard word.count >= 2, word.count <= 32 else { return false }
        let letters = CharacterSet.letters
        var hasLetter = false
        for s in word.unicodeScalars {
            if letters.contains(s) { hasLetter = true; continue }
            if s == "'" || s == "\u{2019}" || s == "-" { continue }
            return false
        }
        return hasLetter
    }

    private func touch() {
        lock.lock()
        unsavedChanges += 1
        let shouldSave = unsavedChanges >= Self.saveEvery
        if shouldSave { unsavedChanges = 0 }
        let snapshot = shouldSave ? payload : nil
        lock.unlock()
        if let snapshot { save(snapshot) }
    }

    /// Keep the store bounded: drop the weakest/oldest entries past the caps.
    private func evictIfNeededLocked() {
        if payload.words.count > Self.wordCap {
            let sorted = payload.words.sorted {
                ($0.value.weight, $0.value.lastUsed) < ($1.value.weight, $1.value.lastUsed)
            }
            for (key, _) in sorted.prefix(payload.words.count - Self.wordCap) {
                payload.words.removeValue(forKey: key)
            }
        }
        if payload.rejections.count > Self.rejectionCap {
            let sorted = payload.rejections.sorted { $0.value.lastUsed < $1.value.lastUsed }
            for (key, _) in sorted.prefix(payload.rejections.count - Self.rejectionCap) {
                payload.rejections.removeValue(forKey: key)
            }
        }
    }

    /// Apply exponential decay at load so dormant words fade across sessions
    /// without any background work. Entries that decay to noise are dropped.
    private static func decayed(_ payload: Payload, now: Date) -> Payload {
        var out = payload
        for (key, var e) in out.words {
            let days = now.timeIntervalSince(e.lastUsed) / 86_400
            if days > 1 {
                e.weight *= pow(0.5, days / decayHalfLifeDays)
                if e.weight < 0.25 { out.words.removeValue(forKey: key); continue }
                out.words[key] = e
            }
        }
        return out
    }

    private func loadPayload() -> Payload {
        if let url = fileURL,
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(Payload.self, from: data) {
            return decoded
        }
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode(Payload.self, from: data) {
            return decoded
        }
        return Payload()
    }

    private func save(_ snapshot: Payload) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        if let url = fileURL {
            try? data.write(to: url, options: .atomic)
        } else {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}
