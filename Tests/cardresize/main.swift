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

if failures > 0 { print("\(failures) FAILURES"); exit(1) }
print("ALL PASS")
