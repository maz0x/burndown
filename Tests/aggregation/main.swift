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
check(unk.first?.key == kUnknownProject, "a record with no project reads as \"No folder recorded\"")
check(!kUnknownProject.hasPrefix("("), "and not as a parenthesised placeholder the reader has to decode")

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

// --- quiet days must survive as zeros ---
// Two records three days apart: the days between them still have to exist, or the chart's axis
// jumps from 01 to 05 and reads as if those days never happened.
let sparse = [
    UsageRecord(date: d("2026-06-01T10:00:00Z"), model: "claude-opus-5", project: "a", session: "s",
                input: 10, output: 0, cache5m: 0, cache1h: 0, cacheRead: 0),
    UsageRecord(date: d("2026-06-04T10:00:00Z"), model: "claude-opus-5", project: "a", session: "s",
                input: 20, output: 0, cache5m: 0, cache1h: 0, cacheRead: 0),
]
let filled = rollupByDaysBack(sparse, days: 5, now: d("2026-06-05T12:00:00Z"), calendar: utc)
check(filled.count == 5, "asking for five days back gives five days")
check(filled.map(\.key) == ["2026-06-01", "2026-06-02", "2026-06-03", "2026-06-04", "2026-06-05"],
      "and they are consecutive, oldest first, with no gaps")
check(filled[1].tokens == 0 && filled[2].tokens == 0, "the quiet days come back as zeros")
check(filled[0].tokens == 10 && filled[3].tokens == 20, "the busy days keep their numbers")
check(rollupByDaysBack([], days: 3, now: d("2026-06-05T12:00:00Z"), calendar: utc).count == 3,
      "no records at all still gives a full run of zero days")
// Records older than the window must not leak in.
let old = [UsageRecord(date: d("2026-05-01T10:00:00Z"), model: "claude-opus-5", project: "a",
                       session: "s", input: 999, output: 0, cache5m: 0, cache1h: 0, cacheRead: 0)]
check(rollupByDaysBack(old + sparse, days: 5, now: d("2026-06-05T12:00:00Z"), calendar: utc)
        .reduce(0) { $0 + $1.tokens } == 30, "older records stay outside the window")

// --- one conversation split across several log files ---
// Claude Code opens a new log when a chat is resumed or compacted, so a long piece of work shows
// up as several files with the same title. Listed raw that is four identical rows.
let split = [
    SessionUsage(id: "/1.jsonl", title: "Long piece of work", project: "Home folder",
                 date: d("2026-06-01T10:00:00Z"), tokens: 100, cost: 1),
    SessionUsage(id: "/2.jsonl", title: "Long piece of work", project: "Home folder",
                 date: d("2026-06-02T10:00:00Z"), tokens: 200, cost: 2),
    SessionUsage(id: "/3.jsonl", title: "Something else", project: "Home folder",
                 date: d("2026-06-01T10:00:00Z"), tokens: 50, cost: 0.5),
    // Same title, DIFFERENT project: a genuinely separate piece of work, kept separate.
    SessionUsage(id: "/4.jsonl", title: "Long piece of work", project: "site",
                 date: d("2026-06-01T10:00:00Z"), tokens: 30, cost: 0.3),
]
let merged = mergeSessions(split)
check(merged.count == 3, "same title and project merge, a different project does not")
let big = merged.first { $0.title == "Long piece of work" && $0.project == "Home folder" }!
check(big.tokens == 300 && big.cost == 3, "tokens and cost add up")
check(big.parts == 2, "and the row says how many logs it took")
check(big.date == d("2026-06-02T10:00:00Z"), "the date is the most recent of them")
check(merged.first { $0.project == "site" }?.parts == 1, "a single-log conversation stays a single part")
check(mergeSessions([]).isEmpty, "nothing in, nothing out")
// Two different untitled chats on the same day share a GENERATED label. Merging on that would add
// together work that has nothing to do with each other.
let untitled = [
    SessionUsage(id: "/u1.jsonl", title: "Untitled chat \u{00B7} Aug 1", project: "Home folder",
                 date: d("2026-06-01T10:00:00Z"), tokens: 100, cost: 1),
    SessionUsage(id: "/u2.jsonl", title: "Untitled chat \u{00B7} Aug 1", project: "Home folder",
                 date: d("2026-06-01T18:00:00Z"), tokens: 900, cost: 9),
]
check(mergeSessions(untitled).count == 2, "untitled chats are never merged into each other")
// Order in equals order out, so the list does not reshuffle itself between renders.
check(merged.map(\.title) == ["Long piece of work", "Something else", "Long piece of work"],
      "first-seen order is preserved")

if failures == 0 { print("ALL AGGREGATION TESTS PASSED") }
else { print("\(failures) FAILURE(S)"); exit(1) }
