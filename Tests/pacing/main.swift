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
check(!p1.summary.contains("-"), "summary has no em-dash")

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

print(failures == 0 ? "\nALL PACING TESTS PASSED" : "\n\(failures) FAILURE(S)")
exit(failures == 0 ? 0 : 1)
