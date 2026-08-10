import SwiftUI
import Charts

// The chart catalogue. Twenty-four selectable views over the same underlying data, grouped by the question
// they answer, plus the shared hover/scrub readout every one of them uses.
//
// Design note: burn data is extremely spiky - long
// flat stretches punctuated by bursts - so no single treatment suits every question. Rate views show
// intensity, volume views show totals, burndowns show whether you will make it to the reset, and the
// breakdown views answer "where did it go". The user picks; nothing is hard-coded.

// MARK: - Kinds

enum ChartKind: String, CaseIterable, Identifiable {
    // Burn: how hard are you pushing right now
    case burnLine, burnSteps, burnBars, cumulative, burnHistogram
    // Limits: will you make it to the reset
    case sessionBurndown, weekBurndown, usageLines, paceGauge, modelCaps
    // Breakdown: where did it go
    case byModel, byProject, costPerDay, topChats, modelMix, projectMix
    // Rhythm: when do you work
    case hourProfile, dayHeatmap, weekdayProfile, dailyTokens, sessionBlocks
    // Detail: what is the traffic made of
    case cacheMix, inputOutput, monthCost

    var id: String { rawValue }

    var label: String {
        switch self {
        case .burnLine:        return "Burn rate"
        case .burnSteps:       return "Burn steps"
        case .burnBars:        return "Volume bars"
        case .cumulative:      return "Cumulative tokens"
        case .burnHistogram:   return "Burn distribution"
        case .sessionBurndown: return "Session burndown"
        case .weekBurndown:    return "Week burndown"
        case .usageLines:      return "Session + week %"
        case .paceGauge:       return "Pace"
        case .modelCaps:       return "Model limits"
        case .byModel:         return "By model"
        case .byProject:       return "By project"
        case .costPerDay:      return "Cost per day"
        case .topChats:        return "Top chats"
        case .modelMix:        return "Model mix"
        case .projectMix:      return "Project mix"
        case .hourProfile:     return "Hour of day"
        case .dayHeatmap:      return "Activity heatmap"
        case .weekdayProfile:  return "Day of week"
        case .dailyTokens:     return "Tokens per day"
        case .sessionBlocks:   return "Session blocks"
        case .cacheMix:        return "Cache efficiency"
        case .inputOutput:     return "Input vs output"
        case .monthCost:       return "Spend to date"
        }
    }

    /// Short form for the popover header control, where width is scarce.
    var short: String {
        switch self {
        case .burnLine:        return "Burn"
        case .burnSteps:       return "Steps"
        case .burnBars:        return "Volume"
        case .cumulative:      return "Total"
        case .burnHistogram:   return "Spread"
        case .sessionBurndown: return "Session"
        case .weekBurndown:    return "Week"
        case .usageLines:      return "Usage %"
        case .paceGauge:       return "Pace"
        case .modelCaps:       return "Caps"
        case .byModel:         return "Model"
        case .byProject:       return "Project"
        case .costPerDay:      return "Cost"
        case .topChats:        return "Chats"
        case .modelMix:        return "Mix"
        case .projectMix:      return "Split"
        case .hourProfile:     return "Hours"
        case .dayHeatmap:      return "Heatmap"
        case .weekdayProfile:  return "Weekday"
        case .dailyTokens:     return "Daily"
        case .sessionBlocks:   return "Blocks"
        case .cacheMix:        return "Cache"
        case .inputOutput:     return "In/Out"
        case .monthCost:       return "Spend"
        }
    }

