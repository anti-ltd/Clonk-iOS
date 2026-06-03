import UIKit
import os

/// Diagnostic trace for the keyboard height-jump bug. Flip `enabled` off (or
/// delete the calls) once the cause is pinned. Read it in Console.app with the
/// device tethered, filter: subsystem `ltd.anti.clink`, category `height`.
public enum HeightTrace {
    public static let enabled = false
    static let log = Logger(subsystem: "ltd.anti.clink", category: "height")
}

public extension UIInputViewController {
    /// Dump the view's current height state at a named point in the lifecycle, so
    /// a single keyboard switch on-device produces an ordered trace of what height
    /// is in effect when — and whether the system's inflated balloon constraint is
    /// present/tamed at that moment.
    func logHeightState(_ tag: String) {
        guard HeightTrace.enabled else { return }
        // Pre-format with `String(format:)` — it prints "nan"/"inf" instead of
        // trapping the way `Int(cgFloat)` would on a non-finite value (possible
        // during the first, pre-sized layout pass).
        let h = String(format: "%.0f", view.bounds.height)
        let intrinsic = String(format: "%.0f", view.intrinsicContentSize.height)
        var balloon = "none"
        for c in view.constraints
        where c.firstItem === view
            && c.firstAttribute == .height
            && c.identifier == "UIView-Encapsulated-Layout-Height" {
            balloon = String(format: "%.0f@%.0f", c.constant, c.priority.rawValue)
        }
        let line = "\(tag): bounds=\(h) intrinsic=\(intrinsic) balloon=\(balloon)"
        HeightTrace.log.log("\(line, privacy: .public)")
    }
}

public extension UIView {

    /// Defuse iOS's `UIView-Encapsulated-Layout-Height` constraint on this view.
    ///
    /// On presentation iOS installs this constraint at **required (1000)** priority,
    /// set to a transient inflated height (empirically our target + ~228pt) before
    /// it re-measures and settles. Our own height constraint sits at `.required - 1`
    /// (999), so during that window the system's value wins and the keyboard renders
    /// inflated for a frame, then collapses. Switching keyboards is worst: the
    /// inflated, bottom-docked frame pushes our (transparent) top edge up over the
    /// host app, which shows through for the length of the appearance animation.
    ///
    /// Dropping its priority below ours makes our target height win. It re-applies
    /// automatically since iOS re-adds the constraint on every appearance. Returns
    /// whether it found and tamed one (useful for the input view's own hook).
    @discardableResult
    func tameEncapsulatedHeightConstraint() -> Bool {
        var tamed = false
        for c in constraints
        where c.firstItem === self
            && c.firstAttribute == .height
            && c.identifier == "UIView-Encapsulated-Layout-Height"
            && c.priority == .required {
            c.priority = .defaultHigh   // 750 — below our 999 height constraint
            tamed = true
        }
        return tamed
    }
}

public extension UIInputViewController {
    /// See `UIView.tameEncapsulatedHeightConstraint()`. Safe to call from any layout
    /// hook; cheap.
    func tameSystemHeightConstraint() {
        view.tameEncapsulatedHeightConstraint()
    }
}
