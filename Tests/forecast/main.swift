import Foundation

// Redeclare the tiny value type here (the real one lives in LiveActivity.swift, which pulls in
// Combine / SwiftUI). Same convention as Tests/chartdata/main.swift, so the headless compile of
// Sources/Forecast.swift is self-contained. LiveState + the forecast functions come from Forecast.swift.
struct TimedSample: Equatable { let t: Date; let v: Double }

var failures = 0
func check(_ cond: Bool, _ msg: String) {
    print(cond ? "  ok   \(msg)" : "  FAIL \(msg)")
    if !cond { failures += 1 }
}

// now == t0 for every forecast call below; `at(secsFromNow, v)` builds a sample relative to now.
let t0 = Date(timeIntervalSince1970: 1_000_000)
func at(_ secsFromNow: Double, _ v: Double) -> TimedSample { TimedSample(t: t0.addingTimeInterval(secsFromNow), v: v) }

print("compactETA:")
check(compactETA(0) == "<1m", "0s -> <1m")
check(compactETA(30) == "<1m", "30s -> <1m")
check(compactETA(59) == "<1m", "59s (still 0 whole minutes) -> <1m")
check(compactETA(60) == "1m", "60s -> 1m")
check(compactETA(45 * 60) == "45m", "45m -> 45m")
check(compactETA(3600) == "1h", "exactly 1h -> 1h (no trailing 0m)")
check(compactETA(2 * 3600 + 10 * 60) == "2h 10m", "2h10m -> 2h 10m")
check(compactETA(23 * 3600 + 59 * 60) == "23h 59m", "23h59m -> 23h 59m")
check(compactETA(24 * 3600) == "1d", "exactly 24h -> 1d (no trailing 0h)")
check(compactETA(25 * 3600) == "1d 1h", "25h -> 1d 1h")
check(compactETA(3 * 86400 + 4 * 3600) == "3d 4h", "docstring example 3d 4h")

print("LiveState.label:")
check(LiveState.live.label == "LIVE", "live -> LIVE")
check(LiveState.est.label == "EST", "est -> EST")
check(LiveState.stale.label == "STALE", "stale -> STALE")
check(LiveState.rateLimited.label == "LIMITED", "rateLimited -> LIMITED")
check(LiveState.offline.label == "OFFLINE", "offline -> OFFLINE")

print("LiveState.isLive:")
check(LiveState.live.isLive == true, "only .live is live")
check(LiveState.est.isLive == false, ".est is not live")
check(LiveState.stale.isLive == false, ".stale is not live")

// Scenario A: steady rise, no reset. slope 0.0001/s over the last 2000s; current 0.6 -> 4000s (66.67m).
print("forecastToLimit / forecastMinutes, rising trend:")
let riseA = [at(-2000, 0.4), at(-1000, 0.5), at(0, 0.6)]
check(forecastToLimit(riseA, current: 0.6, resetAt: nil, now: t0) == "~1h 6m to limit",
      "A: 4000s ETA formats as ~1h 6m to limit")
if let m = forecastMinutes(riseA, current: 0.6, resetAt: nil, now: t0) {
    check(abs(m - 4000.0 / 60.0) < 1e-4, "A: forecastMinutes ~= 66.67")
} else { check(false, "A: forecastMinutes should be non-nil") }

// Scenario B: an old sample outside the 90-min window must be ignored (recent slice reflects pace).
// Using all four points would give ~1h39m; using only the recent three gives ~2h4m.
print("forecast uses only the recent (<=90m) slice:")
let mixed = [at(-7200, 0.1), at(-3600, 0.4), at(-1800, 0.5), at(0, 0.6)]
check(forecastToLimit(mixed, current: 0.585, resetAt: nil, now: t0) == "~2h 4m to limit",
      "B: recent-only slope -> ~2h 4m (not the ~1h39m an all-points slope would give)")
if let m = forecastMinutes(mixed, current: 0.585, resetAt: nil, now: t0) {
    check(abs(m - 124.5) < 1e-3, "B: forecastMinutes ~= 124.5")
} else { check(false, "B: forecastMinutes should be non-nil") }