    var blurb: String {
        switch self {
        case .burnLine:        return "Tokens per minute as a smoothed line, with the rolling average."
        case .burnSteps:       return "Tokens per minute as steps - honest about bursty traffic, no invented slopes between samples."
        case .burnBars:        return "Actual tokens per time bucket. Bursts read as blocks of volume rather than spikes."
        case .cumulative:      return "Running total of tokens across the window. Always rises, so the slope is the burn rate."
        case .burnHistogram:   return "How often you burn at each rate. A long tail means rare, huge bursts."
        case .sessionBurndown: return "How much of the 5-hour session limit is left, against the pace that lasts exactly to the reset."
        case .weekBurndown:    return "How much of the weekly limit is left, against the pace that lasts exactly to the reset."
        case .usageLines:      return "Session and week on one 0-100% scale, plus each model's share. Click a legend name to hide its line."
        case .paceGauge:       return "Session and week, each against the pace that lasts exactly to the reset. Past 1.0x you are overspending."
        case .modelCaps:       return "Every weekly limit side by side: all models, plus any model with its own cap."
        case .byModel:         return "Tokens stacked by model family, so you can see which model is eating the window."
        case .byProject:       return "The projects that used the most tokens in the window."
        case .costPerDay:      return "Estimated spend per day."
        case .topChats:        return "The individual conversations that cost the most in the window."
        case .modelMix:        return "Each model's share of the window as one proportional bar."
        case .projectMix:      return "Each project's share of the window as one proportional bar."
        case .hourProfile:     return "Your average usage by hour of the day - when you actually work."
        case .dayHeatmap:      return "Days by hour, shaded by usage. The shape of your week at a glance."
        case .weekdayProfile:  return "Average usage by day of the week - which days carry the load."
        case .dailyTokens:     return "Total tokens per day, with the daily average marked."
        case .sessionBlocks:   return "Every 5-hour session block in the period and how hard each one was worked."
        case .cacheMix:        return "Cache reads against fresh tokens. A high cache share means you are getting a lot for less."
        case .inputOutput:     return "What the traffic is made of: input, output, and cache."
        case .monthCost:       return "Running spend across the period, with where it lands at this rate."
        }
    }

    /// Menu grouping.
    var group: String {
        switch self {
        case .burnLine, .burnSteps, .burnBars, .cumulative, .burnHistogram:            return "Burn"
        case .sessionBurndown, .weekBurndown, .usageLines, .paceGauge, .modelCaps:     return "Limits"
        case .byModel, .byProject, .costPerDay, .topChats, .modelMix, .projectMix:     return "Breakdown"
        case .hourProfile, .dayHeatmap, .weekdayProfile, .dailyTokens, .sessionBlocks: return "Rhythm"
        case .cacheMix, .inputOutput, .monthCost:                                      return "Detail"
        }
    }

    static let groupOrder = ["Burn", "Limits", "Breakdown", "Rhythm", "Detail"]
    /// Tab label: five tabs have to share ~240pt, and "Breakdown" is the one that will not fit.
    static func groupTab(_ g: String) -> String { g == "Breakdown" ? "Split" : g }

    /// Does the rolling time-window setting apply? Burndowns are pinned to their limit window, and the
    /// day-scale views use the day-count setting instead.
    var usesWindow: Bool {
        switch self {
        case .sessionBurndown, .weekBurndown, .paceGauge, .modelCaps,
             .costPerDay, .hourProfile, .dayHeatmap, .weekdayProfile,
             .dailyTokens, .sessionBlocks, .monthCost:
            return false
        default: return true
        }
    }
    /// Does the day-count setting apply?
    var usesDays: Bool {
        switch self {
        case .costPerDay, .hourProfile, .dayHeatmap, .weekdayProfile,
             .dailyTokens, .sessionBlocks, .monthCost:
            return true
        default: return false
        }
    }
}

// MARK: - Shared plumbing

/// One time-bucketed total.
struct TokBucket: Identifiable, Equatable { let id: Int; let t: Date; let v: Double }
/// One named category total (project, model, day…).
struct CatValue: Identifiable, Equatable { let id: Int; let name: String; let v: Double }
/// One stacked slice: a bucket's contribution from one series.
struct StackSlice: Identifiable, Equatable { let id: String; let t: Date; let key: String; let v: Double }
/// A stacked slice resolved to explicit rectangle bounds.
///
/// Swift Charts' `BarMark` collapses to zero width on a CONTINUOUS x scale (Date or numeric) unless it
/// can infer a step; only categorical scales lay it out reliably. Every time-bucketed bar chart here
/// therefore draws `RectangleMark`s with explicit start/end bounds, which also gives exact bucket
/// widths and correct stacking rather than leaving it to inference.
struct StackRect: Identifiable, Equatable {
    let id: String; let t0: Date; let t1: Date; let key: String; let y0: Double; let y1: Double
}
/// One heatmap cell.
struct HeatCell: Identifiable, Equatable { let id: Int; let dayLabel: String; let dayIndex: Int; let hour: Int; let v: Double }

