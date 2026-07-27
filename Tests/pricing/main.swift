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
check(priceFor(model: "claude-opus-4-1").input == 15, "opus-4-1 id -> 15 (old)")
check(priceFor(model: "claude-opus-4-0").input == 15, "opus-4-0 id -> 15 (old)")
check(priceFor(model: "claude-sonnet-4-5").input == 3 && priceFor(model: "claude-sonnet-4-5").output == 15, "sonnet -> 3/15")
check(priceFor(model: "claude-haiku-4-5").input == 1 && priceFor(model: "claude-haiku-4-5").output == 5, "haiku -> 1/5")
check(priceFor(model: "fable-1").input == 10 && priceFor(model: "fable-1").output == 50, "fable -> 10/50")
check(priceFor(model: "something-unknown").input == 3 && priceFor(model: "something-unknown").output == 15, "unknown -> 3/15 default")
check(priceFor(model: "CLAUDE-OPUS-4-6").input == 5, "case-insensitive (uppercase opus -> 5)")
// QUIRK (behavior preserved, deliberately not fixed): the real Opus-3 id is "claude-3-opus-*", which the
// `opus-3` substring check does NOT match, so Opus 3 currently prices as NEW ($5), not old ($15).
// Negligible today (Opus 3 is effectively unused), left unchanged. This test pins the current behavior.
check(priceFor(model: "claude-3-opus-20240229").input == 5, "claude-3-opus id currently prices as 5 (opus-3 check misses '3-opus' order) [QUIRK]")

print("tokenCost:")
approx(tokenCost(model: "claude-opus-4-6", input: 0, output: 0, cache5m: 0, cache1h: 0, cacheRead: 0), 0, 1e-9, "all zero -> $0")
approx(tokenCost(model: "claude-opus-4-6", input: 1_000_000, output: 1_000_000, cache5m: 0, cache1h: 0, cacheRead: 0), 30, 1e-9, "opus 1M in + 1M out -> $30")
approx(tokenCost(model: "claude-sonnet-4-5", input: 1_000_000, output: 0, cache5m: 1_000_000, cache1h: 1_000_000, cacheRead: 1_000_000), 13.05, 1e-6, "sonnet cache mix -> $13.05 (3 + 3.75 + 6 + 0.3)")
approx(tokenCost(model: "claude-haiku-4-5", input: 2_000_000, output: 0, cache5m: 0, cache1h: 0, cacheRead: 0), 2, 1e-9, "haiku 2M in -> $2")

print(failures == 0 ? "\nALL PASS" : "\n\(failures) FAILURE(S)")
exit(failures == 0 ? 0 : 1)
