import Foundation

// Headless tests for Sources/Aggregation.swift, compiled together with Sources/Pricing.swift
// so the cost math is exercised against the REAL rate table. No XCTest: a tiny assert plus a
// non-zero exit on any failure, matching the other run-*-tests.sh suites.

var failures = 0
func check(_ cond: Bool, _ msg: String) {
    if cond { print("  ok: \(msg)") } else { print("  FAIL: \(msg)"); failures += 1 }
}
func approx(_ a: Double, _ b: Double, _ eps: Double = 1e-6) -> Bool { abs(a - b) < eps }

// Deterministic UTC calendar so day bucketing does not depend on the test machine's timezone.
var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(identifier: "UTC")!
func d(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

let recs = [
    // opus, 1M fresh input
    UsageRecord(date: d("2026-06-01T10:00:00Z"), model: "claude-opus-4-8",  project: "alpha",
                input: 1_000_000, output: 0, cache5m: 0, cache1h: 0, cacheRead: 0),
    // sonnet, 1M fresh output
    UsageRecord(date: d("2026-06-01T11:00:00Z"), model: "claude-sonnet-4-6", project: "alpha",
                input: 0, output: 1_000_000, cache5m: 0, cache1h: 0, cacheRead: 0),
    // opus, 1M cache read (next day, different project)
    UsageRecord(date: d("2026-06-02T09:00:00Z"), model: "claude-opus-4-8",  project: "beta",
                input: 0, output: 0, cache5m: 0, cache1h: 0, cacheRead: 1_000_000),
]

// --- totals ---
let t = totals(recs)
check(t.records == 3, "totals counts all records")
check(t.input == 1_000_000 && t.output == 1_000_000 && t.cacheRead == 1_000_000, "totals sum token buckets")
check(t.tokens == 3_000_000, "totals token sum = 3M")
check(t.freshTokens == 2_000_000 && t.cacheTokens == 1_000_000, "fresh vs cache split")

// --- cost integration with real Pricing ---
// opus input $5/M = 5.00 ; sonnet output $15/M = 15.00 ; opus cacheRead 0.1*5 = $0.50/M = 0.50
let expectedCost = 5.0 + 15.0 + 0.5
check(approx(t.cost, expectedCost), "totals cost uses real Pricing table (\(t.cost) ~ \(expectedCost))")

// --- model family normalization ---
check(modelFamily("claude-opus-4-8") == "Opus", "opus -> Opus")
check(modelFamily("claude-sonnet-4-6") == "Sonnet", "sonnet -> Sonnet")
check(modelFamily("claude-haiku-4-5") == "Haiku", "haiku -> Haiku")
check(modelFamily("gpt-5") == "Other", "unknown -> Other")

// --- rollup by model family (token-desc) ---
let byModel = rollupByModelFamily(recs)
check(byModel.count == 2, "two model families")
check(byModel.first?.key == "Opus" && byModel.first?.tokens == 2_000_000, "Opus leads with 2M")
check(byModel.last?.key == "Sonnet" && byModel.last?.tokens == 1_000_000, "Sonnet 1M")

// --- rollup by project (token-desc) ---
let byProj = rollupByProject(recs)
check(byProj.first?.key == "alpha" && byProj.first?.tokens == 2_000_000, "alpha leads (2M)")
check(byProj.contains { $0.key == "beta" && $0.tokens == 1_000_000 }, "beta 1M")
let unk = rollupByProject([UsageRecord(date: d("2026-06-01T10:00:00Z"), model: "claude-haiku-4-5",
                                       project: "", input: 10, output: 0, cache5m: 0, cache1h: 0, cacheRead: 0)])
check(unk.first?.key == "(unknown)", "empty project -> (unknown)")

// --- rollup by session (per-chat) ---
let sessRecs = [
    UsageRecord(date: d("2026-06-01T10:00:00Z"), model: "claude-opus-4-8", project: "alpha", session: "chatA",
                input: 100, output: 0, cache5m: 0, cache1h: 0, cacheRead: 0),
    UsageRecord(date: d("2026-06-01T11:00:00Z"), model: "claude-opus-4-8", project: "alpha", session: "chatA",
                input: 200, output: 0, cache5m: 0, cache1h: 0, cacheRead: 0),
    UsageRecord(date: d("2026-06-01T12:00:00Z"), model: "claude-opus-4-8", project: "beta", session: "chatB",
                input: 50, output: 0, cache5m: 0, cache1h: 0, cacheRead: 0),
]
let bySession = rollupBySession(sessRecs)
check(bySession.count == 2, "two sessions")
check(bySession.first?.key == "chatA" && bySession.first?.tokens == 300, "chatA aggregates to 300 tokens")

// --- rollup by day (chronological) ---
let byDay = rollupByDay(recs, calendar: utc)
check(byDay.count == 2, "two distinct days")
check(byDay.first?.key == "2026-06-01" && byDay.last?.key == "2026-06-02", "days in chronological order")
check(byDay.first?.records == 2, "2026-06-01 has 2 records")

// --- window filter ---
let win = recordsInWindow(recs, since: d("2026-06-02T00:00:00Z"), until: d("2026-06-03T00:00:00Z"))
check(win.count == 1 && win.first?.project == "beta", "window keeps only the 2026-06-02 record")

// --- empty input is safe ---
check(totals([]).tokens == 0 && rollupByDay([], calendar: utc).isEmpty, "empty records aggregate cleanly")

if failures == 0 { print("ALL AGGREGATION TESTS PASSED") }
else { print("\(failures) FAILURE(S)"); exit(1) }