/// The x position inside the plot area → a domain value. Returns nil outside the plot.
func plotValue<T: Plottable>(_ proxy: ChartProxy, _ geo: GeometryProxy, _ pt: CGPoint, as: T.Type) -> T? {
    let frame = geo[proxy.plotAreaFrame]
    guard frame.contains(pt) else { return nil }
    return proxy.value(atX: pt.x - frame.minX)
}

/// Continuous-hover overlay that reports plot-local hits and clears on exit. Every chart uses this so
/// the scrub behaviour is identical everywhere.
struct HoverCatcher: ViewModifier {
    let onHover: (CGPoint?, ChartProxy, GeometryProxy) -> Void
    func body(content: Content) -> some View {
        content.chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let pt): onHover(pt, proxy, geo)
                        case .ended:          onHover(nil, proxy, geo)
                        }
                    }
            }
        }
    }
}
extension View {
    func hoverCatcher(_ onHover: @escaping (CGPoint?, ChartProxy, GeometryProxy) -> Void) -> some View {
        modifier(HoverCatcher(onHover: onHover))
    }
}

/// Bucket per-call records into `n` even time buckets, summing tokens.
func bucketRecords(_ records: [UsageRecord], from: Date, to: Date, buckets n: Int) -> [TokBucket] {
    guard n > 0, to > from else { return [] }
    let span = to.timeIntervalSince(from)
    let step = span / Double(n)
    var sums = [Double](repeating: 0, count: n)
    // burnTokens, not totalTokens. This is the volume chart that sits beside the burn-rate chart,
    // and the live rate has always excluded cache reads. Counting them here meant the two charts in
    // one family measured different things: the bars could tower while the rate beside them barely
    // moved, because a long conversation re-reads an enormous amount of cache to do very little.
    // cumulativeRecords is built on this, so it follows. The cache chart still counts reads, since
    // that is what it is about.
    for r in records where r.date >= from && r.date <= to {
        let i = min(n - 1, max(0, Int(r.date.timeIntervalSince(from) / step)))
        sums[i] += Double(r.burnTokens)
    }
    return (0..<n).map { TokBucket(id: $0, t: from.addingTimeInterval(step * (Double($0) + 0.5)), v: sums[$0]) }
}

/// Running total of tokens across the window.
func cumulativeRecords(_ records: [UsageRecord], from: Date, to: Date, buckets n: Int) -> [TokBucket] {
    var run = 0.0
    return bucketRecords(records, from: from, to: to, buckets: n).map { b in
        run += b.v
        return TokBucket(id: b.id, t: b.t, v: run)
    }
}

/// Tokens by model family, bucketed over time, as stack slices (only families that actually appear).
func modelStack(_ records: [UsageRecord], from: Date, to: Date, buckets n: Int) -> [StackSlice] {
    guard n > 0, to > from else { return [] }
    let step = to.timeIntervalSince(from) / Double(n)
    var sums: [String: [Double]] = [:]
    for r in records where r.date >= from && r.date <= to {
        let i = min(n - 1, max(0, Int(r.date.timeIntervalSince(from) / step)))
        sums[modelFamily(r.model), default: [Double](repeating: 0, count: n)][i] += Double(r.totalTokens)
    }
    return sums.sorted { $0.key < $1.key }.flatMap { (family, arr) -> [StackSlice] in
        arr.enumerated().map { (i, v) in
            StackSlice(id: "\(family)-\(i)", t: from.addingTimeInterval(step * (Double(i) + 0.5)), key: family, v: v)
        }
    }
}

