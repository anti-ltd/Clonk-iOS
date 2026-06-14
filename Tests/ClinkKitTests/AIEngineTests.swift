/**
 AIEngine / AIAvailability logic tests. These never exercise live Apple
 Intelligence (the simulator host may or may not support it) — they pin the
 pure parts: the availability mapping, request defaults, the unavailable-throw
 contract, and the settings gate's encode/decode behavior.
 */
import Foundation
import Testing
#if canImport(FoundationModels)
import FoundationModels
#endif

@Suite struct AIEngineTests {

    @Test func generationRequestDefaults() {
        let r = AIEngine.GenerationRequest(prompt: "hello")
        #expect(r.prompt == "hello")
        #expect(r.instructions == nil)
        #expect(r.temperature == 0.7)
        #expect(r.maximumResponseTokens == 128)
    }

    /// `generate` must throw `.unavailable` (never crash, never hang) when the
    /// model can't run. Skipped in the one environment where it CAN run —
    /// there the throw contract doesn't apply.
    @Test func generateThrowsWhenUnavailable() async {
        guard AIAvailability.current() != .available else { return }
        await #expect(throws: AIEngineError.self) {
            _ = try await AIEngine().generate(.init(prompt: "hi"))
        }
    }

    /// Same contract for the streaming variant: the stream finishes by
    /// throwing, it doesn't yield and it doesn't hang.
    @Test func streamThrowsWhenUnavailable() async {
        guard AIAvailability.current() != .available else { return }
        var yielded = [String]()
        do {
            for try await delta in AIEngine().generateStream(.init(prompt: "hi")) {
                yielded.append(delta)
            }
            Issue.record("stream should have thrown")
        } catch {
            #expect(error is AIEngineError)
        }
        #expect(yielded.isEmpty)
    }

    /// Empty / whitespace input short-circuits to "" before touching the model,
    /// so it's safe (and free) on any device.
    @Test func translateEmptyIsNoOp() async throws {
        let out = try await AIEngine().translate("   \n ", to: "Spanish")
        #expect(out.isEmpty)
    }

    /// Real input routes through `generate`, so it honours the same
    /// unavailable-throw contract when the model can't run.
    @Test func translateThrowsWhenUnavailable() async {
        guard AIAvailability.current() != .available else { return }
        await #expect(throws: AIEngineError.self) {
            _ = try await AIEngine().translate("hello", to: "Spanish")
        }
    }

    /// Prewarm and reset are unconditionally safe no-ops when unavailable.
    @Test func prewarmAndResetAreSafe() async {
        let engine = AIEngine()
        await engine.prewarm()
        await engine.prewarm(instructions: "be brief")
        await engine.reset()
    }

    #if canImport(FoundationModels)
    @Test func availabilityMapping() {
        guard #available(iOS 26.0, *) else { return }
        #expect(AIAvailability(.available) == .available)
        #expect(AIAvailability(.unavailable(.deviceNotEligible)) == .deviceNotEligible)
        #expect(AIAvailability(.unavailable(.appleIntelligenceNotEnabled)) == .appleIntelligenceNotEnabled)
        #expect(AIAvailability(.unavailable(.modelNotReady)) == .modelNotReady)
    }
    #endif

    @Test func aiEnabledSettingRoundTrips() throws {
        var s = KeyboardSettings()
        #expect(s.aiEnabled == false)   // off by default — AI is strictly opt-in

        s.aiEnabled = true
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(KeyboardSettings.self, from: data)
        #expect(decoded.aiEnabled == true)
    }
}
