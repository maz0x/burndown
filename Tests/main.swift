import Foundation

// Unit tests for the pure forecast logic. This file is compiled together with ONLY
// Sources/Forecast.swift (see run-tests.sh), so it redeclares the tiny TimedSample value
// that Forecast.swift depends on (the app's real one lives in LiveActivity.swift).
struct TimedSample: Equatable { let t: Date; let v: Double }

var failures = 0
func check(_ cond: Bool, _ msg: String) {
    if cond { print("  ok   \(msg)") } else { failures += 1; print("  FAIL \(msg)") }
}
func approx(_ got: Double?, _ want: Double, _ tol: Double, _ msg: String) {
    guard let got else { failures += 1; print("  FAIL \(msg) (got nil, want ~\(want))"); return }
    check(abs(got - want) <= tol, "\(msg) (got \(got), want ~\(want))")
}

let now = Date(timeIntervalSince1970: 1_000_000)
func s(_ minsAgo: Double, _ v: Double) -> TimedSample { TimedSample(t: now.addingTimeInterval(-minsAgo * 60), v: v) }

print("forecastMinutes:")
// Steady climb 0.50 -> 0.70 over 60 min; remaining 0.30 at that slope = 90 min.
approx(forecastMinutes([s(60, 0.50), s(30, 0.60), s(0, 0.70)], current: 0.70, resetAt: nil, now: now),
       90, 5, "linear climb projects ~90 min")
// Flat usage: no slope, no ETA.
check(forecastMinutes([s(60, 0.50), s(30, 0.50), s(0, 0.50)], current: 0.50, resetAt: nil, now: now) == nil,
      "flat usage -> nil")
// Shrinking usage: never reaches the cap.
check(forecastMinutes([s(60, 0.60), s(30, 0.55), s(0, 0.50)], current: 0.50, resetAt: nil, now: now) == nil,
      "shrinking usage -> nil")
// Would hit in ~90 min but the window resets in 10 min: nothing useful to say.
check(forecastMinutes([s(60, 0.50), s(30, 0.60), s(0, 0.70)], current: 0.70,
                      resetAt: now.addingTimeInterval(10 * 60), now: now) == nil,
      "resets before the cap -> nil")
// Already at the cap.
check(forecastMinutes([s(60, 0.90), s(30, 0.95), s(0, 1.0)], current: 1.0, resetAt: nil, now: now) == nil,
      "already at cap -> nil")
// Time span too short to trust a slope (< 120s).
check(forecastMinutes([s(1, 0.50), s(0, 0.60)], current: 0.60, resetAt: nil, now: now) == nil,
      "span under 120s -> nil")

print("forecastToLimit:")
check(forecastToLimit([s(60, 0.50), s(30, 0.60), s(0, 0.70)], current: 0.70, resetAt: nil, now: now) == "~1h 30m to limit",
      "linear climb -> '~1h 30m to limit'")
check(forecastToLimit([s(60, 0.50), s(0, 0.50)], current: 0.50, resetAt: nil, now: now) == nil,
      "flat -> nil")

print("compactETA:")
check(compactETA(30) == "<1m", "30s -> <1m")
check(compactETA(45 * 60) == "45m", "45m")
check(compactETA(2 * 3600) == "2h", "exact 2h -> 2h")
check(compactETA(130 * 60) == "2h 10m", "2h 10m")
check(compactETA(3 * 86400 + 4 * 3600) == "3d 4h", "3d 4h")
check(compactETA(2 * 86400) == "2d", "exact 2d -> 2d")

print("sparse fallback (recent <3 samples -> full history):")
// Only ONE sample falls in the last 90 min, so `recent` (count 1) is too thin and the
// code must fall back to the full history. If it did NOT fall back, first==last -> dt 0 -> nil;
// a non-nil ~450 min proves the fallback slice is used.
approx(forecastMinutes([s(200, 0.30), s(150, 0.40), s(20, 0.50)], current: 0.50, resetAt: nil, now: now),
       450, 5, "fallback to full history projects ~450 min")
check(forecastToLimit([s(200, 0.30), s(150, 0.40), s(20, 0.50)], current: 0.50, resetAt: nil, now: now) == "~7h 30m to limit",
      "fallback to full history -> '~7h 30m to limit'")
// With >=3 recent samples the RECENT slice wins over the older flat history: old-flat + recent-steep
// projects ~120 min off the recent slope, not ~300 min it would give off the full span.
approx(forecastMinutes([s(200, 0.50), s(80, 0.50), s(60, 0.50), s(30, 0.60), s(0, 0.70)], current: 0.70, resetAt: nil, now: now),
       120, 5, "recent slice used when >=3 recent samples (~120 min, not ~300)")

print("slope / span boundaries:")
// dt exactly 120s must be rejected (guard is dt > 120), 180s accepted.
check(forecastMinutes([s(2, 0.50), s(0, 0.60)], current: 0.60, resetAt: nil, now: now) == nil,
      "dt == 120s -> nil (boundary)")
approx(forecastMinutes([s(3, 0.50), s(0, 0.60)], current: 0.60, resetAt: nil, now: now),
       12, 2, "dt 180s climb -> ~12 min")
check(forecastToLimit([s(2, 0.50), s(0, 0.60)], current: 0.60, resetAt: nil, now: now) == nil,
      "forecastToLimit dt == 120s -> nil (boundary)")
// Positive but ultra-shallow slope whose ETA exceeds the ~3-week sane horizon -> nil.
check(forecastMinutes([s(600, 0.500), s(0, 0.504)], current: 0.504, resetAt: nil, now: now) == nil,
      "slope positive but ETA > 21 days -> nil (horizon edge)")
// current at/below 0 is rejected.
check(forecastMinutes([s(60, 0.50), s(0, 0.50)], current: 0.0, resetAt: nil, now: now) == nil,
      "current == 0 -> nil")
check(forecastToLimit([s(60, 0.50), s(30, 0.60), s(0, 0.70)], current: 0.0, resetAt: nil, now: now) == nil,
      "forecastToLimit current == 0 -> nil")

print("resetAt edges:")
// The ~90-min climb hits the cap in exactly 5400s. Reset exactly AT the hit is allowed
// (guard is now+secs > r, strict), reset 1s BEFORE the hit suppresses the forecast.
approx(forecastMinutes([s(60, 0.50), s(30, 0.60), s(0, 0.70)], current: 0.70,
                       resetAt: now.addingTimeInterval(5400), now: now),
       90, 1, "reset exactly at hit -> still forecasts (~90 min)")
check(forecastMinutes([s(60, 0.50), s(30, 0.60), s(0, 0.70)], current: 0.70,
                      resetAt: now.addingTimeInterval(5399), now: now) == nil,
      "reset 1s before hit -> nil")

print(failures == 0 ? "\nALL PASS" : "\n\(failures) FAILURE(S)")
exit(failures == 0 ? 0 : 1)