/// Tokens by model family, bucketed and resolved into stacked rectangles (see StackRect).
func modelStackRects(_ records: [UsageRecord], from: Date, to: Date, buckets n: Int) -> [StackRect] {
    guard n > 0, to > from else { return [] }
    let step = to.timeIntervalSince(from) / Double(n)
    let inset = step * 0.14           // a hair of air between columns
    var sums: [String: [Double]] = [:]
    for r in records where r.date >= from && r.date <= to {
        let i = min(n - 1, max(0, Int(r.date.timeIntervalSince(from) / step)))
        sums[modelFamily(r.model), default: [Double](repeating: 0, count: n)][i] += Double(r.totalTokens)
    }
    let families = sums.keys.sorted()
    var out: [StackRect] = []
    for i in 0..<n {
        var base = 0.0
        let t0 = from.addingTimeInterval(step * Double(i) + inset)
        let t1 = from.addingTimeInterval(step * Double(i + 1) - inset)
        for f in families {
            let v = sums[f]?[i] ?? 0
            guard v > 0 else { continue }
            out.append(StackRect(id: "\(f)-\(i)", t0: t0, t1: t1, key: f, y0: base, y1: base + v))
            base += v
        }
    }
    return out
}

/// Top projects by tokens in the window.
func topProjects(_ records: [UsageRecord], from: Date, limit: Int = 5) -> [CatValue] {
    var sums: [String: Double] = [:]
    for r in records where r.date >= from {
        sums[r.project.isEmpty ? kUnknownProject : r.project, default: 0] += Double(r.totalTokens)
    }
    return sums.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
        .prefix(limit).enumerated().map { CatValue(id: $0.offset, name: $0.element.key, v: $0.element.value) }
}

/// Estimated cost per calendar day, oldest first.
func costPerDay(_ records: [UsageRecord], days: Int, now: Date = Date()) -> [CatValue] {
    let cal = Calendar.current
    let today = cal.startOfDay(for: now)
    var sums: [Date: Double] = [:]
    for r in records {
        let d = cal.startOfDay(for: r.date)
        if let diff = cal.dateComponents([.day], from: d, to: today).day, diff >= 0, diff < days {
            sums[d, default: 0] += r.cost
        }
    }
    // Labels are the categorical x values, so they MUST be unique, and a bare day-of-month is only
    // unique while the window is shorter than the shortest month it can span. Thirty-one days from
    // the first of April ends on the first of May, and Swift Charts merges those two bars into one
    // without a word. The threshold is 27, not 31, because February exists.
    let f = DateFormatter(); f.dateFormat = days > 27 ? "M/d" : (days > 9 ? "d" : "EEE")
    return (0..<days).reversed().compactMap { back in
        guard let d = cal.date(byAdding: .day, value: -back, to: today) else { return nil }
        return CatValue(id: days - back, name: f.string(from: d), v: sums[d] ?? 0)
    }
}

/// Average tokens per hour-of-day across the last `days` days (only days with any activity count, so a
/// fresh install is not diluted by empty history).
func hourOfDayProfile(_ records: [UsageRecord], days: Int, now: Date = Date()) -> [TokBucket] {
    let cal = Calendar.current
    // Cut at a day boundary, not at this instant. Both of these divide by the number of days that
    // saw any activity, so a cutoff of "this time N days ago" lets a partial day contribute a
    // fraction of its tokens while still counting as a whole day in the divisor, pulling every
    // average down. Whole days in, whole days out.
    let cutoff = cal.date(byAdding: .day, value: -(days - 1), to: cal.startOfDay(for: now))
        ?? cal.startOfDay(for: now)
    var sums = [Double](repeating: 0, count: 24)
    var activeDays: Set<Date> = []
    for r in records where r.date >= cutoff {
        sums[cal.component(.hour, from: r.date)] += Double(r.totalTokens)
        activeDays.insert(cal.startOfDay(for: r.date))
    }
    let n = max(1, activeDays.count)
    return (0..<24).map { TokBucket(id: $0, t: Date(timeIntervalSince1970: Double($0)), v: sums[$0] / Double(n)) }
}

