/**
 `TrackpadPanel`: the trackpad-mode overlay shown while the space bar is held in
 trackpad cursor mode. Purely visual — a centered move glyph tinted the theme accent.
 */
import SwiftUI

/// The full-keyboard trackpad shown while the space bar is held in trackpad
/// cursor mode — just a single centred 2-D move glyph, tinted the theme accent,
/// over the keyboard's own backdrop (painted by the canvas). Purely visual: the
/// drag is tracked by the multitouch surface beneath it, so it takes no touches.
struct TrackpadPanel: View {
    let theme: Theme

    var body: some View {
        Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
            .font(.system(size: 22, weight: .regular))
            .foregroundStyle(theme.accent.color)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
