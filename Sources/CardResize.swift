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

    // MARK: - Height ceiling

    /// Breathing room left between the bottom of the card and the bottom of the screen.
    static let screenGap = 24.0

    /// The tallest the card may be, in DESIGN points, given the screen space available to it.
    ///
    /// Without a ceiling the card is purely content-driven: switch on six charts and it grows
    /// straight past the bottom of the display, with no way to reach whatever fell off the end.
    /// `visible` is expected to be NSScreen.visibleFrame.height, which already excludes the menu
    /// bar and the Dock, so the only thing left to reserve is the gap. Divided by the zoom,
    /// because the card works in design points and the screen does not.
    static func heightCeiling(visible: Double, scale: Double) -> Double {
        // Clamped to the zoom range the app actually offers. A bare divide-by-zero guard let a
        // garbage scale turn into a garbage ceiling (scale 0 gave a ceiling ten times the screen),
        // which is exactly the ceiling failing to be a ceiling.
        max(240, (visible - screenGap) / max(minScale, min(maxScale, scale)))
    }

    /// The popover zoom range, matching the Settings slider.
    static let minScale = 0.7
    static let maxScale = 1.6

    /// How much bigger the chart boost may get before the card would pass the ceiling.
    ///
    /// The boost applies to every visible chart, so the headroom is shared between them. Already
    /// over the ceiling (more charts were switched on since), this returns 0: the drag can shrink
    /// the card but never grow it further off the screen.
    static func boostHeadroom(currentHeight: Double, ceiling: Double, charts: Int) -> Double {
        guard charts > 0 else { return maxBoost }
        return max(0, (ceiling - currentHeight) / Double(charts))
    }
}
