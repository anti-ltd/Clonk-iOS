/**
 `MotionDiagnostics`: zero-cost-in-release instrumentation for the motion system.

 Emits signpost events/intervals into Instruments' Points of Interest track so
 animation triggers can be lined up against frame drops in a trace ("did the
 hitch land on the panel open or the suggestion compute?"). Everything here
 compiles to nothing in Release — the keyboard extension's memory and CPU
 budgets never pay for it, and signposts cost effectively nothing even in
 Debug unless Instruments is actually recording.

 Usage:
     MotionDiagnostics.event("emoji.flash")
     MotionDiagnostics.interval("panel.layout") { ... }

 Profile the keyboard extension by attaching Instruments (os_signpost / Points
 of Interest) to the ClinkKeyboard process while typing in any host app.
 

 Module: motion · Target: ClinkKit
 Learn: MOTION.md
 */
import Foundation
import OSLog

enum MotionDiagnostics {
    #if DEBUG
    private static let signposter = OSSignposter(subsystem: "ltd.anti.clink",
                                                 category: .pointsOfInterest)
    #endif

    /// Mark the instant an animation is triggered (one tick in the trace).
    @inline(__always)
    static func event(_ name: StaticString) {
        #if DEBUG
        signposter.emitEvent(name)
        #endif
    }

    /// Wrap synchronous work in a named signpost interval.
    @inline(__always)
    static func interval<T>(_ name: StaticString, _ body: () throws -> T) rethrows -> T {
        #if DEBUG
        let state = signposter.beginInterval(name)
        defer { signposter.endInterval(name, state) }
        return try body()
        #else
        return try body()
        #endif
    }
}
