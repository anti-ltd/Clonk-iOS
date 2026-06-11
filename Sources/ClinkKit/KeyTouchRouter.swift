/**
 Multitouch routing for the key grid. `KeyTouchRouter` / `KeyGridTouchView` maps
 raw `UITouch` events onto key IDs and callbacks. Also defines `MultiTouchSurface`
 (UIViewRepresentable bridge) and the `KeyFrameKey` / `BarHitboxKey` preference keys.
 */
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
/// One key's observable press state. Each `KeyView` reads ONLY its own instance
/// (plus, on liquid glass, its `neighborTick`), so a press/release invalidates
/// the pressed key and — on glass — its immediate neighbours, never the whole
/// grid. `@Observable` tracks per *property*, not per key: the old shared
/// `pressed: Set` / `tapTicks` dictionary re-rendered all ~35 keys (glass
/// effects × preference closures) several times per keystroke, which on-device
/// cost the frame that should have shown the press bloom — taps felt dropped.
@MainActor
@Observable
public final class KeyPressState {
    /// Held by any finger, or lingering after release (see `startLinger`).
    public internal(set) var isPressed = false
    /// Bumped on *every* touch-down — drives the additive "tap pulse" each
    /// `KeyView` plays to confirm a press.
    ///
    /// `isPressed` can't do this job: the press bloom is sprung on it changing,
    /// but pressing the same key twice in quick succession (the second `l` in
    /// "tell") re-fires inside the linger window, so the key never leaves
    /// pressed and the bloom never re-animates — the second tap reads as
    /// dropped even though the character *was* inserted. This tick changes on
    /// every landing, so the pulse fires every time regardless of press state.
    public internal(set) var tapTick = 0
    /// Bumped whenever an ADJACENT key's press flips. Liquid-glass keys read
    /// this so they re-evaluate when a neighbour is pressed or released —
    /// `GlassEffectContainer`'s liquid merge only refreshes when the views on
    /// BOTH sides of the blend re-evaluate, and the merge is strictly local,
    /// so the neighbours are exactly the set that needs waking. Solid keys
    /// never read it, so the writes cost nothing there.
    public internal(set) var neighborTick = 0
    /// Live swipe-ripple swell for this key, `0` (rest) … `1` (finger
    /// dead-centre), pushed by the router on each glide sample (see
    /// `updateSwipeTrail`). Per-key — and only written when the value actually
    /// moved — so a sample re-renders the handful of keys under and around the
    /// finger, not the whole grid (which is what made the ripple drop frames).
    public internal(set) var bulge: CGFloat = 0
}

@MainActor
@Observable
public final class KeyTouchRouter {
    /// Per-key observable press state, created on first access. The dictionary
    /// itself is deliberately NOT observed (only each `KeyPressState`'s own
    /// properties are), so lazily inserting a state — or flipping one key's
    /// press — never invalidates any other key's view.
    @ObservationIgnored private var keyStates: [String: KeyPressState] = [:]

    /// This key's press state — `KeyView` reads its pressed/tap-pulse out of
    /// here, written by the touch surface during touch events.
    public func state(for id: String) -> KeyPressState {
        if let s = keyStates[id] { return s }
        let s = KeyPressState()
        keyStates[id] = s
        return s
    }

    /// Keys currently held down (by any finger) or lingering — the union of all
    /// active touches, so two fingers on one key keep it lit until both lift.
    /// Internal diffing state only (deliberately unobserved): views are driven
    /// by the per-key `KeyPressState`s, plus `neighborTick` for the glass merge.
    @ObservationIgnored public private(set) var pressed: Set<String> = []

    /// Space-bar trackpad: live horizontal drag offset (drives the glass warp)
    /// and whether the current space touch has crossed into cursor-drag mode.
    public private(set) var spaceDragX: CGFloat = 0
    public private(set) var spaceCursorActive = false

    /// Bumped on every backspace auto-repeat so the delete glyph bounces.
    public private(set) var deleteTick = 0
    /// True while a backspace swipe-to-delete-word is engaged, so the delete glyph
    /// can show a distinct "eating words" animation (emphasised + leaning) for the
    /// duration of the drag. Cleared on lift/cancel.
    public private(set) var deleteWordSwipeActive = false

    // MARK: - Swipe / glide typing
    //
    // A swipe is a single finger that lands on a letter and slides across the
    // grid; on lift the traced path is decoded into a word. The first letter is
    // still typed instantly on touch-down (so plain tapping is unchanged); when
    // the slide engages, the host deletes that stray letter and, on lift, inserts
    // the decoded word. `KeyGridTouchView` owns the per-touch path capture and the
    // engage decision — the router holds the published render state and the host
    // callbacks. See `beginSwipe` / `endSwipe`.

    /// True while a swipe trace is engaged (past the tap threshold). Drives the
    /// trail overlay; no key types while it's set for the swiping finger.
    public private(set) var swipeActive = false
    /// The live finger trail (in the touch surface's local coordinate space, the
    /// same space the key `frames` live in). Published for the trail overlay.
    public private(set) var swipeTrail: [CGPoint] = []

    // MARK: - Accent long-press session
    //
    // Holding a letter key (when accent popups are on) raises a bar of diacritic
    // variants; sliding highlights one, releasing commits it — the same
    // interaction model as the emoji skin-tone picker. While a session is live no
    // other key types. `accentKeyID` names the held key (the canvas anchors the
    // bar over it and `KeyView` publishes that key's frame); `accentOptions` is
    // the base glyph + its variants; `accentIndex` is the highlighted swatch.

    /// The key whose accent bar is currently showing, or nil when no session is
    /// live. `KeyView` publishes this key's frame so the canvas can anchor the bar.
    public private(set) var accentKeyID: String?
    /// The bar's options: base glyph first, then its diacritic variants.
    public private(set) var accentOptions: [String] = []
    /// The highlighted (and on-release committed) option index.
    public private(set) var accentIndex: Int = 0

    public init() {}

    // MARK: - Registry (pushed in from the layout each pass)
    //
    // Only the *frames* flow through SwiftUI preferences (cheap, Equatable). The
    // specs — which carry non-Equatable action closures — are fetched on demand
    // via `resolveSpec` at touch time, so they always reflect the current plane /
    // shift without round-tripping closures through the preference system.

