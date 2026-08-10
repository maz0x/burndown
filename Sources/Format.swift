import Foundation

// Foundation-pure formatting + chart-math helpers, split out of Views.swift so the headless test
// harness (run-format-tests.sh) can compile the real implementations with no SwiftUI / Charts.
// The app keeps using them unchanged (build.sh globs Sources/*.swift).

/// Compact token count: "942", "14k", "1.4M", "7.0B".
///
/// The billions step is not decoration. A heavy week runs past a thousand million, and this used
/// to print that as "6972.0M": six digits before the decimal point, which is the exact thing a
/// compact format exists to prevent, and it wrecks the column it sits in.
func fmtTok(_ n: Int) -> String {
    if n >= 1_000_000_000 { return String(format: "%.1fB", Double(n) / 1_000_000_000) }
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

/// Compact human duration: "<1m", "45m", "2h 10m", "3d 4h".
func compactETA(_ s: TimeInterval) -> String {
    let m = Int(s / 60)
    if m < 1 { return "<1m" }
    if m < 60 { return "\(m)m" }
    let h = m / 60, remM = m % 60
    if h < 24 { return remM == 0 ? "\(h)h" : "\(h)h \(remM)m" }
    let d = h / 24, remH = h % 24
    return remH == 0 ? "\(d)d" : "\(d)d \(remH)h"
}

/// One money format for tables.
///
/// Two decimals always, and thousands grouped. The column this replaces mixed $1954 with $4.93 and
/// asked the reader to judge magnitude from the digit count; a version that switched precision by
/// size only moved the problem, printing $96.00 directly above $114. Money is written with cents,
/// so it is written with cents here, every row, whatever the size.
func moneyTable(_ v: Double) -> String {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.minimumFractionDigits = 2
    f.maximumFractionDigits = 2
    f.groupingSeparator = ","
    f.usesGroupingSeparator = true
    return "$" + (f.string(from: NSNumber(value: v)) ?? String(format: "%.2f", v))
}

/// The whole-percent pair for a usage fraction: what is used, and what is left.
///
/// Both come from ONE rounding, because rounding them separately lets them disagree. At 61.5% used
/// the two independent roundings give 62 used and 39 left, which is 101 between them, and the
/// reader who checks is right to trust neither. Deriving the remainder from the rounded used value
/// makes them add up by construction.
func usedAndLeftPercent(_ fractionUsed: Double) -> (used: Int, left: Int) {
    let used = Int((max(0, min(1, fractionUsed)) * 100).rounded())
    return (used, 100 - used)
}

/// A money label for a chart axis.
///
/// "$0" is reserved for actually zero. A sub-dollar tick used to print "$0" as well, so a day that
/// cost forty cents put "$0" at the TOP of its own axis, which reads as an axis for a day that cost
/// nothing. Whole dollars round rather than truncate, so a tick drawn at $7.80 does not claim $7.
func moneyAxisLabel(_ v: Double) -> String {
    if v <= 0 { return "$0" }
    if v < 1 { return moneyCents(v) }
    return "$\(Int(v.rounded()))"
}
