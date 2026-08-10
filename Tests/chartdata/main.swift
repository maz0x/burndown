import Foundation

// Redeclare the tiny value types here (the real ones live in LiveActivity.swift / Views.swift, which
// pull in Combine / SwiftUI). Same convention as Tests/main.swift, so the headless compile is self-contained.
struct TimedSample: Equatable { let t: Date; let v: Double }
struct ChartPoint: Identifiable { let id: Int; let t: Date; let v: Double; let seg: Int }

var failures = 0
func check(_ cond: Bool, _ msg: String) {
    print(cond ? "  ok   \(msg)" : "  FAIL \(msg)")
    if !cond { failures += 1 }
}

let t0 = Date(timeIntervalSince1970: 1_000_000)
func at(_ secs: Double, _ v: Double) -> TimedSample { TimedSample(t: t0.addingTimeInterval(secs), v: v) }

print("ema:")
check(ema([], 0.5).isEmpty, "empty -> empty")
let e1 = ema([at(0, 10), at(1, 20), at(2, 30)], 0.5)
check(e1.count == 3, "preserves count")
check(e1[0].v == 10, "first seeded to first value")
check(e1[1].v == 15, "0.5*20 + 0.5*10 = 15")
check(e1[2].v == 22.5, "0.5*30 + 0.5*15 = 22.5")
check(e1.map { $0.t } == [at(0, 0), at(1, 0), at(2, 0)].map { $0.t }, "timestamps preserved")

print("segmentize:")
let segs = segmentize([at(0, 1), at(10, 2), at(400, 3), at(410, 4)], gap: 120)
check(segs.map { $0.seg } == [0, 0, 1, 1], "a gap > 120s starts a new segment")
check(segs.map { $0.id } == [0, 1, 2, 3], "ids are the original indices")
let clamped = segmentize([at(0, 5), at(1, 100)], gap: 120, clampTo: 50)
check(clamped.map { $0.v } == [5, 50], "values clamp to clampTo")
check(segmentize([], gap: 120).isEmpty, "empty -> empty")

print("bucketed:")
check(bucketed([at(0, 1), at(1, 2)], lower: t0, upper: t0.addingTimeInterval(2), buckets: 5, pickMax: true).count == 2,
      "count <= buckets -> returned unchanged")
let dense = [at(2, 9), at(5, 1), at(12, 8), at(15, 2), at(22, 7), at(25, 3)]  // 2 per 10s bucket, interior times
let bMax = bucketed(dense, lower: t0, upper: t0.addingTimeInterval(30), buckets: 3, pickMax: true)
check(bMax.count == 3, "downsamples to 3 buckets")
check(bMax.map { $0.v } == [9, 8, 7], "pickMax keeps each bucket's peak")
let bLast = bucketed(dense, lower: t0, upper: t0.addingTimeInterval(30), buckets: 3, pickMax: false)
check(bLast.map { $0.v } == [1, 2, 3], "pickMax=false keeps each bucket's latest")

print("nearestSample:")
let pool = [at(0, 1), at(100, 2), at(300, 3)]
check(nearestSample(pool, to: t0.addingTimeInterval(110))?.v == 2, "closest by time")
check(nearestSample(pool, to: t0.addingTimeInterval(290))?.v == 3, "closest by time (later)")
check(nearestSample([], to: t0) == nil, "empty -> nil")

// MARK: modelWeekShareSeries - per-model lines on the "Session + week %" chart
do {
    let now = Date()
    let reset = now.addingTimeInterval(3 * 86_400)          // weekly window resets in 3 days
    func rec(_ ago: Double, _ model: String, _ tok: Int) -> UsageRecord {
        UsageRecord(date: now.addingTimeInterval(-ago), model: model, project: "p", session: "s",
                    input: tok, output: 0, cache5m: 0, cache1h: 0, cacheRead: 0)
    }
    let records = [rec(4 * 3600, "claude-fable-5", 100), rec(2 * 3600, "claude-fable-5", 300),
                   rec(1 * 3600, "claude-opus-4-8", 100)]

    let out = modelWeekShareSeries(records: records, weeklyPct: 0.50, weeklyResetAt: reset, now: now)
    check(out.count == 2, "every model used gets a line, capped or not")
    check(out.map(\.label) == ["Fable", "Opus"], "biggest consumer leads the legend")

    // The whole point of the shared calibration: the model lines must ADD UP to the weekly
    // percentage the card shows, so the chart can never contradict the number above it.
    let ends = out.map { $0.samples.last?.v ?? 0 }
    check(abs(ends.reduce(0, +) - 0.50) < 0.0001, "model lines sum to the reported weekly percentage")

    // 400 of 500 tokens are Fable, so Fable owns 80% of the 50% consumed.
    let fable = out.first { $0.label == "Fable" }!
    check(abs((fable.samples.last?.v ?? 0) - 0.40) < 0.0001, "each line is its true share of the week")
    check(fable.samples.first?.v == 0, "and starts the week at zero")
    let rising = zip(fable.samples, fable.samples.dropFirst()).allSatisfy { $0.v <= $1.v + 0.0001 }
    check(rising, "cumulative usage never goes down")

    // An uncapped model still appears. This is the bug the measure change fixes: under the old
    // per-cap measure Opus had no weekly ceiling of its own, so it drew no line at all.
    check(out.contains { $0.label == "Opus" }, "a model with no weekly cap of its own still appears")

    // No weekly reading means no scale to calibrate against, so there is nothing honest to draw.
    let zeroed = modelWeekShareSeries(records: records, weeklyPct: 0, weeklyResetAt: reset, now: now)
    check(zeroed.isEmpty, "0% weekly is skipped rather than dividing by zero")

    // Records from before this weekly window must not count toward it.
    let old = [rec(9 * 86_400, "claude-fable-5", 9_999)] + records
    let scoped = modelWeekShareSeries(records: old, weeklyPct: 0.50, weeklyResetAt: reset, now: now)
    check(abs((scoped.first { $0.label == "Fable" }?.samples.last?.v ?? 0) - 0.40) < 0.0001,
          "last week's usage does not drag this week's line")
    check(abs(scoped.map { $0.samples.last?.v ?? 0 }.reduce(0, +) - 0.50) < 0.0001,
          "and the sum still lands on the weekly reading")
}


