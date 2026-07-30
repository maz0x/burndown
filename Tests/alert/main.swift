import Foundation

// Behavioral tests for the REAL alert decision logic in Sources/AlertLogic.swift (compiled together
// by run-alert-tests.sh). No UNUserNotificationCenter, no AppSettings, no notifications fired,
// pure state transitions on synthetic inputs. Reverting AlertLogic.swift must make these fail.

var failures = 0
func check(_ cond: Bool, _ msg: String) {
    if cond { print("  ok   \(msg)") } else { failures += 1; print("  FAIL \(msg)") }
}

let now = Date(timeIntervalSince1970: 1_000_000)
let R = now.addingTimeInterval(3 * 3600)        // a reset 3h out

print("isNewCycle:")
check(isNewCycle(nil, R) == true, "never-stored -> new window")
check(isNewCycle(.some(R), R) == false, "same reset -> not new")
check(isNewCycle(.some(Optional<Date>.none), nil) == false, "nil->nil reset -> not new")
check(isNewCycle(.some(R), nil) == true, "reset lost -> new window")
check(isNewCycle(.some(R), R.addingTimeInterval(60)) == false, "reset jitter <120s -> not new")
check(isNewCycle(.some(R), R.addingTimeInterval(200)) == true, "reset jumps forward >120s -> new window")

print("alertPctEval (fire once per level per window):")
var st = AlertPctState()
check(alertPctEval(pct: 0.85, reset: R, base: 80, repeatMin: 0, now: now, state: &st) == .fire(level: 80, cur: 85),
      "crossing 80% base fires level 80")
check(alertPctEval(pct: 0.86, reset: R, base: 80, repeatMin: 0, now: now, state: &st) == .none,
      "still over 80 in same window -> no re-fire (single-fire-per-level)")
// live<->est source flip / refresh keeps the same reset -> must NOT re-arm or re-fire
check(alertPctEval(pct: 0.87, reset: R.addingTimeInterval(60), base: 80, repeatMin: 0, now: now, state: &st) == .none,
      "reset jitter from source flip -> no re-fire")
// jump to 100 fires the limit level
check(alertPctEval(pct: 1.0, reset: R, base: 80, repeatMin: 0, now: now, state: &st) == .fire(level: 100, cur: 100),
      "crossing 100% fires the limit level")
// new window (reset jumps >120s) re-arms and fires again
check(alertPctEval(pct: 0.85, reset: R.addingTimeInterval(200), base: 80, repeatMin: 0, now: now, state: &st) == .fire(level: 80, cur: 85),
      "forward reset jump re-arms the window and re-fires")

print("alertPctEval repeat-while-over:")
var st2 = AlertPctState()
_ = alertPctEval(pct: 0.90, reset: R, base: 80, repeatMin: 15, now: now, state: &st2)        // initial fire at t0
check(alertPctEval(pct: 0.91, reset: R, base: 80, repeatMin: 15, now: now.addingTimeInterval(10 * 60), state: &st2) == .none,
      "repeat suppressed before repeatMin elapses (10m < 15m)")
check(alertPctEval(pct: 0.91, reset: R, base: 80, repeatMin: 15, now: now.addingTimeInterval(15 * 60), state: &st2) == .repeatOver(cur: 91),
      "repeat fires once repeatMin elapses (>=15m)")

print("alertBurnEval hysteresis:")
var armed = true
check(alertBurnEval(burn: 120, threshold: 100, armed: &armed) == true && armed == false,
      "burn over threshold fires once and disarms")
check(alertBurnEval(burn: 130, threshold: 100, armed: &armed) == false,
      "still high while disarmed -> no re-fire")
check(alertBurnEval(burn: 70, threshold: 100, armed: &armed) == false && armed == false,
      "exactly 0.7x threshold does NOT re-arm (strict <)")
check(alertBurnEval(burn: 69, threshold: 100, armed: &armed) == false && armed == true,
      "below 0.7x threshold re-arms")
check(alertBurnEval(burn: 120, threshold: 100, armed: &armed) == true,
      "re-armed then over threshold -> fires again")

print("alertForecastEval (fire once, re-arm on new window):")
var fs = AlertForecastState()
check(alertForecastEval(minsLeft: 10, threshold: 30, reset: R, state: &fs) == 10,
      "ETA under threshold fires with rounded minutes")
check(alertForecastEval(minsLeft: 8, threshold: 30, reset: R, state: &fs) == nil,
      "already fired this window -> nil")
check(alertForecastEval(minsLeft: 5, threshold: 30, reset: R.addingTimeInterval(200), state: &fs) == 5,
      "forward reset jump re-arms the forecast alert")
check(alertForecastEval(minsLeft: 45, threshold: 30, reset: R.addingTimeInterval(200), state: &fs) == nil,
      "ETA above threshold -> nil")
check(alertForecastEval(minsLeft: nil, threshold: 30, reset: R.addingTimeInterval(200), state: &fs) == nil,
      "no ETA -> nil")

print(failures == 0 ? "\nALL PASS" : "\n\(failures) FAILURE(S)")
exit(failures == 0 ? 0 : 1)
