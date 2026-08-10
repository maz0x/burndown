import Foundation

// Behavioral tests for the Foundation-pure helpers in Sources/Format.swift.
// Compiled headlessly with that one file by run-format-tests.sh.

var failures = 0
func check(_ cond: Bool, _ msg: String) {
    print(cond ? "  ok   \(msg)" : "  FAIL \(msg)")
    if !cond { failures += 1 }
}

print("fmtTok:")
check(fmtTok(0) == "0", "0 -> 0")
check(fmtTok(942) == "942", "942 -> 942")
check(fmtTok(1_000) == "1k", "1000 -> 1k")
check(fmtTok(14_300) == "14k", "14300 -> 14k")
check(fmtTok(1_000_000) == "1.0M", "1e6 -> 1.0M")
check(fmtTok(1_400_000) == "1.4M", "1.4e6 -> 1.4M")
check(fmtTok(999) == "999", "999 -> 999 (just below k threshold)")
check(fmtTok(999_999) == "1000k", "999999 -> 1000k (M threshold is exactly 1e6)")
check(fmtTok(-5) == "-5", "negative passes through verbatim")

print("money:")
check(money(0) == "$0", "0 -> $0")
check(money(112) == "$112", "112 -> $112")
check(money(112.6) == "$113", "112.6 rounds -> $113")
check(money(999) == "$999", "999 -> $999")
check(money(1_000) == "$1.0k", "1000 -> $1.0k")
check(money(2_100) == "$2.1k", "2100 -> $2.1k")
// The k-threshold tests the raw double (>= 1000), not the rounded value: 999.5 rounds up
// to $1000 yet still prints in dollars, while a true 1000 prints in $k.
check(money(999.4) == "$999", "999.4 rounds down -> $999")
check(money(999.6) == "$1000", "999.6 rounds up but still < 1000 -> $1000 (not $k)")
check(money(999.5) == "$1000", "999.5 rounds half-up -> $1000")

print("fmtCadence:")
check(fmtCadence(0.5) == "live", "<1s -> live")
check(fmtCadence(30) == "30s", "30 -> 30s")
check(fmtCadence(59) == "59s", "59 -> 59s")
check(fmtCadence(60) == "1m", "60 -> 1m")
check(fmtCadence(300) == "5m", "300 -> 5m")
check(fmtCadence(0) == "live", "0 -> live")
check(fmtCadence(90) == "1m", "90 -> 1m (truncates 1.5m)")
check(fmtCadence(119) == "1m", "119 -> 1m (truncates)")

print("relTimeLabel:")
let now = Date(timeIntervalSince1970: 1_000_000)
check(relTimeLabel(now, now: now) == "now", "0 -> now")
check(relTimeLabel(now.addingTimeInterval(-20), now: now) == "now", "20s ago -> now")
check(relTimeLabel(now.addingTimeInterval(-12 * 60), now: now) == "−12m", "12m ago")
check(relTimeLabel(now.addingTimeInterval(-60 * 60), now: now) == "−1h", "1h ago")
check(relTimeLabel(now.addingTimeInterval(-6 * 3600), now: now) == "−6h", "6h ago")
check(relTimeLabel(now.addingTimeInterval(-3 * 86400), now: now) == "−3d", "3d ago")
// 30s ago rounds to 1 minute (the "now" branch only fires at <= 0 minutes).
check(relTimeLabel(now.addingTimeInterval(-30), now: now) == "−1m", "30s ago rounds to −1m")
// Minute->hour rounding boundary: 89m rounds to 1h, 90m rounds to 2h.
check(relTimeLabel(now.addingTimeInterval(-89 * 60), now: now) == "−1h", "89m -> −1h")
check(relTimeLabel(now.addingTimeInterval(-90 * 60), now: now) == "−2h", "90m -> −2h")
// Day boundary: 1439m still shows hours (−24h); 1440m flips to days (−1d).
check(relTimeLabel(now.addingTimeInterval(-1439 * 60), now: now) == "−24h", "1439m -> −24h")
check(relTimeLabel(now.addingTimeInterval(-1440 * 60), now: now) == "−1d", "1440m -> −1d")
check(relTimeLabel(now.addingTimeInterval(-36 * 3600), now: now) == "−2d", "36h rounds to −2d")

