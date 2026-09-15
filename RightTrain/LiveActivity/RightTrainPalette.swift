import SwiftUI

// The one status palette (and the shape tokens below), shared by the app and the Live Activity so a
// delayed train is the same amber on Pinned, the Lock Screen and in the
// Dynamic Island. Light values meet 4.5:1 as text on the grouped background;
// dark values are tuned for black. Everything else (surfaces, text,
// separators) uses system colours, and green doubles as the brand accent.

extension Color {
    /// On time, success, and the brand's action colour.
    static let rightTrainGood = Color("RightTrainGood")
    /// Delayed, at risk, changed platform: something to watch.
    static let rightTrainLate = Color("RightTrainAmber")
    /// Cancelled, missed, failed: something to act on now.
    static let rightTrainCancelled = Color("RightTrainDanger")
}

/// Corner radii, shared with the Live Activity. Controls and badges use
/// capsules; platform tiles scale their own radius with their size.
enum RTRadius {
    /// Inset chips, callouts and highlighted rows inside a card.
    static let chip: CGFloat = 8
    /// Cards and grouped blocks; matches inset-grouped list sections.
    static let card: CGFloat = 12
    /// Floating glass panels over content: prompts and the loading HUD.
    static let floating: CGFloat = 22
}
