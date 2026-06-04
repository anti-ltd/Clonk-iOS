import SwiftUI
import UIKit

/// Multitouch input for the key grid.
///
/// The keys used to each carry their own SwiftUI `DragGesture`. That reads fine
/// for one slow finger, but SwiftUI's gesture system doesn't reliably track two
/// simultaneous touches across sibling views — so when you type *fast* and press
/// the next key before lifting the last (the overlap every touch-typist does),
/// the second press is dropped or arrives late. It feels "off" without an
/// obvious cause.
///
/// The fix: hand all touch handling to a single `UIView` with
/// `isMultipleTouchEnabled`, which receives every `UITouch` independently. Each
/// touch binds to the key it lands on and keeps the *exact* per-key semantics the
/// gestures had — character keys commit on touch-down (instant), function keys on
/// release, backspace auto-repeats while held, the space bar is a tap-or-trackpad.
/// Only the dropped-simultaneous-touch problem goes away.
///
/// `KeyTouchRouter` is the shared, observable bridge: the UIView writes press
/// state into it during touch events (on the main thread — safe), and every
/// `KeyView` reads its own pressed/warp state back out. The SwiftUI views keep
/// rendering exactly as before; only the *source* of the press changed.
@MainActor
@Observable
public final class KeyTouchRouter {
    /// Keys currently held down (by any finger). Each `KeyView` renders pressed
    /// when its ID is in here. Recomputed as the union of all active touches, so
    /// two fingers on one key keep it lit until both lift.
    public private(set) var pressed: Set<String> = []

    /// Space-bar trackpad: live horizontal drag offset (drives the glass warp)
    /// and whether the current space touch has crossed into cursor-drag mode.
    public private(set) var spaceDragX: CGFloat = 0
    public private(set) var spaceCursorActive = false

    /// Bumped on every backspace auto-repeat so the delete glyph bounces.
    public private(set) var deleteTick = 0

    /// Per-key counter bumped on *every* touch-down. Drives the additive "tap
    /// pulse" each `KeyView` plays to confirm a press.
    ///
    /// `pressed` can't do this job: the press bloom is sprung on `pressed`
    /// changing, but pressing the same key twice in quick succession (the second
    /// `l` in "tell") re-fires inside the linger window, so the key never leaves
    /// `pressed` and the bloom never re-animates — the second tap reads as
    /// dropped even though the character *was* inserted. This tick changes on
    /// every landing, so the pulse fires every time regardless of press state.
    public private(set) var tapTicks: [String: Int] = [:]

    /// The current tap count for a key (0 if never pressed). Read by `KeyView` as
    /// its pulse trigger.
    public func tapTick(_ id: String) -> Int { tapTicks[id] ?? 0 }

    public init() {}

    // MARK: - Registry (pushed in from the layout each pass)
    //
    // Only the *frames* flow through SwiftUI preferences (cheap, Equatable). The
    // specs — which carry non-Equatable action closures — are fetched on demand
    // via `resolveSpec` at touch time, so they always reflect the current plane /
    // shift without round-tripping closures through the preference system.

    /// keyID → frame in the grid's coordinate space.
    fileprivate var frames: [String: CGRect] = [:]
    /// keyID → its current spec (rebuilt by the canvas, reflecting plane/shift).
    fileprivate var resolveSpec: (String) -> KeySpec? = { _ in nil }
    /// Fired on every key-down — the host plays the clink + haptic here.
    fileprivate var onPressDown: () -> Void = {}
    /// How long a key stays visually pressed *after* the finger lifts (seconds).
    /// A quick tap otherwise flips pressed on→off within a frame or two, so the
    /// bloom/colour spring never reaches full strength and the press reads dim.
    /// Holding it briefly lets the effect bloom fully, then spring back.
    fileprivate var lingerDuration: TimeInterval = 0.1
    /// Scale applied to each key's frame before hit-testing (see `key(at:)`).
    fileprivate var hitboxScale: Double = 1.0

