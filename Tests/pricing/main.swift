import Foundation

// Behavioral tests for the cost model in Sources/Pricing.swift (compiled headlessly with that file).

var failures = 0
func check(_ cond: Bool, _ msg: String) {
    print(cond ? "  ok   \(msg)" : "  FAIL \(msg)")
    if !cond { failures += 1 }
}
func approx(_ a: Double, _ b: Double, _ tol: Double, _ msg: String) { check(abs(a - b) < tol, msg + " (got \(a))") }

print("priceFor:")
check(priceFor(model: "claude-opus-4-6").input == 5 && priceFor(model: "claude-opus-4-6").output == 25, "opus 4.6 -> 5/25")
// The ids below are the REAL ones, exactly as they appear in the logs. The previous versions of
// these checks used shapes nobody ever writes ("claude-opus-4-0"), so they passed against a rule
// that could never fire in practice: every Opus 4.0 token was billed at a third of its true rate
// and the suite reported all clear. A pricing test that does not use real model ids is worse than
// no pricing test.
check(priceFor(model: "claude-opus-4-1-20250805").input == 15, "Opus 4.1, real id -> 15/75")
check(priceFor(model: "claude-opus-4-20250514").input == 15
      && priceFor(model: "claude-opus-4-20250514").output == 75, "Opus 4.0, real id -> 15/75")
// The dated form must be matched by its year, not by a bare "opus-4" prefix, or the current models
// get charged triple.
check(priceFor(model: "claude-opus-4-5-20251101").input == 5, "Opus 4.5 stays at the new rate")
check(priceFor(model: "claude-opus-4-8").input == 5, "and so does Opus 4.8, the one actually in use")
check(priceFor(model: "claude-opus-5").input == 5, "and Opus 5")
check(priceFor(model: "claude-sonnet-4-5").input == 3 && priceFor(model: "claude-sonnet-4-5").output == 15, "sonnet -> 3/15")
check(priceFor(model: "claude-haiku-4-5").input == 1 && priceFor(model: "claude-haiku-4-5").output == 5, "haiku -> 1/5")
check(priceFor(model: "fable-1").input == 10 && priceFor(model: "fable-1").output == 50, "fable -> 10/50")
check(priceFor(model: "something-unknown").input == 3 && priceFor(model: "something-unknown").output == 15, "unknown -> 3/15 default")
check(priceFor(model: "CLAUDE-OPUS-4-6").input == 5, "case-insensitive (uppercase opus -> 5)")
// The real Opus 3 id reads "3-opus", not "opus-3", so the old check never matched it either and
// Opus 3 priced as a current model. Retired and unused, but the fix costs one string.
check(priceFor(model: "claude-3-opus-20240229").input == 15, "Opus 3, real id -> 15/75")

print("tokenCost:")
approx(tokenCost(model: "claude-opus-4-6", input: 0, output: 0, cache5m: 0, cache1h: 0, cacheRead: 0), 0, 1e-9, "all zero -> $0")
approx(tokenCost(model: "claude-opus-4-6", input: 1_000_000, output: 1_000_000, cache5m: 0, cache1h: 0, cacheRead: 0), 30, 1e-9, "opus 1M in + 1M out -> $30")
approx(tokenCost(model: "claude-sonnet-4-5", input: 1_000_000, output: 0, cache5m: 1_000_000, cache1h: 1_000_000, cacheRead: 1_000_000), 13.05, 1e-6, "sonnet cache mix -> $13.05 (3 + 3.75 + 6 + 0.3)")
approx(tokenCost(model: "claude-haiku-4-5", input: 2_000_000, output: 0, cache5m: 0, cache1h: 0, cacheRead: 0), 2, 1e-9, "haiku 2M in -> $2")

print(failures == 0 ? "\nALL PASS" : "\n\(failures) FAILURE(S)")
exit(failures == 0 ? 0 : 1)