/// Day × hour grid for the heatmap, oldest day first.
func heatCells(_ records: [UsageRecord], days: Int, now: Date = Date()) -> [HeatCell] {
    let cal = Calendar.current
    let today = cal.startOfDay(for: now)
    var grid: [Int: [Double]] = [:]
    for r in records {
        let d = cal.startOfDay(for: r.date)
        guard let back = cal.dateComponents([.day], from: d, to: today).day, back >= 0, back < days else { continue }
        grid[back, default: [Double](repeating: 0, count: 24)][cal.component(.hour, from: r.date)] += Double(r.totalTokens)
    }
    let f = DateFormatter(); f.dateFormat = "EEE"
    var out: [HeatCell] = []
    var id = 0
    for back in (0..<days).reversed() {
        guard let d = cal.date(byAdding: .day, value: -back, to: today) else { continue }
        let row = grid[back] ?? [Double](repeating: 0, count: 24)
        for h in 0..<24 {
            out.append(HeatCell(id: id, dayLabel: f.string(from: d), dayIndex: days - 1 - back, hour: h, v: row[h]))
            id += 1
        }
    }
    return out
}

/// Compact "2 PM" style hour label.
func hourLabel(_ h: Int) -> String {
    let x = h % 12 == 0 ? 12 : h % 12
    return "\(x)\(h < 12 ? "a" : "p")"
}

// MARK: - Helpers for the second dozen

/// Total tokens per calendar day, oldest first.
func dailyTokens(_ records: [UsageRecord], days: Int, now: Date = Date()) -> [CatValue] {
    let cal = Calendar.current
    let today = cal.startOfDay(for: now)
    // The day boundaries are worked out once. The first version of this asked Calendar for a start
    // of day AND a day difference for every record in the whole retained history, on a chart the
    // card re-renders constantly, which is what made the popover feel slow. Real calendar
    // boundaries plus a binary search give the same answer, DST nights included, for far less work.
    var starts: [Date] = []                         // oldest first
    for back in (0..<days).reversed() {
        if let d = cal.date(byAdding: .day, value: -back, to: today) { starts.append(d) }
    }
    guard let first = starts.first else { return [] }
    let end = cal.date(byAdding: .day, value: 1, to: today) ?? now
    var sums = [Double](repeating: 0, count: starts.count)
    for r in records where r.date >= first && r.date < end {
        var lo = 0, hi = starts.count - 1            // last boundary at or before this record
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if starts[mid] <= r.date { lo = mid } else { hi = mid - 1 }
        }
        sums[lo] += Double(r.totalTokens)
    }
    // Labels are the categorical x values, so they MUST be unique, and a bare day-of-month is only
    // unique while the window is shorter than the shortest month it can span. Thirty-one days from
    // the first of April ends on the first of May, and Swift Charts merges those two bars into one
    // without a word. The threshold is 27, not 31, because February exists.
    let f = DateFormatter(); f.dateFormat = days > 27 ? "M/d" : (days > 9 ? "d" : "EEE")
    return starts.indices.map { CatValue(id: $0 + 1, name: f.string(from: starts[$0]), v: sums[$0]) }
}

/// Daily totals rolled up into weeks, for windows too long to draw a bar per day.
///
/// Ninety bars inside a 264pt card is about a pixel and a half each: not a chart, a texture. Past
/// five weeks the popover asks for weeks instead, which is the same information at a size the eye


/// Average tokens by weekday (Mon…Sun), across the days covered.
func weekdayProfile(_ records: [UsageRecord], days: Int, now: Date = Date()) -> [CatValue] {
    let cal = Calendar.current
    // Day-aligned, for the same reason as hourOfDayProfile: a partial boundary day would add a
    // slice of tokens to one weekday while counting as a full day against its average.
    let cutoff = cal.date(byAdding: .day, value: -(days - 1), to: cal.startOfDay(for: now))
        ?? cal.startOfDay(for: now)
    var sums = [Double](repeating: 0, count: 7)      // index 0 = Monday
    var seen: [Set<Date>] = Array(repeating: [], count: 7)
    for r in records where r.date >= cutoff {
        let idx = (cal.component(.weekday, from: r.date) + 5) % 7   // 1=Sun → 6, 2=Mon → 0
        sums[idx] += Double(r.totalTokens)
        seen[idx].insert(cal.startOfDay(for: r.date))
    }
    let names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    return (0..<7).map { CatValue(id: $0, name: names[$0], v: sums[$0] / Double(max(1, seen[$0].count))) }
}