    /// keyID → frame in the grid's coordinate space. Unobserved: it feeds
    /// hit-testing and the bulge/neighbour computations, never a view directly.
    @ObservationIgnored fileprivate var frames: [String: CGRect] = [:]
    /// keyID → the IDs of adjacent keys (edge gap ≤ `neighborGap` on both
    /// axes — same-row neighbours, the rows above/below, and diagonals).
    /// Rebuilt only when `frames` actually changes. Drives the glass-merge
    /// `neighborTick` nudges in `recomputePressed`.
    @ObservationIgnored private var neighbors: [String: [String]] = [:]
    /// Maximum edge-to-edge gap (pt) for two keys to count as neighbours.
    /// Comfortably above key/row spacing (~6pt) so diagonals qualify, and well
    /// below a key width so next-but-one keys don't.
    private let neighborGap: CGFloat = 18
    /// Swipe-ripple config (pushed from settings each layout pass): whether the
    /// glide should swell keys at all, and the influence radius in key-sizes.
    @ObservationIgnored fileprivate var swipeMorphEnabled: Bool = false
    @ObservationIgnored fileprivate var swipeMorphRadius: CGFloat = 1.0
    /// keyID → its current spec. Resolved on demand at touch time so it always
    /// reads the *live* plane/shift (a sticky-shift flip mid-burst must affect the
    /// very next touch). The canvas memoizes the underlying build, so this closure
    /// is an O(1) dictionary lookup in the common case — see `currentKeySpecs`.
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
    /// Adaptive hitboxes on: bias hit-testing toward the predicted next letter by
    /// flexing each letter key's frame (see `key(at:)` / `AdaptiveHitbox`).
    fileprivate var adaptiveEnabled: Bool = false
    /// Adaptive tuning knobs (see `AdaptiveHitbox` / `KeyboardSettings`).
    fileprivate var adaptiveGrow: Double = AdaptiveHitbox.defaultGrow
    fileprivate var adaptiveShrink: Double = AdaptiveHitbox.defaultShrink
    fileprivate var adaptivePredictionWeight: Double = AdaptiveHitbox.defaultPredictionWeight
    fileprivate var adaptivePredictAtWordStart: Bool = true
    /// The last letter typed (lowercased), driving the next-letter prediction.
    /// nil at a word boundary (after space / function keys). Published so the
    /// debug overlay can mirror the same prediction.
    public private(set) var predictedFrom: Character?
    /// Points of horizontal space-bar travel per one-character cursor move, and
    /// the threshold to enter cursor-trackpad mode. Larger = less sensitive (see
    /// `KeyboardSettings.spaceCursorStride`).
    fileprivate var cursorStride: CGFloat = 10
    /// Backspace swipe-to-delete-word: leftward travel (pt) before the gesture
    /// engages (deleting the first word and stopping char-repeat), then the travel
    /// per additional word as the finger keeps gliding left. User-tunable via
    /// `KeyboardSettings.deleteWordSwipeEngage` / `…Stride`.
    fileprivate var deleteWordEngage: CGFloat = 24
    fileprivate var deleteWordStride: CGFloat = 42
    /// Seconds the space bar must be held before cursor mode can engage (0 = instant).
    fileprivate var cursorActivationDelay: TimeInterval = 0
    /// Characters jumped per vertical "line" step when a space drag moves up/down
    /// — the cursor API only moves by character offset, so a line is an estimate
    /// (see `touchMoved`). User-tunable via `KeyboardSettings.cursorLineStride`.
    fileprivate var cursorLineStride: Int = 30
    /// "Combined" cursor mode: every touch (except the next-keyboard globe, so the
    /// user is never trapped) is rebound to the space bar, so dragging anywhere
    /// drives the space cursor pad and the bar morphs — while no key ever types.
    /// Read by `KeyGridTouchView` to pick the binding target.
    fileprivate var cursorCombined: Bool = false
    fileprivate var repeatHoldDelay: TimeInterval = 0.450
    fileprivate var repeatInitialInterval: Int = 110
    fileprivate var repeatMinInterval: Int = 40
    fileprivate var repeatAccelStep: Int = 6
    /// Whether holding a letter key reveals its accent variants.
    fileprivate var accentsEnabled: Bool = false
    /// Width of the touch surface (≈ keyboard width), for clamping the accent bar
    /// on-screen identically to the canvas renderer.
    fileprivate var surfaceWidth: CGFloat = 0
    /// How long a letter must be held (still) before its accent bar appears.
    fileprivate var accentHoldDelay: TimeInterval = 0.5
    /// Finger travel (pt) that cancels a pending accent hold — past this it's a
    /// swipe, not a still press.
    fileprivate var accentMoveCancel: CGFloat = 12
    /// Upward travel (pt) before a drag-up key (123→panel) fires.
    fileprivate var dragUpThreshold: CGFloat = 24
    /// Swipe/glide typing on: a slide across the letters is decoded into a word.
    fileprivate var swipeEnabled: Bool = false
    /// Fired the instant a swipe engages — the host deletes the first letter that
    /// was typed on touch-down (the decoded word replaces it on lift).
    fileprivate var onSwipeStart: () -> Void = {}
    /// Fired on lift with the traced path and the current letter-key centres — the
    /// host decodes a word and inserts it.
    fileprivate var onSwipeEnd: ([CGPoint], [Character: CGPoint]) -> Void = { _, _ in }

