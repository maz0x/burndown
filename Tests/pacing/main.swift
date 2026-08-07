import Foundation

// Headless tests for the Foundation-pure weekly pacing advisor (Sources/Pacing.swift).
// Same self-contained check()/failures/exit(1) pattern as Tests/chartdata/main.swift.

var failures = 0
func check(_ cond: Bool, _ msg: String) {
    print(cond ? "  ok   \(msg)" : "  FAIL \(msg)")
    if !cond { failures += 1 }
}

print("weeklyPacing (hits cap before reset):")
// Half the cap used, burning 10% of cap/hour: 0.5 / 0.1 = 5h to cap, well before a 24h reset.
let p1 = weeklyPacing(fractionUsed: 0.5, ratePerHour: 0.1, hoursUntilReset: 24, sessionFraction: 0.1)
check(p1.hoursUntilCap == 5, "hoursUntilCap = remaining / ratePerHour = 5")
check(p1.hitsCapBeforeReset, "5h <= 24h means cap is hit before reset")
check(abs(p1.sessionsRemaining - 5) < 1e-9, "0.5 / 0.1 = 5 sessions remaining")
check(p1.summary.contains("reach the weekly cap"), "summary warns about reaching the cap")
check(!p1.summary.contains("\u{2014}") && !p1.summary.contains("\u{2013}"),
      "summary has no em-dash or en-dash")

print("weeklyPacing (headroom to the reset):")
// 20% used, slow 1%/hour burn: 0.8 / 0.01 = 80h to cap, far beyond a 24h reset.
let p2 = weeklyPacing(fractionUsed: 0.2, ratePerHour: 0.01, hoursUntilReset: 24, sessionFraction: 0.1)
check(p2.hoursUntilCap == 80, "hoursUntilCap = 0.8 / 0.01 = 80")
check(!p2.hitsCapBeforeReset, "80h > 24h means it does not hit the cap before reset")
check(abs(p2.sessionsRemaining - 8) < 1e-9, "0.8 / 0.1 = 8 sessions remaining")
check(p2.summary.contains("headroom") && p2.summary.contains("8 sessions"), "summary reports headroom and session count")

print("weeklyPacing (zero rate, cap never reached):")
let p3 = weeklyPacing(fractionUsed: 0.3, ratePerHour: 0, hoursUntilReset: 10, sessionFraction: 0.2)
check(p3.hoursUntilCap == nil, "ratePerHour <= 0 -> hoursUntilCap is nil")
check(!p3.hitsCapBeforeReset, "nil hoursUntilCap can never hit the cap before reset")
check(abs(p3.sessionsRemaining - 3.5) < 1e-9, "0.7 / 0.2 = 3.5 sessions remaining")

print("weeklyPacing (boundary: exactly at reset horizon):")
// 0.4 remaining at 0.04/hour = exactly 10h, equal to hoursUntilReset (<= is inclusive).
let p4 = weeklyPacing(fractionUsed: 0.6, ratePerHour: 0.04, hoursUntilReset: 10, sessionFraction: 0.1)
check(p4.hoursUntilCap == 10, "remaining 0.4 / 0.04 = 10h")
check(p4.hitsCapBeforeReset, "exactly at the reset horizon counts as hitting the cap (<=)")

print("weeklyPacing (already at or over the cap):")
let p5 = weeklyPacing(fractionUsed: 1.0, ratePerHour: 0.1, hoursUntilReset: 12, sessionFraction: 0.1)
check(p5.sessionsRemaining == 0, "no remaining fraction -> 0 sessions remaining")
check(p5.summary.contains("Weekly cap reached"), "summary states the cap is already reached")
let p6 = weeklyPacing(fractionUsed: 1.5, ratePerHour: 0.1, hoursUntilReset: 12, sessionFraction: 0.1)
check(p6.sessionsRemaining == 0, "overshooting the cap clamps remaining to 0 sessions")
check(p6.hoursUntilCap == 0, "remaining clamps to 0 so the cap is 0h away")

print("weeklyPacing (zero session size):")
let p7 = weeklyPacing(fractionUsed: 0.4, ratePerHour: 0.05, hoursUntilReset: 24, sessionFraction: 0)
check(p7.sessionsRemaining == 0, "sessionFraction <= 0 -> 0 sessions remaining (no divide by zero)")

print("hoursText:")
check(hoursText(2) == "2h", "whole hours render as Xh")
check(hoursText(0.5) == "30m", "under an hour renders as minutes")
check(hoursText(0) == "0m", "zero renders as 0m")
check(hoursText(-5) == "0m", "negative durations clamp to 0m")

print("paceReading:")
// A five hour session window, one hour in.
let H = 3600.0, W5 = 5 * H
check(paceReading(pct: 0.2, secondsToReset: 4 * H, window: W5)?.ratio == 1.0,
      "20% spent one fifth of the way in is exactly 1.0x")
check(abs((paceReading(pct: 0.4, secondsToReset: 4 * H, window: W5)?.ratio ?? 0) - 2.0) < 0.001,
      "twice the budget for the time elapsed reads 2.0x")
check(paceReading(pct: 0.5, secondsToReset: W5 - 30, window: W5) == nil,
      "the first minute of a window says nothing rather than a wild number")

// Overspending: 40% gone in the first hour empties the budget 90 minutes before the reset.
let hot = paceReading(pct: 0.4, secondsToReset: 4 * H, window: W5)!
check(abs((hot.secondsToEmpty ?? 0) - 1.5 * H) < 1, "60% left at 40% per hour is 90 minutes")
check(abs((hot.dryEarlyBy ?? 0) - 2.5 * H) < 1, "which lands 2h 30m short of the reset")
check(hot.caption.contains("before the reset"), "and the caption says so in plain words")

// Comfortable: on pace to coast to the reset.
let calm = paceReading(pct: 0.1, secondsToReset: 4 * H, window: W5)!
check(calm.dryEarlyBy == nil, "a comfortable pace never runs dry early")
check(calm.caption.contains("lasts past the reset"), "and says it lasts")

// Spending nothing must not divide by zero or claim a run-out.
let idle = paceReading(pct: 0, secondsToReset: 4 * H, window: W5)!
check(idle.secondsToEmpty == nil && idle.ratio == 0, "no spend means no projection and 0.0x")

// Already at the cap.
let done = paceReading(pct: 1.0, secondsToReset: 2 * H, window: W5, atLimitLabel: "limit")!
check(done.caption.hasPrefix("limit reached"), "at the cap it reports the cap, not a forecast")
check(done.secondsToEmpty == nil || done.secondsToEmpty == 0, "with nothing left to project")

print(failures == 0 ? "\nALL PACING TESTS PASSED" : "\n\(failures) FAILURE(S)")
exit(failures == 0 ? 0 : 1)
