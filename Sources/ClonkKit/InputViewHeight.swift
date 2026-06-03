import UIKit

public extension UIInputViewController {

    /// Kill the "height balloons huge then snaps to normal" flash that custom
    /// keyboards show on first appearance and when switching between two of our
    /// keyboards (e.g. emoji ↔ letters).
    ///
    /// On presentation iOS installs its own constraint on our `view` —
    /// `UIView-Encapsulated-Layout-Height`, at **required (1000)** priority — set
    /// to a transient height (empirically our target + ~228pt) before it
    /// re-measures and settles. Our own height constraint sits at `.required - 1`
    /// (999), so during that window the system's value wins and the keyboard
    /// renders inflated for a frame, then collapses. Switching keyboards makes it
    /// worst because the transition starts from the *other* keyboard's frame.
    ///
    /// Fix: each layout pass, find that system constraint and drop its priority
    /// below ours so our target height always wins. No hardcoded offsets, and it
    /// re-applies automatically since iOS re-adds the constraint on every
    /// appearance. Cheap; safe to call from `viewDidLayoutSubviews`.
    func tameSystemHeightConstraint() {
        for c in view.constraints
        where c.firstItem === view
            && c.firstAttribute == .height
            && c.identifier == "UIView-Encapsulated-Layout-Height"
            && c.priority == .required {
            c.priority = .defaultHigh   // 750 — below our 999 height constraint
        }
    }
}