// With no weekly reset known the app falls back to a rolling seven days everywhere else, so the
// model lines have to calibrate against the SAME seven days. Anchoring at the earliest record
// instead spread a seven-day percentage over however much history was retained, so every line came
// out a fraction of its true height exactly when the service was unreachable.
print("no reset time known:")
do {
    let now = Date()
    var recs: [UsageRecord] = []
    // 30 days of history, but only the last 7 belong to this week.
    for d in 0..<30 {
        recs.append(UsageRecord(date: now.addingTimeInterval(-Double(d) * 86_400 - 3600),
                                model: "claude-opus-5", project: "p", session: "s",
                                input: 1000, output: 0, cache5m: 0, cache1h: 0, cacheRead: 0))
    }
    let series = modelWeekShareSeries(records: recs, weeklyPct: 70, weeklyResetAt: nil, now: now)
    let top = series.first?.samples.last?.v ?? 0
    check(abs(top - 70) < 0.01, "the one model in use ends at the full weekly reading, not a fraction of it")
    let firstT = series.first?.samples.first?.t ?? now
    check(abs(firstT.timeIntervalSince(now) + 7 * 86_400) < 2, "and the window opens exactly seven days back")
    // A reset time that has already passed is stale, and must not be trusted over the fallback.
    let stale = modelWeekShareSeries(records: recs, weeklyPct: 70,
                                     weeklyResetAt: now.addingTimeInterval(-3 * 86_400), now: now)
    check(abs((stale.first?.samples.last?.v ?? 0) - 70) < 0.01,
          "a reset time that already passed falls back too, rather than anchoring ten days ago")
}

// A model first used on Friday should read zero all week, then rise. Interpolating from the week's
// opening straight to that first point draws a ramp across days it was never used.
print("no phantom ramp before a model's first use:")
do {
    let now = Date()
    let reset = now.addingTimeInterval(2 * 86_400)          // week opened 5 days ago
    let recs = [UsageRecord(date: now.addingTimeInterval(-3600), model: "claude-opus-5",
                            project: "p", session: "s",
                            input: 1000, output: 0, cache5m: 0, cache1h: 0, cacheRead: 0)]
    let s = modelWeekShareSeries(records: recs, weeklyPct: 40, weeklyResetAt: reset, now: now).first?.samples ?? []
    check(s.count >= 3, "the line carries an opening anchor, a held zero, then the real point")
    check(s[0].v == 0 && s[1].v == 0, "it is still at zero immediately before the first record")
    check(s[1].t > s[0].t && s[1].t < now.addingTimeInterval(-3599),
          "and that held zero sits just before the record, not at the window's opening")
}

// Cache READS are a tenth the price and many times the volume, so counting them measures re-reading
// rather than work. The live rate has always excluded them; the week share now agrees.
print("one token basis:")
do {
    let now = Date()
    let reset = now.addingTimeInterval(86_400)
    let recs = [
        UsageRecord(date: now.addingTimeInterval(-7200), model: "claude-opus-5", project: "p", session: "s",
                    input: 100, output: 100, cache5m: 0, cache1h: 0, cacheRead: 0),
        UsageRecord(date: now.addingTimeInterval(-3600), model: "claude-sonnet-5", project: "p", session: "s",
                    input: 100, output: 100, cache5m: 0, cache1h: 0, cacheRead: 1_000_000),
    ]
    let s = modelWeekShareSeries(records: recs, weeklyPct: 50, weeklyResetAt: reset, now: now)
    let opus = s.first { $0.label == "Opus" }?.samples.last?.v ?? 0
    let sonnet = s.first { $0.label == "Sonnet" }?.samples.last?.v ?? 0
    check(abs(opus - sonnet) < 0.01, "a million cache reads do not make one model swamp the other")
    check(abs(opus + sonnet - 50) < 0.01, "and the lines still sum to the weekly reading")
}

print(failures == 0 ? "\nALL PASS" : "\n\(failures) FAILURE(S)")
exit(failures == 0 ? 0 : 1)