print("percentile:")
check(percentile([], 0.9) == 0, "empty -> 0")
check(percentile([5], 0.9) == 5, "single -> that value")
check(percentile([1, 2, 3, 4, 5, 6, 7, 8, 9, 10], 1.0) == 10, "p100 of 1..10 -> 10")
check(percentile([1, 2, 3, 4, 5, 6, 7, 8, 9, 10], 0.9) == 9, "p90 of 1..10 -> 9 (index 8.1 rounds to 8)")
check(percentile([1, 2, 3, 4, 5, 6, 7, 8, 9, 10], 0.5) == 6, "p50 of 1..10 -> 6 (index 4.5 rounds to 5)")
check(percentile([10, 1, 5, 3], 0.0) == 1, "p0 -> sorted min")
// Out-of-range q is absorbed by the index clamp: q>1 -> last, q<0 -> first.
check(percentile([1, 2, 3, 4], 1.5) == 4, "q>1 clamps to last element")
check(percentile([1, 2, 3, 4], -0.5) == 1, "q<0 clamps to first element")
check(percentile([5, 5, 5, 5], 0.5) == 5, "all-equal -> that value")

print("burnCeiling:")
check(burnCeiling(0) == 60_000, "0 -> 60k floor")
check(burnCeiling(40_000) == 60_000, "40k (x1.25=50k) -> 60k")
check(burnCeiling(60_000) == 80_000, "60k (x1.25=75k) -> 80k")
check(burnCeiling(200_000) == 280_000, "200k (x1.25=250k) -> 280k")
check(burnCeiling(5_000_000) == 1_800_000, "huge -> ladder top 1.8M")

print("ringText / weekRingText / weekLeftString (now injected):")
let t0 = Date(timeIntervalSince1970: 1_000_000)
let s1 = ringText(t0.addingTimeInterval(82 * 60), now: t0)
check(s1.1 == "1h" && s1.2 == "22m left", "session 1h22m -> 1h / 22m left")
check(abs(s1.0 - (82.0 * 60) / (5 * 3600)) < 0.001, "session frac ~0.273")
let s2 = ringText(t0.addingTimeInterval(22 * 60), now: t0)
check(s2.1 == "22m" && s2.2 == "left", "session 22m -> 22m / left")
check(ringText(nil, now: t0).1 == "-", "nil reset -> '-'")
let w1 = weekRingText(t0.addingTimeInterval(2 * 86400 + 21 * 3600), now: t0)
check(w1.1 == "2d" && w1.2 == "21h left", "week 2d21h -> 2d / 21h left")
// nil reset -> the idle placeholder, frac 0.
let wNil = weekRingText(nil, now: t0)
check(wNil.0 == 0 && wNil.1 == "-" && wNil.2 == "idle", "week nil -> (0, '-', 'idle')")
// hours-only branch (d == 0): small label carries the minutes-left.
let wH = weekRingText(t0.addingTimeInterval(5 * 3600 + 12 * 60), now: t0)
check(wH.1 == "5h" && wH.2 == "12m left", "week 5h12m -> 5h / 12m left")
// minutes-only branch: small label is the bare 'left'.
let wM = weekRingText(t0.addingTimeInterval(40 * 60), now: t0)
check(wM.1 == "40m" && wM.2 == "left", "week 40m -> 40m / left")
// frac is clamped to 1.0 when the reset is more than 7 days out.
check(weekRingText(t0.addingTimeInterval(9 * 86400), now: t0).0 == 1.0, "week >7d -> frac clamped to 1.0")
// session ring: frac clamped to 1.0 when reset is more than 5h out, and nil -> idle.
check(ringText(t0.addingTimeInterval(8 * 3600), now: t0).0 == 1.0, "session >5h -> frac clamped to 1.0")
let rNil = ringText(nil, now: t0)
check(rNil.0 == 0 && rNil.1 == "-" && rNil.2 == "idle", "session nil -> (0, '-', 'idle')")
check(weekLeftString(t0.addingTimeInterval(3 * 86400 + 4 * 3600), now: t0) == "3d 4h", "3d 4h")
check(weekLeftString(t0.addingTimeInterval(4 * 3600 + 30 * 60), now: t0) == "4h 30m", "4h 30m")
check(weekLeftString(t0.addingTimeInterval(45 * 60), now: t0) == "45m", "45m")
check(weekLeftString(t0.addingTimeInterval(5 * 86400), now: t0) == "5d 0h", "exact 5d -> 5d 0h")
check(weekLeftString(t0, now: t0) == "0m", "exactly at reset -> 0m")
check(weekLeftString(t0.addingTimeInterval(-100), now: t0) == "0m", "past reset -> 0m")