    fileprivate func update(frames: [String: CGRect],
                            resolveSpec: @escaping (String) -> KeySpec?,
                            onPressDown: @escaping () -> Void,
                            lingerDuration: TimeInterval,
                            minPressVisible: TimeInterval,
                            hitboxScale: Double,
                            adaptiveEnabled: Bool,
                            adaptiveGrow: Double,
                            adaptiveShrink: Double,
                            adaptivePredictionWeight: Double,
                            adaptivePredictAtWordStart: Bool,
                            cursorStride: CGFloat,
                            cursorActivationDelay: TimeInterval,
                            cursorLineStride: Int,
                            cursorCombined: Bool,
                            repeatHoldDelay: TimeInterval,
                            repeatInitialInterval: Int,
                            repeatMinInterval: Int,
                            repeatAccelStep: Int,
                            accentsEnabled: Bool,
                            accentHoldDelay: TimeInterval,
                            accentMoveCancel: CGFloat,
                            deleteWordEngage: CGFloat,
                            deleteWordStride: CGFloat,
                            dragUpThreshold: CGFloat,
                            surfaceWidth: CGFloat,
                            swipeEnabled: Bool,
                            swipeMorphEnabled: Bool,
                            swipeMorphRadius: CGFloat,
                            onSwipeStart: @escaping () -> Void,
                            onSwipeEnd: @escaping ([CGPoint], [Character: CGPoint]) -> Void) {
        // Frames change only on real layout changes (resize, plane padding, …);
        // skipping the no-op write keeps the neighbour map rebuild off the
        // common per-render update path.
        if frames != self.frames {
            self.frames = frames
            rebuildNeighbors()
        }
        self.resolveSpec = resolveSpec
        self.onPressDown = onPressDown
        self.lingerDuration = lingerDuration
        self.minPressVisible = minPressVisible
        self.hitboxScale = hitboxScale
        self.adaptiveEnabled = adaptiveEnabled
        self.adaptiveGrow = adaptiveGrow
        self.adaptiveShrink = adaptiveShrink
        self.adaptivePredictionWeight = adaptivePredictionWeight
        self.adaptivePredictAtWordStart = adaptivePredictAtWordStart
        self.cursorStride = cursorStride
        self.cursorActivationDelay = cursorActivationDelay
        self.cursorLineStride = cursorLineStride
        self.cursorCombined = cursorCombined
        self.repeatHoldDelay = repeatHoldDelay
        self.repeatInitialInterval = repeatInitialInterval
        self.repeatMinInterval = repeatMinInterval
        self.repeatAccelStep = repeatAccelStep
        self.accentsEnabled = accentsEnabled
        self.accentHoldDelay = accentHoldDelay
        self.accentMoveCancel = accentMoveCancel
        self.deleteWordEngage = deleteWordEngage
        self.deleteWordStride = deleteWordStride
        self.dragUpThreshold = dragUpThreshold
        self.surfaceWidth = surfaceWidth
        self.swipeEnabled = swipeEnabled
        self.swipeMorphEnabled = swipeMorphEnabled
        self.swipeMorphRadius = swipeMorphRadius
        self.onSwipeStart = onSwipeStart
        self.onSwipeEnd = onSwipeEnd
    }

    /// Recompute the adjacency map from the current frames: two keys are
    /// neighbours when their edge-to-edge gap is at most `neighborGap` on both
    /// axes. O(n²) over ~35 keys, and only on real layout changes — trivial.
    private func rebuildNeighbors() {
        var map: [String: [String]] = [:]
        let entries = Array(frames)
        for i in entries.indices {
            for j in (i + 1)..<entries.count {
                let a = entries[i].value, b = entries[j].value
                let dx = max(b.minX - a.maxX, a.minX - b.maxX, 0)
                let dy = max(b.minY - a.maxY, a.minY - b.maxY, 0)
                if dx <= neighborGap, dy <= neighborGap {
                    map[entries[i].key, default: []].append(entries[j].key)
                    map[entries[j].key, default: []].append(entries[i].key)
                }
            }
        }
        neighbors = map
    }

    // MARK: - Swipe session (driven by KeyGridTouchView)

    /// Whether swipe typing is on (read by the touch view to decide whether to
    /// track a path at all).
    fileprivate var isSwipeEnabled: Bool { swipeEnabled }

    /// True while an accent bar is up (`accentKeyID`) or its hold is still pending
    /// (`accentPendingID`). Swipe tracking checks this so the two gestures stay
    /// mutually exclusive: sliding up to the accent bar crosses other letter keys
    /// and would otherwise engage a swipe at the same time as the diacritic pick,
    /// double-mutating the document (the "mañ → mñnm" bug). A genuine drag-to-swipe
    /// is unaffected — it first trips `accentMoveCancel`, clearing the pending hold
    /// before this would block it.
    fileprivate var accentActive: Bool { accentKeyID != nil || accentPendingID != nil }

    /// Whether a key types a letter on the current plane — gates which keys a
    /// swipe may start on / engage into.
    fileprivate func isLetterKey(_ id: String) -> Bool { letterOfKey(id) != nil }

    /// Lowercased letter → its key's centre, in the frames' coordinate space.
    /// The decode geometry runs against this map.
    fileprivate func letterCenters() -> [Character: CGPoint] {
        var m: [Character: CGPoint] = [:]
        for (id, f) in frames where letterOfKey(id) != nil {
            m[letterOfKey(id)!] = CGPoint(x: f.midX, y: f.midY)
        }
        return m
    }

    /// Engage the swipe: the host drops the stray first letter. Idempotent.
    fileprivate func beginSwipe() {
        guard !swipeActive else { return }
        swipeActive = true
        onSwipeStart()
    }

    /// Publish the live trail for the overlay, and PUSH the ripple swell into
    /// each affected key's own `KeyPressState.bulge` — keys never read the
    /// trail themselves. Pulling (every key reading `swipeTrail` per sample)
    /// re-rendered the entire grid 60×/s during a glide, which is exactly what
    /// made the ripple drop frames; pushing only touches the keys whose swell
    /// actually moved (the handful around the finger).
    fileprivate func updateSwipeTrail(_ points: [CGPoint]) {
        swipeTrail = points
        if swipeMorphEnabled { pushBulges(tip: points.last) }
    }

    /// Write each key's ripple swell, `0` (rest) … `1` (finger dead-centre),
    /// falling off smoothly to `0` just past `swipeMorphRadius` key-sizes — a
    /// travelling ripple, not the whole grid pulsing. `tip: nil` settles every
    /// key back to rest. Writes are skipped when the value barely moved, so
    /// keys far from the finger are never invalidated at all.
    private func pushBulges(tip: CGPoint?) {
        for (id, f) in frames {
            var target: CGFloat = 0
            if let tip {
                let d = hypot(tip.x - f.midX, tip.y - f.midY)
                let radius = max(f.width, f.height) * swipeMorphRadius
                if radius > 0, d < radius {
                    let t = 1 - d / radius
                    target = t * t   // ease-in falloff — gentle at the fringe, peaks under the finger
                }
            }
            let s = state(for: id)
            if abs(s.bulge - target) > 0.004 || (target == 0 && s.bulge != 0) {
                s.bulge = target
            }
        }
    }

    /// Finish the swipe: hand the path + letter centres to the host to decode and
    /// insert. No-op if not engaged.
    fileprivate func endSwipe(path: [CGPoint]) {
        guard swipeActive else { return }
        swipeActive = false
        swipeTrail = []
        pushBulges(tip: nil)   // every swollen key springs back to rest
        onSwipeEnd(path, letterCenters())
    }

