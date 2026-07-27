import Foundation

// Foundation-pure formatting + chart-math helpers, split out of Views.swift so the headless test
// harness (run-format-tests.sh) can compile the real implementations with no SwiftUI / Charts.
// The app keeps using them unchanged (build.sh globs Sources/*.swift).

/// Compact token count: "942", "14k", "1.4M".
func fmtTok(_ n: Int) -> String {
    if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
    if n >= 1_000     { return String(format: "%.0fk", Double(n) / 1_000) }
    return "\(n)"
}

/// Compact dollar amount: "$112", "$2.1k".
func money(_ d: Double) -> String {
    if d >= 1000 { return String(format: "$%.1fk", d / 1000) }
    return "$" + String(Int(d.rounded()))
}

/// Dollar amount to the cent ("$4.20"), dropping the cents once it is large enough not to need them.
/// Daily spend is often under a dollar, where `money`'s rounding would render everything as "$0".
func moneyCents(_ d: Double) -> String {
    d >= 1000 ? String(format: "$%.0f", d) : String(format: "$%.2f", d)
}

// Relative X-axis label: "now" / "−12m" / "−1h" / "−6h" / "−3d".
func relTimeLabel(_ d: Date, now: Date) -> String {
    let mins = Int((now.timeIntervalSince(d) / 60).rounded())
    if mins <= 0 { return "now" }
    if mins >= 1440 { return "−\(Int((Double(mins) / 1440).rounded()))d" }
    if mins >= 60 { return "−\(Int((Double(mins) / 60).rounded()))h" }
    return "−\(mins)m"
}

/// Refresh cadence label: "live" (sub-second), "30s", "5m".
func fmtCadence(_ s: Double) -> String { s < 1 ? "live" : s >= 60 ? "\(Int(s / 60))m" : "\(Int(s))s" }

// A robust high value (e.g. P95) so a lone huge spike doesn't rescale the whole burn
// chart and flatten everything else to the floor.
func percentile(_ values: [Double], _ q: Double) -> Double {
    guard !values.isEmpty else { return 0 }
    let s = values.sorted()
    return s[max(0, min(s.count - 1, Int((Double(s.count - 1) * q).rounded())))]
}

// A stable "nice" axis top from a ladder (NOT continuous autoscale) so it stays readable
// and rarely jumps; floored at 60k so a quiet stretch doesn't over-zoom.
func burnCeiling(_ ref: Double) -> Double {
    let ladder: [Double] = [60_000, 80_000, 100_000, 120_000, 160_000, 200_000, 240_000, 280_000, 320_000,
                            400_000, 480_000, 600_000, 800_000, 1_000_000, 1_400_000, 1_800_000]
    // ~25% headroom so the tallest peak sits clearly BELOW the top, with empty space above it. That
    // way a peak reads as the real maximum, not a line clipped flat against the ceiling.
    return ladder.first { $0 >= ref * 1.25 } ?? ladder.last!
}

// "3d 4h" / "4h 30m" / "12m" - time remaining until a window resets. `now` is injectable for tests.
func weekLeftString(_ date: Date, now: Date = Date()) -> String {
    let s = max(0, date.timeIntervalSince(now))
    let d = Int(s) / 86400, h = (Int(s) % 86400) / 3600, m = (Int(s) % 3600) / 60
    if d > 0 { return "\(d)d \(h)h" }
    if h > 0 { return "\(h)h \(m)m" }
    return "\(m)m"
}

// (frac of time REMAINING over 7 days, big line, small line) for the weekly ring -
// the ring is full now and depletes as the reset approaches.
func weekRingText(_ resetAt: Date?, now: Date = Date()) -> (Double, String, String) {
    guard let r = resetAt else { return (0, "-", "idle") }
    let s = max(0, r.timeIntervalSince(now))
    let frac = min(1.0, s / (7 * 86400))   // time remaining
    let d = Int(s) / 86400, h = (Int(s) % 86400) / 3600, m = (Int(s) % 3600) / 60
    if d > 0 { return (frac, "\(d)d", "\(h)h left") }
    if h > 0 { return (frac, "\(h)h", "\(m)m left") }
    return (frac, "\(m)m", "left")
}

// (frac over the 5-hour session window, big, small) for the session ring.
func ringText(_ resetAt: Date?, now: Date = Date()) -> (Double, String, String) {
    guard let r = resetAt else { return (0, "-", "idle") }
    let s = max(0, r.timeIntervalSince(now))
    let h = Int(s) / 3600, m = (Int(s) % 3600) / 60
    let frac = min(1.0, s / (5 * 3600))   // time remaining
    return h > 0 ? (frac, "\(h)h", "\(m)m left") : (frac, "\(m)m", "left")
}