// --- one money format for tables ---
// The bug this replaces: $1954 sitting next to $4.93 in the same column, so the reader has to
// work out the magnitude from the digit count.
check(moneyTable(4.93) == "$4.93", "under ten keeps its cents")
check(moneyTable(0) == "$0.00", "zero reads as money, not as nothing")
check(moneyTable(12.34) == "$12.34", "cents are always shown")
check(moneyTable(99.99) == "$99.99", "at every size, so a column never changes precision partway down")
check(moneyTable(1954.4) == "$1,954.40", "thousands are grouped and still show cents")
check(moneyTable(1234567) == "$1,234,567.00", "and stay grouped when large")
check(moneyTable(-4.5) == "$-4.50", "a negative still formats rather than breaking")

// Billions: a heavy week runs past a thousand million, and "6972.0M" is six digits before the
// decimal point, which is what a compact format exists to prevent.
check(fmtTok(6_972_000_000) == "7.0B", "billions get their own step")
check(fmtTok(1_000_000_000) == "1.0B", "exactly a billion crosses over")
check(fmtTok(999_999_999) == "1000.0M", "and just under it stays in millions")

// Rounding "used" and "left" separately lets them disagree: at 61.5 percent the two independent
// roundings give 62 used and 39 left, which is 101 between them.
print("used and left always add up:")
do {
    var worst = 0
    for i in 0...1000 {
        let f = Double(i) / 1000.0
        let (used, left) = usedAndLeftPercent(f)
        worst = max(worst, abs(used + left - 100))
    }
    check(worst == 0, "every fraction from 0 to 1 splits into two whole percents that sum to 100")
    check(usedAndLeftPercent(0.615).used == 62, "61.5 percent used rounds to 62")
    check(usedAndLeftPercent(0.615).left == 38, "and the remainder follows from it, not from its own rounding")
    check(usedAndLeftPercent(0).left == 100, "nothing used is everything left")
    check(usedAndLeftPercent(1).left == 0, "and all used is nothing left")
    check(usedAndLeftPercent(1.4).left == 0, "an over-limit fraction clamps rather than going negative")
    check(usedAndLeftPercent(-0.2).used == 0, "and so does a negative one")
}

// A sub-dollar day used to print "$0" at the TOP of its own axis, which reads as an axis for a day
// that cost nothing at all.
print("money axis labels:")
check(moneyAxisLabel(0) == "$0", "zero is the only thing that prints $0")
check(moneyAxisLabel(0.4) != "$0", "forty cents does not")
check(moneyAxisLabel(0.4).contains("0.4"), "it shows the cents instead")
check(moneyAxisLabel(7.8) == "$8", "whole dollars round rather than truncate")
check(moneyAxisLabel(7.2) == "$7", "in both directions")
check(moneyAxisLabel(120) == "$120", "and a large value is plain")

print(failures == 0 ? "\nALL PASS" : "\n\(failures) FAILURE(S)")
exit(failures == 0 ? 0 : 1)
