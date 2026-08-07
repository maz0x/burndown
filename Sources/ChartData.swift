import Foundation

// Foundation-pure chart-data helpers (smoothing, segmentation, downsampling, nearest-point),
// split out of Views.swift so the headless harness (run-chartdata-tests.sh) can compile the real
// implementations with no SwiftUI / Charts. TimedSample lives in LiveActivity.swift and ChartPoint
// in Views.swift; the test file redeclares those tiny value types, matching the project convention.

// Exponential moving average over a timestamped series - smooths the per-refresh jitter
// of a noisy live rate without the lag of a wide moving average (α≈0.2 recommended).
func ema(_ samples: [TimedSample], _ alpha: Double) -> [TimedSample] {
    guard let first = samples.first else { return [] }
    var acc = first.v
    return samples.map { s in acc = alpha * s.v + (1 - alpha) * acc; return TimedSample(t: s.t, v: acc) }
}

func segmentize(_ samples: [TimedSample], gap: TimeInterval, clampTo: Double = .greatestFiniteMagnitude) -> [ChartPoint] {
    var out: [ChartPoint] = []; var seg = 0
    for (i, s) in samples.enumerated() {
        if i > 0, s.t.timeIntervalSince(samples[i - 1].t) > gap { seg += 1 }
        out.append(ChartPoint(id: i, t: s.t, v: min(s.v, clampTo), seg: seg))
    }
    return out
}

// Downsample to at most `buckets` points across [lower, upper], keeping real timestamps -
// keeps Swift Charts fast even with ~1200 dense burn points. pickMax keeps each bucket's
// peak (burn spikes survive); otherwise the bucket's latest value (usage curves).
func bucketed(_ samples: [TimedSample], lower: Date, upper: Date, buckets: Int, pickMax: Bool) -> [TimedSample] {
    guard samples.count > buckets, upper > lower else { return samples }
    let span = upper.timeIntervalSince(lower)
    var slots: [TimedSample?] = Array(repeating: nil, count: buckets)
    for s in samples {
        let f = s.t.timeIntervalSince(lower) / span
        guard f >= 0, f <= 1 else { continue }
        let i = min(buckets - 1, max(0, Int(f * Double(buckets))))
        if let cur = slots[i] { if pickMax ? (s.v > cur.v) : (s.t > cur.t) { slots[i] = s } }
        else { slots[i] = s }
    }
    return slots.compactMap { $0 }
}

func nearestSample(_ samples: [TimedSample], to date: Date) -> TimedSample? {
    samples.min { abs($0.t.timeIntervalSince(date)) < abs($1.t.timeIntervalSince(date)) }
}

/// Each model's share of the WEEKLY allowance, over time, for the "Session + week %" chart.
///
/// The first cut of this drew a line per model that Claude gives its own weekly cap. On a real
/// account that is one model, so Opus and Haiku silently had no line at all. Share of the weekly
/// allowance is the measure that actually answers "which model is eating my week": every model
/// used appears, all on the same 0-100% axis as Session and Week, and the model lines SUM to the
/// weekly figure rather than each meaning something different.
///
/// Claude's service reports no per-model history, so the SHAPE comes from the local logs and the
/// whole set is scaled by one shared factor so the totals land exactly on the weekly percentage
/// the service reports. One factor for every model, not one each: that is what keeps them
/// additive and keeps the stack honest against the number shown above the chart.
func modelWeekShareSeries(records: [UsageRecord], weeklyPct: Double,
                          weeklyResetAt: Date?, now: Date = Date()) -> [(label: String, samples: [TimedSample])] {
    guard weeklyPct > 0 else { return [] }
    // The current weekly window opened seven days before it is due to reset. With no reset time
    // known, fall back to the earliest record rather than inventing a boundary.
    let weekStart = weeklyResetAt.map { $0.addingTimeInterval(-7 * 86_400) }
        ?? records.map(\.date).min() ?? now

    // Split deliberately: as one chained filter+sort the Swift type-checker times out.
    var rows: [UsageRecord] = []
    // Records whose model could not be identified come back from modelFamily as "Other", and an
    // "Other" line in a legend of real model names is noise wearing a label.
    for r in records where r.date >= weekStart && r.date <= now && modelFamily(r.model) != "Other" {
        rows.append(r)
    }
    rows.sort { $0.date < $1.date }
    let grand = rows.reduce(0) { $0 + $1.totalTokens }
    guard grand > 0 else { return [] }

    // Percentage points per logged token, shared by every model so the lines stay additive.
    let k = weeklyPct / Double(grand)

    var running: [String: Int] = [:]
    var series: [String: [TimedSample]] = [:]
    var families: [String] = []
    for r in rows {
        let fam = modelFamily(r.model)
        if series[fam] == nil {
            series[fam] = [TimedSample(t: weekStart, v: 0)]
            families.append(fam)
        }
        running[fam, default: 0] += r.totalTokens
        series[fam]?.append(TimedSample(t: r.date, v: Double(running[fam] ?? 0) * k))
    }
    // Carry every line to `now` so they all end level with the weekly reading between them.
    for fam in families {
        series[fam]?.append(TimedSample(t: now, v: Double(running[fam] ?? 0) * k))
    }
    // Biggest consumer first, so the legend reads in the order the eye finds the lines. A model
    // that rounds to nothing gets no line: an invisible line with a legend entry is a puzzle.
    return families
        .map { (label: $0, samples: series[$0] ?? []) }
        .filter { ($0.samples.last?.v ?? 0) >= 0.005 }
        .sorted { ($0.samples.last?.v ?? 0) > ($1.samples.last?.v ?? 0) }
}