    fileprivate func update(frames: [String: CGRect],
                            resolveSpec: @escaping (String) -> KeySpec?,
                            onPressDown: @escaping () -> Void,
                            lingerDuration: TimeInterval,
                            hitboxScale: Double) {
        self.frames = frames
        self.resolveSpec = resolveSpec
        self.onPressDown = onPressDown
        self.lingerDuration = lingerDuration
        self.hitboxScale = hitboxScale
    }

    // MARK: - Hit testing

    /// The key nearest a point. The touch surface covers the whole key region
    /// (including the gaps between keys and the side margins), so we always map a
    /// touch to *some* key rather than letting taps fall into dead gaps. That
    /// matches the native keyboard's generous edge/gap targets.
    ///
    /// We measure distance to each key's *frame rectangle* (0 when the point is
    /// inside it), NOT to its centre. Centre distance has no row awareness: a wide
    /// key like the space bar has a far-off centre, so a tap in the bottom-row gap
    /// beside it would be "won" by a narrow key one row up (e.g. `n`/`m`) whose
    /// centre happens to be closer. Rect distance gives every bottom-row key a
    /// vertical distance of 0 across that whole band, so a touch there can never
    /// jump up a row.
    fileprivate func key(at point: CGPoint) -> String? {
        var best: String?
        var bestDist = CGFloat.greatestFiniteMagnitude
        for (id, f) in frames {
            let sf = scaledFrame(f)
            let dx = max(sf.minX - point.x, 0, point.x - sf.maxX)
            let dy = max(sf.minY - point.y, 0, point.y - sf.maxY)
            let d = dx * dx + dy * dy
            if d < bestDist { bestDist = d; best = id }
        }
        return best
    }

    private func scaledFrame(_ f: CGRect) -> CGRect {
        guard hitboxScale != 1.0 else { return f }
        let w = f.width * CGFloat(hitboxScale)
        let h = f.height * CGFloat(hitboxScale)
        return CGRect(x: f.midX - w / 2, y: f.midY - h / 2, width: w, height: h)
    }

    // MARK: - Per-touch lifecycle (called by the UIView)
    //
    // Each touch is bound to the key it lands on for its whole life — exactly how
    // the old per-key gesture behaved, just now genuinely multitouch.

    fileprivate func touchDown(id: String) {
        guard let spec = resolveSpec(id) else { return }
        heldCounts[id, default: 0] += 1
        cancelLinger(id)            // pressed again → stop any pending fade-out
        recomputePressed()
        tapTicks[id, default: 0] &+= 1   // fire the per-press tap pulse
        onPressDown()

        switch spec.kind {
        case .character:
            // The space bar is a character key but inserts on *release* (a tap),
            // because a press-and-drag is the cursor trackpad instead. Every other
            // character commits instantly on touch-down.
            if spec.isSpace {
                spaceCursorActive = false
                spaceDragX = 0
                spaceSteps = 0
            } else {
                spec.action()
            }
        case .function:
            if spec.isRepeatable {
                startRepeating(spec)
            }
            // Other function keys (shift, plane toggle, globe, return) fire on
            // release — see `touchUp`.
        }
    }

    fileprivate func touchMoved(id: String, translationX: CGFloat, translationY: CGFloat) {
        guard let spec = resolveSpec(id) else { return }

        // Drag-up keys (the 123→emoji gesture): once the finger has travelled far
        // enough upward, fire once and mark the touch consumed so `touchUp` skips
        // the normal tap action. Mirrors the space-bar trackpad's tap-vs-drag split.
        if spec.onDragUp != nil, !dragUpFired.contains(id),
           translationY < -Self.dragUpThreshold {
            dragUpFired.insert(id)
            // The canvas swaps out from under this touch, so it never gets a
            // touchUp/cancel — clear the key's press now or it sticks "pressed"
            // (the 123 key stayed blue after returning to letters).
            clearPress(id)
            dragHaptic.impactOccurred()
            spec.onDragUp?()
            return
        }

        guard spec.isSpace else { return }
        // Past a small threshold the space touch becomes a cursor trackpad; a
        // plain tap (no real movement) still types a space on release.
        if abs(translationX) > Self.cursorStride { spaceCursorActive = true }
        guard spaceCursorActive else { return }
        spaceDragX = translationX
        let step = Int((translationX / Self.cursorStride).rounded(.towardZero))
        if step != spaceSteps {
            spec.onCursorMove?(step - spaceSteps)
            spaceSteps = step
        }
    }

