/**
 UserAdaptation behavior tests: learnability filter, thresholds, rejection
 suppression. Uses a store pointed at a nonexistent App Group (falls back to
 UserDefaults), cleared per test so state never leaks between runs.
 */
import Foundation
import Testing

/// Fresh, isolated store per test (bogus group ID → UserDefaults fallback).
private func freshStore() -> UserAdaptation {
    let store = UserAdaptation(appGroupID: "group.test.invalid.\(UUID().uuidString)")
    store.clear()
    return store
}

@Suite(.serialized) struct UserAdaptationTests {
    @Test func learnableFilterRejectsNoise() {
        #expect(UserAdaptation.isLearnable("hello"))
        #expect(UserAdaptation.isLearnable("don't"))
        #expect(UserAdaptation.isLearnable("auto-stop"))
        #expect(UserAdaptation.isLearnable("привет"))
        #expect(!UserAdaptation.isLearnable("a"))            // one-letter noise
        #expect(!UserAdaptation.isLearnable("abc123"))       // digits
        #expect(!UserAdaptation.isLearnable("a@b.com"))      // symbols
        #expect(!UserAdaptation.isLearnable(""))
        #expect(!UserAdaptation.isLearnable(String(repeating: "x", count: 40)))
    }

    @Test func singleCommitIsNotLearned() {
        let store = freshStore()
        store.recordCommit("frobnicate")
        #expect(!store.isLearned("frobnicate"))   // threshold is 2
        store.recordCommit("frobnicate")
        #expect(store.isLearned("frobnicate"))
        #expect(store.isLearned("FROBNICATE"))    // case-insensitive key
    }

    @Test func learnedWordsKeepUserCasing() {
        let store = freshStore()
        store.recordCommit("Felix")
        store.recordCommit("Felix")
        #expect(store.learnedWords().contains("Felix"))
        #expect(store.completions(prefix: "fel", limit: 3) == ["Felix"])
        // The word itself is not its own completion.
        #expect(store.completions(prefix: "felix", limit: 3).isEmpty)
    }

    @Test func rankBoostGrowsWithUse() {
        let store = freshStore()
        #expect(store.rankBoost(for: "word") == 0)
        store.recordCommit("word")
        let one = store.rankBoost(for: "word")
        store.recordCommit("word")
        store.recordCommit("word")
        let three = store.rankBoost(for: "word")
        #expect(one > 0)
        #expect(three > one)
        #expect(three < 2)   // boosts stay bounded — never dwarf real frequency
    }

    @Test func rejectionSuppressesAfterThreshold() {
        let store = freshStore()
        store.recordRejection(from: "dawg", to: "dog")
        #expect(!store.isRejected("dawg"))         // once could be a slip
        store.recordRejection(from: "dawg", to: "dog")
        #expect(store.isRejected("dawg"))
        #expect(store.isRejected("Dawg"))
        // Rejecting a correction is also a strong commit of the original.
        #expect(store.isLearned("dawg"))
    }

    @Test func clearWipesEverything() {
        let store = freshStore()
        store.recordCommit("hello")
        store.recordCommit("hello")
        store.recordRejection(from: "teh", to: "the")
        store.recordRejection(from: "teh", to: "the")
        store.clear()
        #expect(!store.isLearned("hello"))
        #expect(!store.isRejected("teh"))
        #expect(store.learnedWords().isEmpty)
    }

    @Test func customWordIsImmediatelyLearnedAndListed() {
        let store = freshStore()
        #expect(store.addCustomWord("Frodo"))
        #expect(store.isLearned("frodo"))                 // valid from the start
        #expect(store.customWords() == ["Frodo"])         // user casing kept
        #expect(store.learnedWords().contains("Frodo"))   // engine sees it
        #expect(!store.organicLearnedWords().contains("Frodo")) // but UI history doesn't
        #expect(!store.addCustomWord("frodo"))            // dup (any casing) rejected
        #expect(!store.addCustomWord("a"))                // noise rejected
    }

    @Test func clearKeepsCustomWordsButWipesLearned() {
        let store = freshStore()
        store.recordCommit("hello"); store.recordCommit("hello")
        store.addCustomWord("Galadriel")
        store.clear()
        #expect(!store.isLearned("hello"))                // organic word gone
        #expect(store.isLearned("galadriel"))             // custom word stays
        #expect(store.customWords() == ["Galadriel"])
    }

    @Test func removeCustomWordDropsIt() {
        let store = freshStore()
        store.addCustomWord("Smeagol")
        store.removeCustomWord("smeagol")                 // case-insensitive
        #expect(store.customWords().isEmpty)
        #expect(!store.isLearned("smeagol"))
    }

    @Test func persistenceRoundTripsThroughFlush() {
        let groupID = "group.test.invalid.persist"
        let a = UserAdaptation(appGroupID: groupID)
        a.clear()
        a.recordCommit("persisted")
        a.recordCommit("persisted")
        a.flush()
        let b = UserAdaptation(appGroupID: groupID)
        #expect(b.isLearned("persisted"))
        b.clear()
    }
}