/// The biggest individual conversations in the window, by tokens.
func topChats(_ records: [UsageRecord], from: Date, limit: Int = 4) -> [CatValue] {
    var sums: [String: Double] = [:]
    for r in records where r.date >= from && !r.session.isEmpty {
        sums[r.session, default: 0] += Double(r.totalTokens)
    }
    return sums.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
        // RAW titles. Baking the display name in here froze it into the memoised rows, whose key
        // carries no alias state, so renaming a chat did nothing visible until the data happened to
        // change. The chart applies the alias at render time, where ChatNames is observed.
        .prefix(limit).enumerated().map {
            CatValue(id: $0.offset, name: $0.element.key, v: $0.element.value)
        }
}

/// Share of the window per key, largest first, as fractions summing to 1.
func shareSplit(_ records: [UsageRecord], from: Date, by key: (UsageRecord) -> String) -> [CatValue] {
    var sums: [String: Double] = [:]
    for r in records where r.date >= from { sums[key(r), default: 0] += Double(r.totalTokens) }
    let total = sums.values.reduce(0, +)
    guard total > 0 else { return [] }
    return sums.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
        .enumerated().map { CatValue(id: $0.offset, name: $0.element.key, v: $0.element.value / total) }
}

/// One 5-hour session block: when it started and how many tokens it burned. Blocks are cut the same
/// way the engine cuts them (a new block starts when a call lands more than 5h after the block start,
/// or more than 5h after the previous call), so this history lines up with the session percentage.
struct SessionBlock: Identifiable, Equatable { let id: Int; let start: Date; let tokens: Double }

func sessionBlocks(_ records: [UsageRecord], days: Int, now: Date = Date()) -> [SessionBlock] {
    // Day-aligned, like every other windowed chart here.
    let sod = Calendar.current.startOfDay(for: now)
    let cutoff = Calendar.current.date(byAdding: .day, value: -(days - 1), to: sod) ?? sod
    let sorted = records.filter { $0.date >= cutoff }.sorted { $0.date < $1.date }
    guard !sorted.isEmpty else { return [] }
    let five: TimeInterval = 5 * 3600
    // A session block starts at the top of the hour containing its first message, exactly as the
    // engine's own buildBlocks does. Without that anchor this chart cut its blocks at a different
    // instant from the five-hour window the rest of the app counts against, so the bars could show
    // a boundary the session card disagreed with, by up to an hour.
    func floorHour(_ d: Date) -> Date {
        Date(timeIntervalSinceReferenceDate: (d.timeIntervalSinceReferenceDate / 3600).rounded(.down) * 3600)
    }
    var out: [SessionBlock] = []
    var start = floorHour(sorted[0].date), last = sorted[0].date, sum = 0.0, id = 0
    for r in sorted {
        if r.date.timeIntervalSince(start) >= five || r.date.timeIntervalSince(last) >= five {
            out.append(SessionBlock(id: id, start: start, tokens: sum)); id += 1
            start = floorHour(r.date); sum = 0
        }
        sum += Double(r.totalTokens); last = r.date
    }
    out.append(SessionBlock(id: id, start: start, tokens: sum))
    return out
}

/// Cache reads vs fresh tokens, bucketed, as stacked rectangles.
func cacheMixRects(_ records: [UsageRecord], from: Date, to: Date, buckets n: Int) -> [StackRect] {
    guard n > 0, to > from else { return [] }
    let step = to.timeIntervalSince(from) / Double(n)
    let inset = step * 0.14
    var fresh = [Double](repeating: 0, count: n), cached = [Double](repeating: 0, count: n)
    for r in records where r.date >= from && r.date <= to {
        let i = min(n - 1, max(0, Int(r.date.timeIntervalSince(from) / step)))
        fresh[i] += Double(r.input + r.output + r.cache5m + r.cache1h)
        cached[i] += Double(r.cacheRead)
    }
    var out: [StackRect] = []
    for i in 0..<n {
        let t0 = from.addingTimeInterval(step * Double(i) + inset)
        let t1 = from.addingTimeInterval(step * Double(i + 1) - inset)
        if fresh[i] > 0 { out.append(StackRect(id: "f\(i)", t0: t0, t1: t1, key: "Fresh", y0: 0, y1: fresh[i])) }
        if cached[i] > 0 { out.append(StackRect(id: "c\(i)", t0: t0, t1: t1, key: "Cache read", y0: fresh[i], y1: fresh[i] + cached[i])) }
    }
    return out
}