    fileprivate func touchUp(id: String) {
        releaseHold(id)
        guard let spec = resolveSpec(id) else { return }

        // A drag-up gesture already fired and consumed this touch — don't also run
        // the key's tap action (e.g. don't switch to numbers after opening emoji).
        if dragUpFired.remove(id) != nil { return }

        switch spec.kind {
        case .character:
            if spec.isSpace {
                if !spaceCursorActive { spec.action() }   // tap → space
                spaceCursorActive = false
                spaceDragX = 0
                spaceSteps = 0
            }
            // Non-space characters already committed on touch-down.
        case .function:
            if spec.isRepeatable {
                stopRepeating()
            } else {
                spec.action()   // shift / plane toggle / globe / return
            }
        }
    }

    fileprivate func touchCancelled(id: String) {
        releaseHold(id)
        dragUpFired.remove(id)
        guard let spec = resolveSpec(id) else { return }
        if spec.isRepeatable { stopRepeating() }
        if spec.isSpace {
            spaceCursorActive = false
            spaceDragX = 0
            spaceSteps = 0
        }
    }

    // MARK: - Press state + linger
    //
    // A key reads "pressed" while a finger holds it OR while it's lingering after
    // release. `heldCounts` tracks fingers per key (so two fingers on one key keep
    // it lit until both lift); `lingering` holds keys whose fade-out is pending.

    private var heldCounts: [String: Int] = [:]
    private var lingering: Set<String> = []
    private var lingerTasks: [String: Task<Void, Never>] = [:]

    /// Drop one finger from a key; once none remain, start its linger fade-out.
    private func releaseHold(_ id: String) {
        let remaining = (heldCounts[id] ?? 1) - 1
        if remaining <= 0 {
            heldCounts[id] = nil
            startLinger(id)
        } else {
            heldCounts[id] = remaining
        }
        recomputePressed()
    }

    private func recomputePressed() {
        let next = Set(heldCounts.keys).union(lingering)
        if next != pressed { pressed = next }
    }

    /// Immediately drop a key's pressed state (no linger) — used when a gesture
    /// (123→emoji drag) swaps the canvas out from under the touch, so the key
    /// can't receive its normal release.
    private func clearPress(_ id: String) {
        heldCounts[id] = nil
        cancelLinger(id)
        recomputePressed()
    }

    /// Light tap played when the 123→emoji drag fires — the gesture's feedback,
    /// the haptic cousin of the shift/caps-lock morph. Only actually buzzes with
    /// Full Access granted; a silent no-op otherwise (never crashes).
    private let dragHaptic = UIImpactFeedbackGenerator(style: .rigid)

    /// Keep a just-released key visually pressed for `lingerDuration`, then clear
    /// it — so a quick tap blooms fully before springing back.
    private func startLinger(_ id: String) {
        guard lingerDuration > 0 else { return }
        lingering.insert(id)
        lingerTasks[id]?.cancel()
        lingerTasks[id] = Task { @MainActor in
            try? await Task.sleep(for: .seconds(lingerDuration))
            if Task.isCancelled { return }
            lingering.remove(id)
            lingerTasks[id] = nil
            recomputePressed()
        }
    }

