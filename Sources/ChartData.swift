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
