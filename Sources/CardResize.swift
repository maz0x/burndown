import Foundation

// Corner-drag RESIZING for the card (popover + floating window). Reflow, not zoom.
//
// The two axes do two different, useful things at a constant font size:
//   * Horizontal: card WIDTH. Every row already fills its container (bars are GeometryReader,
//     names truncate against a Spacer, charts plot into available width), so a wider card means
//     longer bars, fuller chat names, roomier charts - more information, same type size.
//   * Vertical: extra plot height added to every popover chart ("boost"). The card's height is
//     content-driven, so charts are the one honest place for vertical growth to go; with the
//     chart section hidden the vertical axis is deliberately inert.
//
// Zooming (text and all) stays a separate control: the Appearance "Popover size" slider
// (settings.textScale). The grip changes the window, the slider changes the type.
// This file is Foundation-pure so run-cardresize-tests.sh can compile it alone.
enum CardResize {
    /// The design floor: every layout constant in DetailCard was tuned at this width, so the
    /// card never goes narrower - shrinking below the design is where "responsive" turns ugly.
    static let minWidth = 264.0
    /// Wide enough to defeat name truncation and stretch every bar; past this the single-column
    /// card starts to read as empty acreage.
    static let maxWidth = 440.0
    /// Extra plot height added to EVERY chart, 0 (the tuned 74pt base) to +90 (a tall reading).
    static let minBoost = 0.0
    static let maxBoost = 90.0

    static func clampW(_ w: Double) -> Double { max(minWidth, min(maxWidth, w)) }
    static func clampB(_ b: Double) -> Double { max(minBoost, min(maxBoost, b)) }

    /// Horizontal drag: the card's right edge tracks the cursor 1:1. `dx` is in DESIGN points
    /// (the caller divides the cursor delta by textScale, since the zoom multiplies on top).
    static func width(start: Double, dx: Double) -> Double { clampW(start + dx) }

    /// Vertical drag: `dy` (design points) is split across the `charts` visible plots, so the
    /// card's bottom edge - which moves by charts x boost - tracks the cursor 1:1. With no
    /// charts visible there is nothing for height to mean, and the axis is inert.
    static func boost(start: Double, dy: Double, charts: Int) -> Double {
        guard charts > 0 else { return clampB(start) }
        return clampB(start + dy / Double(charts))
    }
}