    /// Cancel a pending fade-out — the key was pressed again before it expired.
    private func cancelLinger(_ id: String) {
        lingerTasks[id]?.cancel()
        lingerTasks[id] = nil
        lingering.remove(id)
    }

    // MARK: - Backspace auto-repeat

    private var repeatTask: Task<Void, Never>?
    private var spaceSteps = 0
    private static let cursorStride: CGFloat = 10
    /// Upward travel (pt) before a drag-up key (123→emoji) fires.
    private static let dragUpThreshold: CGFloat = 24
    /// Keys whose `onDragUp` has fired for the current touch, so `touchUp` skips
    /// their tap action. Cleared on up/cancel.
    private var dragUpFired: Set<String> = []

    private func startRepeating(_ spec: KeySpec) {
        stopRepeating()
        repeatTask = Task { @MainActor in
            spec.action()                                    // first delete now
            try? await Task.sleep(for: .milliseconds(450))   // hold delay
            var interval = 110
            while !Task.isCancelled {
                onPressDown()                               // clink on each repeat
                spec.action()
                deleteTick &+= 1                            // bounce the glyph
                interval = max(40, interval - 6)           // accelerate
                try? await Task.sleep(for: .milliseconds(interval))
            }
        }
    }

    private func stopRepeating() {
        repeatTask?.cancel()
        repeatTask = nil
    }
}

// MARK: - Frame publishing

/// Every key publishes its bounds under this key so the grid can build a
/// hit-test registry. Unlike the glyph preference, this includes *every* key
/// (shift, space, function keys) — all of them must be touchable.
struct KeyFrameKey: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

// MARK: - The multitouch UIView

/// A bare `UIView` that captures every touch over the key grid and routes it
/// through `KeyTouchRouter`. `isMultipleTouchEnabled` is the whole point — it
/// gets independent `touchesBegan`/`Moved`/`Ended` for each finger, which is
/// what SwiftUI's per-view gestures could not do.
@MainActor
final class KeyGridTouchView: UIView {
    let router: KeyTouchRouter
    /// keyID + start point bound to each live touch, so moves/ends route to the
    /// key the finger originally landed on.
    private var bindings: [ObjectIdentifier: (id: String, start: CGPoint)] = [:]

    init(router: KeyTouchRouter) {
        self.router = router
        super.init(frame: .zero)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            let p = t.location(in: self)
            guard let id = router.key(at: p) else { continue }
            bindings[ObjectIdentifier(t)] = (id, p)
            router.touchDown(id: id)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            guard let b = bindings[ObjectIdentifier(t)] else { continue }
            let p = t.location(in: self)
            router.touchMoved(id: b.id, translationX: p.x - b.start.x,
                              translationY: p.y - b.start.y)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            guard let b = bindings.removeValue(forKey: ObjectIdentifier(t)) else { continue }
            router.touchUp(id: b.id)
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            guard let b = bindings.removeValue(forKey: ObjectIdentifier(t)) else { continue }
            router.touchCancelled(id: b.id)
        }
    }
}

/// Hosts `KeyGridTouchView` and feeds it the resolved key frames each layout.
struct MultiTouchSurface: UIViewRepresentable {
    let router: KeyTouchRouter
    let frames: [String: CGRect]
    let resolveSpec: (String) -> KeySpec?
    let onPressDown: () -> Void
    let lingerDuration: TimeInterval
    let hitboxScale: Double

    func makeUIView(context: Context) -> KeyGridTouchView {
        let v = KeyGridTouchView(router: router)
        router.update(frames: frames, resolveSpec: resolveSpec,
                      onPressDown: onPressDown, lingerDuration: lingerDuration,
                      hitboxScale: hitboxScale)
        return v
    }

    func updateUIView(_ uiView: KeyGridTouchView, context: Context) {
        router.update(frames: frames, resolveSpec: resolveSpec,
                      onPressDown: onPressDown, lingerDuration: lingerDuration,
                      hitboxScale: hitboxScale)
    }
}
