/**
 On-device AI backend via Apple Intelligence (the FoundationModels framework,
 iOS 26+). This is the single home for all FoundationModels usage: availability
 probing, lazy session management, and async text generation. Future features
 (predictive typing, translator panel, AI suggestions, adaptive hitboxes) call
 into `AIEngine`; nothing else in the codebase should import FoundationModels.

 Fully offline — inference runs in an Apple system process, so it works inside
 the keyboard extension without counting against its memory cap. 100% optional:
 callers gate on `KeyboardSettings.aiEnabled` (off by default); the engine
 itself never reads settings so it stays pure and testable.
 

 Module: prediction · Target: ClinkKit
 Learn: docs/04-prediction.md
 */
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Why on-device AI is or isn't usable right now. Plain Swift (no
/// FoundationModels types) so it's constructible and testable on iOS 17.
public enum AIAvailability: Equatable, Sendable {
    /// Apple Intelligence is on and the model is ready.
    case available
    /// The device is running an OS older than iOS 26 (no FoundationModels).
    case osBelowMinimum
    /// The hardware can't run Apple Intelligence (pre-A17 Pro / M-series).
    case deviceNotEligible
    /// Capable device, but Apple Intelligence is switched off in Settings.
    case appleIntelligenceNotEnabled
    /// Model assets are still downloading / preparing; transient.
    case modelNotReady
    /// Unavailable for a reason this build doesn't know about.
    case unavailableOther

    /// Probe the live system state. Cheap; safe to call from any context on
    /// any OS version.
    public static func current() -> AIAvailability {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else { return .osBelowMinimum }
        return AIAvailability(SystemLanguageModel.default.availability)
        #else
        return .osBelowMinimum
        #endif
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
extension AIAvailability {
    init(_ availability: SystemLanguageModel.Availability) {
        switch availability {
        case .available:
            self = .available
        case .unavailable(.deviceNotEligible):
            self = .deviceNotEligible
        case .unavailable(.appleIntelligenceNotEnabled):
            self = .appleIntelligenceNotEnabled
        case .unavailable(.modelNotReady):
            self = .modelNotReady
        case .unavailable:
            // Future SDK reasons degrade gracefully instead of trapping.
            self = .unavailableOther
        }
    }
}
#endif

public enum AIEngineError: Error, Sendable {
    /// Generation was requested while the model isn't usable; carries the
    /// reason so callers can surface accurate copy.
    case unavailable(AIAvailability)
    case generationFailed(String)
}

/// Lazy, actor-isolated wrapper around `LanguageModelSession`. An actor (not
/// `@MainActor`) so generation never competes with keyboard rendering; the
/// shared instance does zero work until a feature actually calls it — merely
/// linking this file costs nothing at keyboard launch.
public actor AIEngine {
    public static let shared = AIEngine()

    /// One unit of text generation. Defaults are tuned for short,
    /// keyboard-shaped output (suggestions, corrections, translations).
    public struct GenerationRequest: Sendable {
        public var prompt: String
        /// System-style instructions. The session is rebuilt when these change,
        /// so features with a stable persona pay the setup cost once.
        public var instructions: String?
        /// Sampling temperature passed to `GenerationOptions`.
        public var temperature: Double
        /// Hard cap on generated tokens — kept low for keyboard-shaped output.
        public var maximumResponseTokens: Int

        public init(
            prompt: String,
            instructions: String? = nil,
            temperature: Double = 0.7,
            maximumResponseTokens: Int = 128
        ) {
            self.prompt = prompt
            self.instructions = instructions
            self.temperature = temperature
            self.maximumResponseTokens = maximumResponseTokens
        }
    }

    /// The live `LanguageModelSession`, type-erased so this stored property
    /// compiles with the iOS 17 deployment floor. Only touched inside
    /// `#available(iOS 26.0, *)` branches.
    private var sessionBox: Any?
    /// Instructions the current session was created with; a mismatch on the
    /// next request rebuilds the session.
    private var sessionInstructions: String?

    public init() {}

    /// Create the session (if needed) and ask the system to load model assets
    /// ahead of the first request, hiding first-token latency. Safe to call
    /// repeatedly; a no-op below iOS 26 or when the model is unavailable.
    public func prewarm(instructions: String? = nil) {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *), AIAvailability.current() == .available else { return }
        session(instructions: instructions).prewarm()
        #endif
    }

    /// One-shot generation. Throws `AIEngineError.unavailable` when the model
    /// can't run (callers should have gated on `settings.aiEnabled` already).
    public func generate(_ request: GenerationRequest) async throws -> String {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else { throw AIEngineError.unavailable(.osBelowMinimum) }
        let availability = AIAvailability.current()
        guard availability == .available else { throw AIEngineError.unavailable(availability) }
        do {
            let response = try await session(instructions: request.instructions)
                .respond(to: request.prompt, options: options(for: request))
            return response.content
        } catch {
            // A failed session (e.g. context window exceeded) is not reusable.
            sessionBox = nil
            throw AIEngineError.generationFailed(String(describing: error))
        }
        #else
        throw AIEngineError.unavailable(.osBelowMinimum)
        #endif
    }

    /// Streamed generation for future live-typing features. Yields *deltas*
    /// (newly generated text only), not cumulative snapshots. `nonisolated`:
    /// it only spawns a task that hops onto the actor, so callers get the
    /// stream synchronously.
    public nonisolated func generateStream(_ request: GenerationRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.stream(request) { continuation.yield($0) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Drop the session — call on memory pressure or when the user turns the
    /// AI setting off. The next request lazily rebuilds it.
    public func reset() {
        sessionBox = nil
        sessionInstructions = nil
    }

    // MARK: - Internals

    private func stream(_ request: GenerationRequest, yield: @Sendable (String) -> Void) async throws {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else { throw AIEngineError.unavailable(.osBelowMinimum) }
        let availability = AIAvailability.current()
        guard availability == .available else { throw AIEngineError.unavailable(availability) }
        do {
            var delivered = ""
            let stream = session(instructions: request.instructions)
                .streamResponse(to: request.prompt, options: options(for: request))
            for try await snapshot in stream {
                // Snapshots are cumulative; forward only the new suffix.
                let content = snapshot.content
                if content.hasPrefix(delivered) {
                    yield(String(content.dropFirst(delivered.count)))
                } else {
                    yield(content)
                }
                delivered = content
            }
        } catch {
            sessionBox = nil
            throw AIEngineError.generationFailed(String(describing: error))
        }
        #else
        throw AIEngineError.unavailable(.osBelowMinimum)
        #endif
    }

    #if canImport(FoundationModels)
    /// Return the cached session, rebuilding it when the requested
    /// instructions differ from the ones it was created with.
    @available(iOS 26.0, *)
    private func session(instructions: String?) -> LanguageModelSession {
        if let existing = sessionBox as? LanguageModelSession, sessionInstructions == instructions {
            return existing
        }
        let session: LanguageModelSession
        if let instructions {
            session = LanguageModelSession(instructions: instructions)
        } else {
            session = LanguageModelSession()
        }
        sessionBox = session
        sessionInstructions = instructions
        return session
    }

    @available(iOS 26.0, *)
    private func options(for request: GenerationRequest) -> GenerationOptions {
        GenerationOptions(
            temperature: request.temperature,
            maximumResponseTokens: request.maximumResponseTokens
        )
    }
    #endif
}