    /// Abandon the swipe with no commit (touch cancelled).
    fileprivate func cancelSwipe() {
        guard swipeActive else { return }
        swipeActive = false
        swipeTrail = []
        pushBulges(tip: nil)
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
    ///
    /// Rect distance alone still isn't enough at the *sides*: the home row is
    /// indented (the `A`…`L` row sits inset from the edges), so a tap near the
    /// left/right edge at the home row's vertical level is horizontally far from
    /// `A`/`L` but vertically in their band — while the un-indented row above/below
    /// reaches closer to the edge. By plain Euclid that neighbour row wins and
    /// `A`/`L` never light up (the reported "tap close on the edge" miss). So we
    /// tier the ranking: a key whose vertical band *contains* the point always
    /// beats one that doesn't, and only within a tier does distance decide. A touch
    /// at a row's level therefore binds to that row's nearest key (the indented
    /// `A`/`L` claim their whole side margin); full rect distance still resolves the
    /// vertical gaps *between* rows, where no band contains the point.
    fileprivate func key(at point: CGPoint) -> String? {
        // Adaptive: each letter key's frame is flexed by its predicted likelihood
        // (the previous letter drives the prediction). Non-letter keys stay at
        // their plain size. With adaptive off the map is empty → every factor is
        // 1.0 and this reduces to the original nearest-frame routing.
        let factors: [Character: Double]
        if adaptiveEnabled, predictedFrom != nil || adaptivePredictAtWordStart {
            factors = AdaptiveHitbox.factorMap(prev: predictedFrom,
                                               grow: adaptiveGrow,
                                               shrink: adaptiveShrink,
                                               predictionWeight: adaptivePredictionWeight)
        } else {
            factors = [:]
        }
        var best: String?
        var bestDist = CGFloat.greatestFiniteMagnitude
        var bestFactor = 0.0
        var bestInBand = false
        for (id, f) in frames {
            var factor = 1.0
            if adaptiveEnabled, let c = letterOfKey(id) { factor = factors[c] ?? 1.0 }
            let sf = scaledFrame(f, extra: factor)
            let dx = max(sf.minX - point.x, 0, point.x - sf.maxX)
            let dy = max(sf.minY - point.y, 0, point.y - sf.maxY)
            // In-band = the point sits within this key's vertical span. Such a key
            // always outranks one that isn't, so an edge/inset tap at a row's level
            // can't jump to a closer-by-Euclid neighbour row (the indented A/L case).
            let inBand = dy == 0
            let d = dx * dx + dy * dy
            let better: Bool
            if inBand != bestInBand {
                better = inBand
            } else if d != bestDist {
                better = d < bestDist
            } else {
                // On a tie (overlapping enlarged frames both contain the point), the
                // more-likely key wins — otherwise dictionary order would decide.
                better = factor > bestFactor
            }
            if better {
                bestInBand = inBand; bestDist = d; best = id; bestFactor = factor
            }
        }
        return best
    }

    private func scaledFrame(_ f: CGRect, extra: Double = 1.0) -> CGRect {
        let s = hitboxScale * extra
        guard s != 1.0 else { return f }
        let w = f.width * CGFloat(s)
        let h = f.height * CGFloat(s)
        return CGRect(x: f.midX - w / 2, y: f.midY - h / 2, width: w, height: h)
    }

    /// The lowercased letter a key types, or nil for space / function / digit /
    /// symbol keys (which don't participate in adaptive sizing).
    private func letterOfKey(_ id: String) -> Character? {
        guard let spec = resolveSpec(id), spec.kind == .character, !spec.isSpace,
              case let .text(s) = spec.label, let ch = s.lowercased().first, ch.isLetter
        else { return nil }
        return ch
    }

    // MARK: - Per-touch lifecycle (called by the UIView)
    //
    // Each touch is bound to the key it lands on for its whole life — exactly how
    // the old per-key gesture behaved, just now genuinely multitouch.

    fileprivate func touchDown(id: String, localPoint: CGPoint = .zero, windowPoint: CGPoint = .zero) {
        guard let spec = resolveSpec(id) else { return }
        // An accent bar is up — lock out every other key so a stray finger can't
        // type while picking a diacritic (matches the skin-tone picker).
        if accentKeyID != nil { return }
        // Combined cursor mode: once the space cursor is engaged, every other key
        // goes inert — a stray second finger can't type mid-drag. The keyboard is
        // fully normal otherwise (and until the drag engages).
        if cursorCombined, spaceCursorActive, !spec.isSpace { return }
        // Window↔surface offset, recomputed each touch-down (constant for the
        // life of a touch): used to map the dragging finger's window point back
        // into the touch surface's local space for accent-swatch hit-testing.
        viewOrigin = CGPoint(x: windowPoint.x - localPoint.x, y: windowPoint.y - localPoint.y)
        heldCounts[id, default: 0] += 1
        pressStart[id] = Date()     // for the minimum-visible-press floor (see startLinger)
        cancelLinger(id)            // pressed again → stop any pending fade-out
        recomputePressed()
        state(for: id).tapTick &+= 1   // fire the per-press tap pulse
        onPressDown()

        // Remember the letter just typed so the *next* touch can predict from it.
        // Space / function keys reset to a word boundary (nil → unigram prior).
        if spec.kind == .character, !spec.isSpace, case let .text(g) = spec.label,
           let ch = g.lowercased().first, ch.isLetter {
            predictedFrom = ch
        } else {
            predictedFrom = nil
        }

        switch spec.kind {
        case .character:
            // The space bar is a character key but inserts on *release* (a tap),
            // because a press-and-drag is the cursor trackpad instead. Every other
            // character commits instantly on touch-down.
            if spec.isSpace {
                spaceCursorActive = false
                spaceDragX = 0
                spaceSteps = 0
                spaceVSteps = 0
                spaceCursorReadyTask?.cancel()
                if cursorActivationDelay > 0 {
                    spaceCursorReady = false
                    spaceCursorReadyTask = Task { @MainActor in
                        try? await Task.sleep(for: .seconds(cursorActivationDelay))
                        if !Task.isCancelled { spaceCursorReady = true }
                    }
                } else {
                    spaceCursorReady = true
                }
            } else {
                // Commit the character on the NEXT runloop turn, not inside the
                // touch event. The insert is a cross-process proxy call (and, on
                // a word terminator, runs the synchronous autocorrect check) —
                // doing it here held up the render commit that STARTS the press
                // bloom, so by the time frames appeared the spring was half done
                // and the key seemed to snap. Deferring lets the press visual
                // land on the very next frame; FIFO ordering on the main queue
                // keeps the document text in exact key order, and the block runs
                // before any later touch event can be delivered.
                let action = spec.action
                DispatchQueue.main.async { action() }
                // Schedule the accent bar if this key has variants and the
                // feature is on. The base is already typed (above); a hold then
                // raises the bar, and releasing on a variant replaces it.
                if (accentsEnabled || spec.accentsAlwaysOn), !spec.accents.isEmpty {
                    scheduleAccentHold(id: id, options: spec.accents)
                }
            }
        case .function:
            if spec.isRepeatable {
                startRepeating(spec)
            }
            // Prime backspace swipe-to-delete-word tracking (the only key with an
            // `onDeleteWord` hook). A later leftward drag engages it; see `touchMoved`.
            if spec.onDeleteWord != nil {
                deleteWordKeyID = id
                deleteWordEngaged = false
                deleteWordSteps = 0
            }
            // Other function keys (shift, plane toggle, globe, return) fire on
            // release — see `touchUp`.
        }
    }

    fileprivate func touchMoved(id: String, translationX: CGFloat, translationY: CGFloat,
                                windowPoint: CGPoint) {
        // Accent bar is up for this key: slide highlights a swatch (no other key
        // behaviour applies). Independent of which `spec` is current.
        if accentKeyID == id {
            accentIndex = accentSwatchIndex(forWindowX: windowPoint.x)
            return
        }
        // Still waiting on the hold for this key: a real drag means the user isn't
        // holding still — cancel the pending bar so it never pops mid-swipe.
        if accentPendingID == id,
           hypot(translationX, translationY) > accentMoveCancel {
            cancelAccentHold()
        }

        guard let spec = resolveSpec(id) else { return }

        // Backspace swipe-to-delete-word: a leftward drag deletes whole words.
        if let deleteWord = spec.onDeleteWord, deleteWordKeyID == id {
            if !deleteWordEngaged {
                // Engage only on a clearly-leftward, horizontal-dominant drag past
                // the threshold — so holding (then a vertical wiggle) still
                // auto-repeats char-by-char as before.
                guard translationX <= -deleteWordEngage,
                      abs(translationX) > abs(translationY) else { return }
                deleteWordEngaged = true
                deleteWordSwipeActive = true     // drive the delete-glyph animation
                stopRepeating()                 // switch from char-repeat to word-delete
                deleteWordOriginX = translationX
                deleteWordSteps = 0
                dragHaptic.impactOccurred()
                deleteWord()
                deleteTick &+= 1
                return
            }
            // Each further stride leftward removes another word.
            let step = Int(((deleteWordOriginX - translationX) / deleteWordStride).rounded(.towardZero))
            if step > deleteWordSteps {
                for _ in 0..<(step - deleteWordSteps) { deleteWord(); deleteTick &+= 1 }
                deleteWordSteps = step
                dragHaptic.impactOccurred()
            }
            return
        }

        // Drag-up keys (the 123 → panel-picker gesture): once the finger has
        // travelled far enough upward, fire once and mark the touch consumed so
        // `touchUp` skips the normal tap action. Mirrors the space-bar trackpad's
        // tap-vs-drag split.
        if spec.onDragUp != nil, !dragUpFired.contains(id),
           translationY < -dragUpThreshold {
            dragUpFired.insert(id)
            // The key's press is cleared so it doesn't stick "pressed" while the
            // picker is up. (We do NOT clear it via canvas swap-out anymore — the
            // keys stay on screen behind a popover, so the touch keeps flowing.)
            clearPress(id)
            dragHaptic.impactOccurred()
            spec.onDragUp?()
            spec.onDragUpMove?(windowPoint)
            return
        }

        // After a drag-up fired, keep reporting the finger so the canvas can track
        // which picker row it's over.
        if dragUpFired.contains(id) {
            spec.onDragUpMove?(windowPoint)
            return
        }

        guard spec.isSpace else { return }
        // The bar's lean tracks the finger from the FIRST move, before the cursor
        // even engages — otherwise it sits frozen through the dead zone and then
        // lurches sideways the instant the threshold is crossed, which reads as a
        // visual stutter (it "initiated" on press, froze, then jumped). Publishing
        // the live translation every move keeps the lean continuous; the shrink
        // (gated on `spaceCursorActive` in the view) springs in at engage.
        spaceDragX = translationX
        // Past the stride threshold the space touch becomes a 2-D cursor pad; a
        // plain tap (no real movement) still types a space on release. Either axis
        // crossing the stride engages — same for the space-bar slide and the
        // trackpad panel; the panel is only a visual difference (see canvas).
        if !spaceCursorActive {
            guard spaceCursorReady,
                  abs(translationX) > cursorStride || abs(translationY) > cursorStride else { return }
            // Engage, and rebaseline the stepping to this exact point so the first
            // move lands the instant we engage and every step after costs exactly
            // one stride (measuring from the touch origin instead made the first
            // move's travel vary with how far a fast finger overshot).
            spaceCursorActive = true
            spaceDragOrigin = translationX
            spaceDragOriginY = translationY
            spaceSteps = 0
            spaceVSteps = 0
            // Begin moving right at the threshold, on whichever axis crossed first
            // (dominant axis), so a mostly-vertical engage doesn't jump a stray
            // character sideways and vice-versa.
            if abs(translationX) >= abs(translationY) {
                spec.onCursorMove?(translationX > 0 ? 1 : -1)
            } else {
                spec.onCursorMove?(translationY > 0 ? cursorLineStride : -cursorLineStride)
            }
        }
        // Horizontal: one character per stride.
        let step = Int(((translationX - spaceDragOrigin) / cursorStride).rounded(.towardZero))
        if step != spaceSteps {
            spec.onCursorMove?(step - spaceSteps)
            spaceSteps = step
        }
        // Vertical: one "line" (a `cursorLineStride`-character jump) per coarser
        // stride, so a small wobble doesn't fling the cursor across lines. Down
        // (positive Y) moves the cursor forward.
        let vStride = cursorStride * 2
        let vStep = Int(((translationY - spaceDragOriginY) / vStride).rounded(.towardZero))
        if vStep != spaceVSteps {
            spec.onCursorMove?((vStep - spaceVSteps) * cursorLineStride)
            spaceVSteps = vStep
        }
    }

    fileprivate func touchUp(id: String, windowPoint: CGPoint) {
        releaseHold(id)
        if deleteWordKeyID == id { deleteWordKeyID = nil; deleteWordEngaged = false; deleteWordSwipeActive = false }
        // Pending accent hold that never fired (a quick tap) — drop it.
        if accentPendingID == id { cancelAccentHold() }
        // An accent bar is up for this key: commit the highlighted variant and
        // tear the session down. `onAccentCommit` replaces the base only when the
        // pick differs from it (releasing on the base is a no-op — already typed).
        if accentKeyID == id {
            let spec = resolveSpec(id)
            if accentOptions.indices.contains(accentIndex) {
                spec?.onAccentCommit?(accentOptions[accentIndex])
            }
            endAccentSession()
            return
        }
        guard let spec = resolveSpec(id) else { return }

        // A drag-up gesture already fired and consumed this touch — don't also run
        // the key's tap action (e.g. don't switch to numbers after opening the
        // picker). Report the release so the canvas selects/dismisses.
        if dragUpFired.remove(id) != nil {
            spec.onDragUpEnd?(windowPoint)
            return
        }

        switch spec.kind {
        case .character:
            if spec.isSpace {
                spaceCursorReadyTask?.cancel()
                spaceCursorReadyTask = nil
                spaceCursorReady = true
                if spaceCursorActive {
                    // A cursor drag inserted nothing, so it must not bloom on
                    // release: the linger started by `releaseHold` would keep the
                    // bar "pressed" and pop it from its shrunk 0.9 up through the
                    // press-bloom (1.04) before settling — a visible glitch. Drop
                    // the press now so it springs straight back to full size.
                    clearPress(id)
                } else {
                    // Tap → space, deferred like the character keys: the space
                    // is the terminator that runs the synchronous autocorrect
                    // (UITextChecker — tens of ms on a miss), which would
                    // otherwise stall the release animation's first frames.
                    let action = spec.action
                    DispatchQueue.main.async { action() }
                }
                spaceCursorActive = false
                spaceDragX = 0
                spaceSteps = 0
                spaceVSteps = 0
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
        if deleteWordKeyID == id { deleteWordKeyID = nil; deleteWordEngaged = false; deleteWordSwipeActive = false }
        if accentPendingID == id { cancelAccentHold() }
        if accentKeyID == id { endAccentSession() }   // abandon the pick, type nothing extra
        let wasDragUp = dragUpFired.remove(id) != nil
        guard let spec = resolveSpec(id) else { return }
        // Cancelled mid drag-up → dismiss the picker (off-screen point = no row).
        if wasDragUp { spec.onDragUpEnd?(CGPoint(x: -1, y: -1)) }
        if spec.isRepeatable { stopRepeating() }
        if spec.isSpace {
            spaceCursorReadyTask?.cancel()
            spaceCursorReadyTask = nil
            spaceCursorReady = true
            if spaceCursorActive { clearPress(id) }   // no post-drag bloom (see touchUp)
            spaceCursorActive = false
            spaceDragX = 0
            spaceSteps = 0
            spaceVSteps = 0
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
    /// Touch-down timestamp per key, used to floor how long a press stays visible.
    private var pressStart: [String: Date] = [:]
    /// Minimum time a key reads pressed after touch-down, no matter how fast it's
    /// released or cancelled. Screen-edge taps in the keyboard extension are
    /// deferred by iOS's edge system-gestures and then delivered as a near-instant
    /// down+up, collapsing the press to a sub-frame flicker — the letter types but
    /// `A`/`L` never visibly highlight (the reported edge-tap miss). Guaranteeing a
    /// minimum on-screen press makes an edge tap bloom like a held centre tap. The
    /// post-release `lingerDuration` fade rides on top of this; the floor only
    /// raises the total when the press itself was briefer than the floor. Pushed in
    /// from `KeyboardSettings.minPressVisible` each layout pass (see `update`).
    fileprivate var minPressVisible: TimeInterval = 0.09

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
        guard next != pressed else { return }
        let changed = next.symmetricDifference(pressed)
        for id in changed {
            state(for: id).isPressed = next.contains(id)
            // Nudge the neighbours so glass keys adjacent to the press
            // re-evaluate too — the liquid merge needs both sides of the blend
            // refreshed. Solid keys never read the tick, so this is free there.
            for n in neighbors[id] ?? [] { state(for: n).neighborTick &+= 1 }
        }
        pressed = next
    }

    /// Immediately drop a key's pressed state (no linger) — used when a gesture
    /// (123→emoji drag) swaps the canvas out from under the touch, so the key
    /// can't receive its normal release.
    private func clearPress(_ id: String) {
        heldCounts[id] = nil
        pressStart[id] = nil
        cancelLinger(id)
        recomputePressed()
    }

    /// Light tap played when the 123→emoji drag fires — the gesture's feedback,
    /// the haptic cousin of the shift/caps-lock morph. Only actually buzzes with
    /// Full Access granted; a silent no-op otherwise (never crashes).
    private let dragHaptic = UIImpactFeedbackGenerator(style: .rigid)

    /// Keep a just-released key visually pressed, then clear it — so a quick tap
    /// blooms fully before springing back. The hold is the longer of the
    /// post-release `lingerDuration` and whatever remains of the `minPressVisible`
    /// floor measured from touch-down, so a press the system collapsed to an
    /// instant (a deferred screen-edge tap) still stays lit long enough to bloom.
    private func startLinger(_ id: String) {
        let held = pressStart[id].map { Date().timeIntervalSince($0) } ?? 0
        pressStart[id] = nil
        let duration = max(lingerDuration, minPressVisible - held)
        guard duration > 0 else { return }
        lingering.insert(id)
        lingerTasks[id]?.cancel()
        lingerTasks[id] = Task { @MainActor in
            try? await Task.sleep(for: .seconds(duration))
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

    // MARK: - Accent long-press

    /// Window→surface offset captured at touch-down, so a window-space finger
    /// point can be mapped back into the touch surface's local space (where the
    /// key `frames` live) for accent-swatch hit-testing.
    private var viewOrigin: CGPoint = .zero
    /// The key whose accent hold is pending (timer running, bar not yet shown).
    private var accentPendingID: String?
    private var accentPendingOptions: [String] = []
    private var accentHoldTask: Task<Void, Never>?

    private func scheduleAccentHold(id: String, options: [String]) {
        cancelAccentHold()
        accentPendingID = id
        accentPendingOptions = options
        let delay = accentHoldDelay
        accentHoldTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            if Task.isCancelled { return }
            engageAccent()
        }
    }

    /// Raise the accent bar for the pending key once the still-hold elapses.
    private func engageAccent() {
        guard let id = accentPendingID else { return }
        accentKeyID = id
        accentOptions = accentPendingOptions
        accentIndex = 0
        accentPendingID = nil
        accentPendingOptions = []
        accentHoldTask = nil
        dragHaptic.impactOccurred()      // a light buzz as the bar appears
    }

    private func cancelAccentHold() {
        accentHoldTask?.cancel()
        accentHoldTask = nil
        accentPendingID = nil
        accentPendingOptions = []
    }

    /// Tear down a live accent session, dropping the held key's press so it
    /// doesn't linger-bloom after the bar dismisses.
    private func endAccentSession() {
        if let id = accentKeyID { clearPress(id) }
        accentKeyID = nil
        accentOptions = []
        accentIndex = 0
    }

    /// Which swatch the finger is over, mapping a window-space x back to the
    /// bar laid out (centred over the held key) in the touch surface's local
    /// space — the same centring the canvas renders, so the highlight under the
    /// finger matches what commits.
    private func accentSwatchIndex(forWindowX windowX: CGFloat) -> Int {
        let count = accentOptions.count
        guard count > 0, let id = accentKeyID, let frame = frames[id] else { return accentIndex }
        let localX = windowX - viewOrigin.x
        // Same anchoring/clamping the canvas renders with, so the highlighted
        // swatch is exactly the one under the finger.
        let left = AccentPicker.barLeft(keyMidX: frame.midX, count: count, containerWidth: surfaceWidth)
        let i = Int(((localX - left - AccentPicker.hPadding) / AccentPicker.swatch).rounded(.down))
        return min(max(i, 0), count - 1)
    }

    // MARK: - Backspace auto-repeat

    private var repeatTask: Task<Void, Never>?
    /// Backspace word-swipe state: the key being tracked, whether the horizontal
    /// swipe has engaged (char-repeat stopped, now deleting words), the X
    /// translation captured at engage, and how many word-deletes have fired since.
    private var deleteWordKeyID: String?
    private var deleteWordEngaged = false
    private var deleteWordOriginX: CGFloat = 0
    private var deleteWordSteps = 0
    private var spaceSteps = 0
    /// Translation (pt) at the moment the space touch engaged cursor mode. Steps
    /// are counted from here, not the touch origin, so the first character moves
    /// the instant we engage (see `touchMoved`).
    private var spaceDragOrigin: CGFloat = 0
    /// Vertical analogues for trackpad mode: line steps taken and the Y at engage.
    private var spaceVSteps = 0
    private var spaceDragOriginY: CGFloat = 0
    /// Whether the activation-delay hold has elapsed for the current space touch.
    /// Always true when `cursorActivationDelay` is 0 (instant mode).
    private var spaceCursorReady = true
    private var spaceCursorReadyTask: Task<Void, Never>?
    /// Keys whose `onDragUp` has fired for the current touch, so `touchUp` skips
    /// their tap action. Cleared on up/cancel.
    private var dragUpFired: Set<String> = []

    private func startRepeating(_ spec: KeySpec) {
        stopRepeating()
        let holdDelay = repeatHoldDelay
        let initialInterval = repeatInitialInterval
        let minInterval = repeatMinInterval
        let accelStep = repeatAccelStep
        repeatTask = Task { @MainActor in
            spec.action()                                    // first delete now
            try? await Task.sleep(for: .seconds(holdDelay))
            var interval = initialInterval
            while !Task.isCancelled {
                onPressDown()                               // clink on each repeat
                spec.action()
                deleteTick &+= 1                            // bounce the glyph
                interval = max(minInterval, interval - accelStep)
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

/// Frames of the non-key tap targets that carry their own hitbox multiplier —
/// the suggestion bar (`"bar"`) and the top-left panel icon (`"icon"`). Only
/// populated for whichever is actually on screen; used to draw their hitbox
/// outlines in the Advanced settings preview.
struct BarHitboxKey: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// Grow (or shrink) this view's hit-test area vertically by `scale` without
    /// affecting layout — mirrors the keys' `hitboxScale` for the bar chips and
    /// panel icon. `scale` 1.0 is a no-op; >1 makes the target taller, <1
    /// shrinks it. The outer negative padding cancels the layout effect so only
    /// the `contentShape` (the hittable region) changes size.
    @ViewBuilder
    func hitboxExpand(_ scale: Double, baseHeight: CGFloat) -> some View {
        let extra = baseHeight * (CGFloat(scale) - 1) / 2
        self
            .padding(.vertical, extra)
            .contentShape(Rectangle())
            .padding(.vertical, -extra)
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

    /// Per-touch swipe path tracking. A touch that lands on a letter is a swipe
    /// *candidate*; it becomes engaged once the finger slides past the threshold
    /// into a different letter key. Until engaged it's an ordinary tap.
    private struct SwipeTrack { var points: [CGPoint]; let startKeyID: String; var engaged: Bool }
    private var swipeTracks: [ObjectIdentifier: SwipeTrack] = [:]
    /// Minimum travel (pt) before a candidate can engage — keeps a normal tap
    /// (with its tiny finger wobble) from ever reading as a swipe.
    private let swipeEngageTravel: CGFloat = 22

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
            router.touchDown(id: id, localPoint: p, windowPoint: t.location(in: nil))
            // Begin tracking a possible swipe when it lands on a letter — but never
            // while another finger's swipe is already engaged (swipe is one-finger),
            // nor while an accent bar is already up (a second finger mid-pick). We do
            // NOT exclude a *pending* hold here: every accented key (most vowels, n, c…)
            // arms one on touch-down, and a real drag from such a key cancels that hold
            // before the swipe engages — so excluding pending would kill swipe-from-vowel.
            if router.isSwipeEnabled, router.isLetterKey(id), router.accentKeyID == nil,
               !swipeTracks.values.contains(where: { $0.engaged }) {
                swipeTracks[ObjectIdentifier(t)] = SwipeTrack(points: [p], startKeyID: id, engaged: false)
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            guard let b = bindings[ObjectIdentifier(t)] else { continue }
            let p = t.location(in: self)
            router.touchMoved(id: b.id, translationX: p.x - b.start.x,
                              translationY: p.y - b.start.y,
                              windowPoint: t.location(in: nil))

            let oid = ObjectIdentifier(t)
            guard var track = swipeTracks[oid] else { continue }
            track.points.append(p)
            if track.engaged {
                router.updateSwipeTrail(track.points)
            } else {
                // Engage once the finger has travelled far enough AND crossed into
                // a different letter key — a deliberate glide, not a tap wobble.
                // Suppressed while an accent bar is up/pending: `router.touchMoved`
                // above already cancels a *pending* hold on a real drag, so this only
                // blocks the engaged case (sliding to a diacritic swatch).
                let travel = hypot(p.x - b.start.x, p.y - b.start.y)
                let cur = router.key(at: p)
                if !router.accentActive, travel >= swipeEngageTravel, let cur, cur != track.startKeyID,
                   router.isLetterKey(cur) {
                    track.engaged = true
                    router.beginSwipe()
                    router.updateSwipeTrail(track.points)
                }
            }
            swipeTracks[oid] = track
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            let oid = ObjectIdentifier(t)
            guard let b = bindings.removeValue(forKey: oid) else { continue }
            router.touchUp(id: b.id, windowPoint: t.location(in: nil))
            // A finished swipe commits its word; a candidate that never engaged was
            // just a tap (already typed on touch-down) — drop it.
            if let track = swipeTracks.removeValue(forKey: oid), track.engaged {
                router.endSwipe(path: track.points)
            }
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            let oid = ObjectIdentifier(t)
            guard let b = bindings.removeValue(forKey: oid) else { continue }
            router.touchCancelled(id: b.id)
            if let track = swipeTracks.removeValue(forKey: oid), track.engaged {
                router.cancelSwipe()
            }
        }
    }
}

/// The live swipe trail — a smoothed polyline through the captured finger points,
/// drawn over the keys while a glide is in progress.
struct SwipeTrailShape: Shape {
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        guard points.count > 2 else {
            for p in points.dropFirst() { path.addLine(to: p) }
            return path
        }
        // Quadratic smoothing: curve through the midpoints of consecutive samples,
        // using each raw point as the control — rounds off the jitter of raw touch
        // samples into a clean stroke.
        for i in 1..<(points.count - 1) {
            let mid = CGPoint(x: (points[i].x + points[i + 1].x) / 2,
                              y: (points[i].y + points[i + 1].y) / 2)
            path.addQuadCurve(to: mid, control: points[i])
        }
        path.addLine(to: points[points.count - 1])
        return path
    }
}

/// Hosts `KeyGridTouchView` and feeds it the resolved key frames each layout.
struct MultiTouchSurface: UIViewRepresentable {
    let router: KeyTouchRouter
    let frames: [String: CGRect]
    let resolveSpec: (String) -> KeySpec?
    let onPressDown: () -> Void
    let lingerDuration: TimeInterval
    let minPressVisible: TimeInterval
    let hitboxScale: Double
    let adaptiveEnabled: Bool
    let adaptiveGrow: Double
    let adaptiveShrink: Double
    let adaptivePredictionWeight: Double
    let adaptivePredictAtWordStart: Bool
    let cursorStride: CGFloat
    let cursorActivationDelay: TimeInterval
    let cursorLineStride: Int
    let cursorCombined: Bool
    let repeatHoldDelay: TimeInterval
    let repeatInitialInterval: Int
    let repeatMinInterval: Int
    let repeatAccelStep: Int
    let accentsEnabled: Bool
    let accentHoldDelay: TimeInterval
    let accentMoveCancel: CGFloat
    let deleteWordEngage: CGFloat
    let deleteWordStride: CGFloat
    let dragUpThreshold: CGFloat
    let surfaceWidth: CGFloat
    let swipeEnabled: Bool
    let swipeMorphEnabled: Bool
    let swipeMorphRadius: CGFloat
    let onSwipeStart: () -> Void
    let onSwipeEnd: ([CGPoint], [Character: CGPoint]) -> Void

    func makeUIView(context: Context) -> KeyGridTouchView {
        let v = KeyGridTouchView(router: router)
        router.update(frames: frames, resolveSpec: resolveSpec,
                      onPressDown: onPressDown, lingerDuration: lingerDuration,
                      minPressVisible: minPressVisible,
                      hitboxScale: hitboxScale, adaptiveEnabled: adaptiveEnabled,
                      adaptiveGrow: adaptiveGrow, adaptiveShrink: adaptiveShrink,
                      adaptivePredictionWeight: adaptivePredictionWeight,
                      adaptivePredictAtWordStart: adaptivePredictAtWordStart,
                      cursorStride: cursorStride,
                      cursorActivationDelay: cursorActivationDelay,
                      cursorLineStride: cursorLineStride,
                      cursorCombined: cursorCombined,
                      repeatHoldDelay: repeatHoldDelay,
                      repeatInitialInterval: repeatInitialInterval,
                      repeatMinInterval: repeatMinInterval,
                      repeatAccelStep: repeatAccelStep,
                      accentsEnabled: accentsEnabled,
                      accentHoldDelay: accentHoldDelay,
                      accentMoveCancel: accentMoveCancel,
                      deleteWordEngage: deleteWordEngage,
                      deleteWordStride: deleteWordStride,
                      dragUpThreshold: dragUpThreshold,
                      surfaceWidth: surfaceWidth,
                      swipeEnabled: swipeEnabled,
                      swipeMorphEnabled: swipeMorphEnabled,
                      swipeMorphRadius: swipeMorphRadius,
                      onSwipeStart: onSwipeStart,
                      onSwipeEnd: onSwipeEnd)
        return v
    }

    func updateUIView(_ uiView: KeyGridTouchView, context: Context) {
        router.update(frames: frames, resolveSpec: resolveSpec,
                      onPressDown: onPressDown, lingerDuration: lingerDuration,
                      minPressVisible: minPressVisible,
                      hitboxScale: hitboxScale, adaptiveEnabled: adaptiveEnabled,
                      adaptiveGrow: adaptiveGrow, adaptiveShrink: adaptiveShrink,
                      adaptivePredictionWeight: adaptivePredictionWeight,
                      adaptivePredictAtWordStart: adaptivePredictAtWordStart,
                      cursorStride: cursorStride,
                      cursorActivationDelay: cursorActivationDelay,
                      cursorLineStride: cursorLineStride,
                      cursorCombined: cursorCombined,
                      repeatHoldDelay: repeatHoldDelay,
                      repeatInitialInterval: repeatInitialInterval,
                      repeatMinInterval: repeatMinInterval,
                      repeatAccelStep: repeatAccelStep,
                      accentsEnabled: accentsEnabled,
                      accentHoldDelay: accentHoldDelay,
                      accentMoveCancel: accentMoveCancel,
                      deleteWordEngage: deleteWordEngage,
                      deleteWordStride: deleteWordStride,
                      dragUpThreshold: dragUpThreshold,
                      surfaceWidth: surfaceWidth,
                      swipeEnabled: swipeEnabled,
                      swipeMorphEnabled: swipeMorphEnabled,
                      swipeMorphRadius: swipeMorphRadius,
                      onSwipeStart: onSwipeStart,
                      onSwipeEnd: onSwipeEnd)
    }
}