/// Input / output / cache-write / cache-read composition, bucketed, as stacked rectangles.
func inputOutputRects(_ records: [UsageRecord], from: Date, to: Date, buckets n: Int) -> [StackRect] {
    guard n > 0, to > from else { return [] }
    let step = to.timeIntervalSince(from) / Double(n)
    let inset = step * 0.14
    let keys = ["Input", "Output", "Cache write", "Cache read"]
    var sums: [[Double]] = Array(repeating: [Double](repeating: 0, count: n), count: 4)
    for r in records where r.date >= from && r.date <= to {
        let i = min(n - 1, max(0, Int(r.date.timeIntervalSince(from) / step)))
        sums[0][i] += Double(r.input); sums[1][i] += Double(r.output)
        sums[2][i] += Double(r.cache5m + r.cache1h); sums[3][i] += Double(r.cacheRead)
    }
    var out: [StackRect] = []
    for i in 0..<n {
        var base = 0.0
        let t0 = from.addingTimeInterval(step * Double(i) + inset)
        let t1 = from.addingTimeInterval(step * Double(i + 1) - inset)
        for (k, name) in keys.enumerated() {
            let v = sums[k][i]
            guard v > 0 else { continue }
            out.append(StackRect(id: "\(name)-\(i)", t0: t0, t1: t1, key: name, y0: base, y1: base + v))
            base += v
        }
    }
    return out
}

/// Distribution of burn rates: how many samples fell in each rate band. Bands are log-ish so the long
/// tail of rare huge bursts stays visible instead of collapsing into one bar.
func burnHistogram(_ samples: [TimedSample], from: Date) -> [CatValue] {
    let edges: [Double] = [0, 1_000, 5_000, 20_000, 60_000, 200_000, 600_000, .greatestFiniteMagnitude]
    let names = ["<1k", "1-5k", "5-20k", "20-60k", "60-200k", "200-600k", "600k+"]
    var counts = [Double](repeating: 0, count: names.count)
    for s in samples where s.t >= from {
        for i in 0..<names.count where s.v >= edges[i] && s.v < edges[i + 1] { counts[i] += 1; break }
    }
    return (0..<names.count).map { CatValue(id: $0, name: names[$0], v: counts[$0]) }
}

/// Running spend by day across the period, plus where it lands at the current daily rate.
func cumulativeCost(_ records: [UsageRecord], days: Int, now: Date = Date()) -> (points: [CatValue], projected: Double) {
    let per = costPerDay(records, days: days, now: now)
    var run = 0.0
    let pts = per.map { d -> CatValue in run += d.v; return CatValue(id: d.id, name: d.name, v: run) }
    // Every day in this window has already happened, so there is no future here to forecast. What
    // the second number can honestly say is what a full window would come to if every day looked
    // like the days actually worked: spend divided by the days that saw any, times the window. The
    // caption says "at this pace" rather than "heading for" for exactly that reason. It reads high
    // for anyone who works in bursts, which is the truth about a per-working-day rate, not a bug.
    let elapsed = max(1, per.filter { $0.v > 0 }.count)
    let projected = run / Double(elapsed) * Double(days)
    return (pts, projected)
}

/// Cumulative tokens by day-offset for the last 7 days and the 7 before that, for a like-for-like
/// comparison of "this week so far" against "last week by the same point".
func weekOverWeek(_ records: [UsageRecord], now: Date = Date()) -> (this: [Double], prev: [Double]) {
    let cal = Calendar.current
    let today = cal.startOfDay(for: now)
    var cur = [Double](repeating: 0, count: 7), old = [Double](repeating: 0, count: 7)
    for r in records {
        let d = cal.startOfDay(for: r.date)
        guard let back = cal.dateComponents([.day], from: d, to: today).day, back >= 0, back < 14 else { continue }
        if back < 7 { cur[6 - back] += Double(r.totalTokens) } else { old[13 - back] += Double(r.totalTokens) }
    }
    func run(_ a: [Double]) -> [Double] { var s = 0.0; return a.map { s += $0; return s } }
    return (run(cur), run(old))
}