// Scenario C: flat trend -> no ETA (slope guard).
print("flat trend -> nil:")
let flat = [at(-3600, 0.5), at(-1800, 0.5), at(0, 0.5)]
check(forecastToLimit(flat, current: 0.5, resetAt: nil, now: t0) == nil, "C: flat -> toLimit nil")
check(forecastMinutes(flat, current: 0.5, resetAt: nil, now: t0) == nil, "C: flat -> minutes nil")

// Scenario D: shrinking trend -> no ETA (negative slope).
print("shrinking trend -> nil:")
let down = [at(-3600, 0.7), at(0, 0.5)]
check(forecastToLimit(down, current: 0.5, resetAt: nil, now: t0) == nil, "D: shrinking -> toLimit nil")
check(forecastMinutes(down, current: 0.5, resetAt: nil, now: t0) == nil, "D: shrinking -> minutes nil")

// Scenario E: current outside the useful (0, 0.999) band -> nil.
print("current at/over the band edges -> nil:")
check(forecastToLimit(riseA, current: 0.0, resetAt: nil, now: t0) == nil, "E: current 0 -> toLimit nil")
check(forecastMinutes(riseA, current: 0.0, resetAt: nil, now: t0) == nil, "E: current 0 -> minutes nil")
check(forecastToLimit(riseA, current: 1.0, resetAt: nil, now: t0) == nil, "E: current 1.0 -> toLimit nil")
check(forecastMinutes(riseA, current: 1.0, resetAt: nil, now: t0) == nil, "E: current 1.0 -> minutes nil")
check(forecastToLimit(riseA, current: 0.999, resetAt: nil, now: t0) == nil, "E: current 0.999 (not < 0.999) -> nil")

// Scenario F: too-short a time span to trust a slope (dt <= 120s) -> nil.
print("time span too short -> nil:")
let brief = [at(-60, 0.5), at(0, 0.6)]
check(forecastToLimit(brief, current: 0.6, resetAt: nil, now: t0) == nil, "F: dt 60s -> toLimit nil")
check(forecastMinutes(brief, current: 0.6, resetAt: nil, now: t0) == nil, "F: dt 60s -> minutes nil")

// Scenario G: reset lands before the projected cap hit -> nil; a later reset lets the ETA through.
print("reset-before-cap suppresses the ETA:")
check(forecastToLimit(riseA, current: 0.6, resetAt: t0.addingTimeInterval(1800), now: t0) == nil,
      "G: reset in 30m (< 66.67m ETA) -> toLimit nil")
check(forecastMinutes(riseA, current: 0.6, resetAt: t0.addingTimeInterval(1800), now: t0) == nil,
      "G: reset in 30m -> minutes nil")
check(forecastToLimit(riseA, current: 0.6, resetAt: t0.addingTimeInterval(7200), now: t0) == "~1h 6m to limit",
      "G: reset in 2h (> ETA) -> ETA passes through")

// Scenario H: projection beyond the ~3-week horizon -> nil (slope just above the flat threshold).
print("beyond the sane horizon -> nil:")
let creep = [at(-3600, 0.5), at(0, 0.5004)]
check(forecastToLimit(creep, current: 0.5, resetAt: nil, now: t0) == nil, "H: >3wk horizon -> toLimit nil")
check(forecastMinutes(creep, current: 0.5, resetAt: nil, now: t0) == nil, "H: >3wk horizon -> minutes nil")

// Scenario I: no samples at all -> nil.
print("empty samples -> nil:")
check(forecastToLimit([], current: 0.5, resetAt: nil, now: t0) == nil, "I: empty -> toLimit nil")
check(forecastMinutes([], current: 0.5, resetAt: nil, now: t0) == nil, "I: empty -> minutes nil")

print(failures == 0 ? "\nALL PASS" : "\n\(failures) FAILURE(S)")
exit(failures == 0 ? 0 : 1)
