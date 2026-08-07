import Foundation

// Tests for CardResize (Sources/CardResize.swift): the corner-drag reflow math behind the
// popover / floating card resize grip. Horizontal drag = card width, vertical drag = per-chart
// height boost. Pure assertions, no AppKit.

var failures = 0
func expect(_ cond: Bool, _ name: String) {
    if cond { print("  ok  \(name)") } else { failures += 1; print("  FAIL \(name)") }
}
func eq(_ a: Double, _ b: Double, _ tol: Double = 1e-9) -> Bool { abs(a - b) <= tol }

// The limits themselves.
expect(eq(CardResize.minWidth, 264.0), "min width is the 264pt design floor")
expect(CardResize.maxWidth > CardResize.minWidth, "width range is non-empty")
expect(eq(CardResize.minBoost, 0.0), "boost floor is the tuned base (0 extra)")
expect(CardResize.maxBoost > 0, "boost range is non-empty")

// Clamps.
expect(eq(CardResize.clampW(100), CardResize.minWidth), "clampW floors below the design width")
expect(eq(CardResize.clampW(9999), CardResize.maxWidth), "clampW ceils at max")
expect(eq(CardResize.clampW(300), 300), "clampW passes in-range widths")
expect(eq(CardResize.clampB(-20), 0), "clampB floors at 0")
expect(eq(CardResize.clampB(9999), CardResize.maxBoost), "clampB ceils at max")

// Horizontal drag: the right edge tracks the cursor 1:1.
expect(eq(CardResize.width(start: 264, dx: 60), 324), "width grows by the cursor delta")
expect(eq(CardResize.width(start: 324, dx: -60), 264), "width shrinks by the cursor delta")
expect(eq(CardResize.width(start: 264, dx: -500), CardResize.minWidth), "width never goes below design")
expect(eq(CardResize.width(start: 264, dx: 5000), CardResize.maxWidth), "width never exceeds max")
expect(eq(CardResize.width(start: 264, dx: 0), 264), "zero dx keeps width")

// Vertical drag: dy splits across visible charts so the card's bottom edge tracks the cursor.
expect(eq(CardResize.boost(start: 0, dy: 40, charts: 1), 40), "one chart absorbs the whole dy")
expect(eq(CardResize.boost(start: 0, dy: 40, charts: 2), 20), "two charts split dy in half")
expect(eq(CardResize.boost(start: 30, dy: -30, charts: 3), 20), "shrink composes with the start")
expect(eq(CardResize.boost(start: 0, dy: 5000, charts: 2), CardResize.maxBoost), "boost clamps at max")
expect(eq(CardResize.boost(start: 50, dy: -5000, charts: 2), 0), "boost clamps at 0")

// With no charts visible, the vertical axis is inert (but still clamps a wild start).
expect(eq(CardResize.boost(start: 20, dy: 300, charts: 0), 20), "no charts: dy is inert")
expect(eq(CardResize.boost(start: 500, dy: 10, charts: 0), CardResize.maxBoost), "no charts: start still clamps")

// The height ceiling: the card may never grow past the bottom of the screen.
// 900pt of usable screen (menu bar and Dock already excluded), less the 24pt gap.
expect(eq(CardResize.heightCeiling(visible: 900, scale: 1), 876), "the card stops short of the screen edge")
expect(eq(CardResize.heightCeiling(visible: 900, scale: 1.5), 584), "zoom divides out: the ceiling is in design points")
expect(eq(CardResize.heightCeiling(visible: 200, scale: 1), 240), "a tiny screen still leaves a usable card")
expect(eq(CardResize.heightCeiling(visible: 900, scale: 0), 1251.4285714285713),
       "a scale below the app's range clamps to 0.7 rather than producing a wild ceiling")
expect(CardResize.heightCeiling(visible: 900, scale: 99) >= 240,
       "and an absurd scale still returns a usable ceiling")

// Grip headroom: four charts with 100pt left means each may grow by 25.
expect(eq(CardResize.boostHeadroom(currentHeight: 776, ceiling: 876, charts: 4), 25),
       "headroom is shared between the visible charts")
expect(eq(CardResize.boostHeadroom(currentHeight: 900, ceiling: 876, charts: 4), 0),
       "already past the ceiling, the grip shrinks but never grows")
expect(eq(CardResize.boostHeadroom(currentHeight: 400, ceiling: 876, charts: 0), CardResize.maxBoost),
       "no charts means the boost is not the thing to clamp")

// A whole drag, frame by frame, the way the grip actually drives it.
//
// The bug this guards: the boost limit was recomputed every frame from the LIVE height and the
// LIVE boost, so the limit chased its own tail and the card crept instead of following the
// cursor. The limit is now fixed at mouse-down, so the bottom edge tracks the drag one to one
// until it reaches the screen and then simply stops.
do {
    let charts = 3
    let anchorBoost = 10.0
    let ceiling = 876.0
    let heightAtStart = 700.0
    // Fixed once, at mouse-down.
    let maxBoost = min(CardResize.maxBoost,
                       anchorBoost + CardResize.boostHeadroom(currentHeight: heightAtStart,
                                                              ceiling: ceiling, charts: charts))
    func frame(_ dy: Double) -> Double {
        min(maxBoost, CardResize.boost(start: anchorBoost, dy: dy, charts: charts))
    }
    // Dragging down 30pt over three charts adds 10 to the boost: one to one with the cursor.
    expect(eq(frame(30), 20), "the boost follows the cursor one to one")
    expect(eq(frame(60), 30), "and keeps following it")
    // Never goes backwards while the cursor goes forwards.
    var last = -1.0, monotonic = true
    for step in 0...80 {
        let v = frame(Double(step) * 5)
        if v < last - 0.0001 { monotonic = false }
        last = v
    }
    expect(monotonic, "and never jumps backwards partway through a drag")
    // Past the ceiling it stops dead rather than creeping.
    expect(eq(frame(10_000), maxBoost), "a drag past the screen edge stops at the limit")
    expect(eq(frame(20_000), maxBoost), "and stays there however much further the cursor goes")
    // Dragging back UP still shrinks, all the way to zero.
    expect(eq(frame(-30), 0), "dragging back up shrinks the card")
    // The limit does not depend on where the drag currently is, only on where it started.
    let same = min(CardResize.maxBoost,
                   anchorBoost + CardResize.boostHeadroom(currentHeight: heightAtStart,
                                                          ceiling: ceiling, charts: charts))
    expect(eq(same, maxBoost), "the limit is a constant for the whole gesture")
}

if failures > 0 { print("\(failures) FAILURES"); exit(1) }
print("ALL PASS")
