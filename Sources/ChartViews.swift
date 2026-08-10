import SwiftUI
import Charts

// The twelve chart bodies. Every one is ~74pt tall, reads over translucent glass in light and dark,
// and answers a hover with a real number rather than sitting there inert.

/// Everything a chart body might need, so the dispatch in MonitorChart stays a one-liner per kind.
struct ChartCtx {
    var burnSamples: [TimedSample] = []
    var usageSamples: [TimedSample] = []
    var weeklySamples: [TimedSample] = []
    var records: [UsageRecord] = []
    var sessionPct: Double = 0
    var weeklyPct: Double = 0
    var sessionResetAt: Date? = nil
    var weeklyResetAt: Date? = nil
    var modelLimits: [ScopedLimit] = []
    var accent: Color = .orange
    var secondary: Color = kSlate
    var p: Palette = .of(.light)
    // Plot height for every chart body: kChartH base + the corner grip's vertical boost
    // (settings.cardChartBoost). Popover-only; contact sheets and previews keep the base.
    var plotH: CGFloat = kChartH
    var style: ChartStyle = .area
    var window: TimeInterval = 3600
    var days: Int = 14
    var hover: Bool = true
    /// The live tokens-per-minute reading, so the burn chart's headline and the Session line
    /// cannot disagree. They used to: the Session line read the last 60 seconds while the chart
    /// read its most recent SAMPLE, so the card showed "0 tok/min" directly above "1k / min".
    var currentRate: Double = 0
    /// Series the user has switched off in the "Session + week %" legend, and the callback that
    /// toggles one. Supplied by the card (persisted); the Settings gallery leaves them inert.
    /// The conversations producing tokens right now, so a chart can mark one as live.
    var activeStreams: [(name: String, project: String, tok: Int)] = []
    /// The reader's chat-name truncation choice, so row charts shorten names the way the card does.
    var truncation: ChatTruncation = .middle
    var hiddenSeries: Set<String> = []
    var onToggleSeries: (String) -> Void = { _ in }
    /// Window start, clamped to the earliest sample for the "all time" sentinel.
    ///
    /// Never later than half an hour ago, whatever the data says. Every chart builds its x-domain
    /// as `lower ... now`, and a domain whose start is after its end is not a rendering quirk, it
    /// is a crash. The earliest record can sit in the future for reasons entirely outside this
    /// app: a machine whose clock was wrong when the log was written, or a timestamp read in the
    /// wrong zone. The charts should look odd in that case, not take the app down.
    func lower(_ earliest: Date?, now: Date) -> Date {
        // A fixed window is already in the past by construction; only the data-driven one can
        // wander forward. Clamping both would silently widen every short window to thirty minutes.
        guard window >= 3.0e9 else { return now.addingTimeInterval(-max(60, window)) }
        let newest = now.addingTimeInterval(-1800)
        return min(earliest ?? newest, newest)
    }

    /// The line width every time-series chart draws with.
    ///
    /// "Hairline" is offered to the user as a chart STYLE, and it thinned exactly one chart:
    /// BurnRate consulted ctx.style while Cumulative, both usage lines and MonthCost hardcoded
    /// 1.6. A style that changes one chart out of five is not a style, it is a bug with a label.
    var lineW: CGFloat { style == .hairline ? 1 : 1.6 }

    /// A clock that only moves every 15 seconds.
    ///
    /// Charts take their window from "now", so with the real clock no two renders ever agree and a
    /// cache keyed on the window can never hit. Moving a mouse across a chart re-renders it dozens
    /// of times a second. Fifteen seconds of staleness is invisible on an hour-wide plot and turns
    /// all of those renders into one piece of work.
    var tick: Date {
        Date(timeIntervalSinceReferenceDate:
                (Date().timeIntervalSinceReferenceDate / 15).rounded(.down) * 15)
    }

    /// Cheap fingerprint of everything a roll-up over `records` depends on.
    ///
    /// Records are appended to, and trimmed from the front by the retention setting, so count alone
    /// is not enough: a trim plus an append leaves it unchanged. First and last dates close that.
    var dataKey: String {
        "\(records.count)|\(records.first?.date.timeIntervalSince1970 ?? 0)"
        + "|\(records.last?.date.timeIntervalSince1970 ?? 0)|\(days)|\(window)"
        + "|\(tick.timeIntervalSinceReferenceDate)"
    }
}

/// One slot of scratch memory so a chart body can skip an aggregation it has already done.
///
/// Every chart here rolls up the whole retained history on each render, and the card re-renders on
/// the live tick AND on every mouse move while a chart is hovered. Held as `@State`, this survives
/// those renders; the chart asks for its value by a cheap key and only pays when the key changes.
/// Writing to it during `body` is deliberate: it is a cache, it publishes nothing, so it cannot
/// invalidate the view it lives in.
final class ChartMemo {
    private var key: String = ""
    private var box: Any?
    func value<V>(_ k: String, _ make: () -> V) -> V {
        if k == key, let v = box as? V { return v }
        let v = make()
        key = k; box = v
        return v
    }
}

/// The same idea as ChartMemo, but with a slot per named result.
///
/// A chart needs one cached aggregation; a window full of tables and charts needs several, all
/// invalidated by the same thing (the scope changed, or the scan landed). One of these holds them
/// all, so a hover redraw recomputes nothing.
final class Memo {
    private var slots: [String: (key: String, value: Any)] = [:]
    func value<V>(_ name: String, _ key: String, _ make: () -> V) -> V {
        if let hit = slots[name], hit.key == key, let v = hit.value as? V { return v }
        let v = make()
        slots[name] = (key, v)
        return v
    }
}

extension Double {
    func rounded(toPlaces n: Int) -> Double {
        let f = pow(10.0, Double(n))
        return (self * f).rounded() / f
    }
}

/// How much of its slot a categorical bar fills.
///
/// Eight sibling charts used five different fractions between 0.62 and 0.76, which reads as bars of
/// slightly different weights sitting in a row of charts that are meant to be one family.
let kBarFill: Double = 0.7

let kChartH: CGFloat = 74

/// One chart body by kind. The single dispatch point shared by the popover (MonitorChart) and the
/// Settings gallery previews, so a chart can never render differently in the picker than in the card.
struct ChartBodyView: View {
    let kind: ChartKind
    let ctx: ChartCtx
    var body: some View {
        switch kind {
        case .burnLine:      BurnRateChart(ctx: ctx)
        case .burnSteps:     BurnRateChart(ctx: ctx, stepped: true)
        case .burnBars:      VolumeBarsChart(ctx: ctx)
        case .cumulative:    CumulativeChart(ctx: ctx)
        case .burnHistogram: BurnHistogramChart(ctx: ctx)
        case .sessionBurndown:
            BurndownChart(ctx: ctx, samples: ctx.usageSamples, currentPct: ctx.sessionPct,
                          resetAt: ctx.sessionResetAt, window: 5 * 3600, tint: ctx.accent)
        case .weekBurndown:
            BurndownChart(ctx: ctx, samples: ctx.weeklySamples, currentPct: ctx.weeklyPct,
                          resetAt: ctx.weeklyResetAt, window: 7 * 86400, tint: ctx.secondary)
        case .usageLines:    UsageLinesChart(ctx: ctx)
        case .paceGauge:     PaceGaugeChart(ctx: ctx)
        case .modelCaps:     ModelCapsChart(ctx: ctx)
        case .byModel:       ByModelChart(ctx: ctx)
        case .byProject:     ByProjectChart(ctx: ctx)
        case .costPerDay:    CostPerDayChart(ctx: ctx)
        case .topChats:      TopChatsChart(ctx: ctx)
        case .modelMix:      ShareSplitChart(ctx: ctx, byModel: true)
        case .projectMix:    ShareSplitChart(ctx: ctx, byModel: false)
        case .hourProfile:   HourProfileChart(ctx: ctx)
        case .dayHeatmap:    DayHeatmapChart(ctx: ctx)
        case .weekdayProfile: WeekdayProfileChart(ctx: ctx)
        case .dailyTokens:   DailyTokensChart(ctx: ctx)
        case .sessionBlocks: SessionBlocksChart(ctx: ctx)
        case .cacheMix:      CompositionChart(ctx: ctx, cacheOnly: true)
        case .inputOutput:   CompositionChart(ctx: ctx, cacheOnly: false)
        case .monthCost:     MonthCostChart(ctx: ctx)
        }
    }
}

/// True where a LiveCadence indicator sits on top of the stat line, so the line has to leave room
/// for it. The Settings gallery draws chart bodies WITHOUT one, and reserving 52pt there for
/// nothing was cutting off the end of every preview's caption.
private struct CadenceReserveKey: EnvironmentKey { static let defaultValue = true }
extension EnvironmentValues {
    var chartHasCadence: Bool {
        get { self[CadenceReserveKey.self] }
        set { self[CadenceReserveKey.self] = newValue }
    }
}

/// The one-line summary under every chart: bold number, faint caption, at the content edge.
///
/// It used to carry a 26pt indent so it lined up with a plotted chart's y-axis labels, plus an
/// opt-out for the charts that have no axis, plus a right-aligned variant for one chart that
/// totalled a column. Three positions for one idea. Every section heading in the card sits at the
/// content edge, so every summary sits at the content edge too, and a reader's eye finds all of
/// them in the same place.
func statLine(_ big: String, _ small: String, _ p: Palette, tint: Color? = nil) -> some View {
    StatLine(big: big, small: small, p: p, tint: tint)
}

struct StatLine: View {
    let big: String, small: String, p: Palette
    var tint: Color? = nil
    @Environment(\.chartHasCadence) private var cadence
    var body: some View {
        HStack(spacing: 4) {
            Text(big).font(.system(size: 11, weight: .semibold)).foregroundStyle(tint ?? p.ink)
                .monospacedDigit().lineLimit(1).fixedSize()
            if !small.isEmpty {
                Text(small).font(.system(size: 9.5)).foregroundStyle(p.faint).lineLimit(1)
            }
            Spacer(minLength: 4)
        }
        // The trailing reserve is the live cadence indicator's slot, which the card draws on top
        // of this row. The gallery has no indicator, so it keeps the space.
        // No leading gutter: the in-box left edge is the box's content edge and nothing else,
        // so the stat line starts exactly where the rows and the chart above it start.
        .padding(.trailing, cadence ? 52 : 8)
    }
}

/// The trailing value column shared by every row-style chart, so a number in one chart ends on the
/// same edge as a number in the next.
let kRowValueWidth: CGFloat = 64
/// The bar height shared by every row-style chart.
let kRowBarHeight: CGFloat = 5

/// The mark in a chart legend: a short length of the line it stands for, dashed when the line is.
struct LegendSwatch: View {
    let colour: Color
    let dashed: Bool
    /// Whether the series this swatch names is currently drawn.
    ///
    /// A switched-off series was marked by opacity alone, at 0.32, which is a difference the eye
    /// reads as "unimportant" rather than as "off": the reader cannot tell a faint line from a
    /// hidden one. Off is drawn hollow, which is a state rather than a shade.
    var on: Bool = true
    var body: some View {
        Capsule().fill(on ? AnyShapeStyle(colour) : AnyShapeStyle(Color.clear))
            .overlay { if !on { Capsule().strokeBorder(colour, lineWidth: 1) } }
            .frame(width: 9, height: 2.5)
            .mask(alignment: .leading) {
                if dashed {
                    HStack(spacing: 1.5) {
                        Capsule().frame(width: 3)
                        Capsule().frame(width: 3)
                    }
                } else {
                    Capsule()
                }
            }
            .frame(width: 9, height: 6)   // same footprint as the dot it replaced
    }
}

/// A categorical x axis that labels only some of its categories.
///
/// `AxisMarks` over a categorical scale draws a label for EVERY category. At 90 days that is 90
/// labels crammed into 264pt, which stops being text and becomes the grey smear under the bars.
/// Thinning counts back from the newest, so the most recent day always keeps its label, and hover
/// still names every single bar exactly, so nothing is actually lost.
/// Categorical x-axis ticks, thinned so labels never collide.
///
/// 8.5 is the card's tick tier. It defaulted to 8 and call sites passed 8.5 or nothing, so one role
/// was drawn at three sizes across sibling charts.
func thinnedCatXAxis(_ names: [String], _ p: Palette, size: CGFloat = 8.5,
                     maxLabels: Int = 7) -> some AxisContent {
    let step = max(1, Int((Double(names.count) / Double(maxLabels)).rounded(.up)))
    let last = names.count - 1
    let keep = names.enumerated().filter { (last - $0.offset) % step == 0 }.map { $0.element }
    return AxisMarks(values: keep) { v in
        AxisValueLabel {
            if let s = v.as(String.self) {
                Text(s).font(.system(size: size, design: .monospaced)).foregroundStyle(p.faint)
            }
        }
    }
}

// MARK: - 1/2. Burn rate (line, steps)

struct BurnRateChart: View {
    let ctx: ChartCtx
    var stepped = false
    @State private var sel: TimedSample?
    @State private var memo = ChartMemo()
    var body: some View {
        let p = ctx.p
        let now = ctx.tick
        let lower = ctx.lower(ctx.burnSamples.first?.t, now: now)
        let win = memo.value(ctx.dataKey + "|burn\(ctx.burnSamples.count)") {
            ctx.burnSamples.filter { $0.t >= lower }
        }
        // Time-weighted, not a plain mean over samples. The sampler runs about thirty times faster
        // while tokens are flowing than while idle, so a busy minute contributes thirty times as
        // many samples as a quiet one and a straight average is pulled toward whatever was
        // happening most often rather than for the longest. Each sample carries the span until the
        // next one; the last carries the median span so a trailing sample cannot dominate.
        let mean: Double = {
            guard win.count > 1 else { return win.first?.v ?? 0 }
            var gaps: [Double] = []
            for i in 1..<win.count { gaps.append(max(0, win[i].t.timeIntervalSince(win[i - 1].t))) }
            let typical = gaps.sorted()[gaps.count / 2]
            var num = 0.0, den = 0.0
            for (i, s) in win.enumerated() {
                let w = i < gaps.count ? gaps[i] : typical
                num += s.v * w; den += w
            }
            return den > 0 ? num / den : win.map(\.v).reduce(0, +) / Double(win.count)
        }()
        // The domain gets the card-wide 1.1 headroom six other charts already use. The CEILING is
        // unchanged and still honest; this is only so the newest sample's dot, when it clamps to
        // that ceiling, is not drawn half outside the plot.
        let yMax = burnCeiling(percentile(win.map(\.v), 0.97))
        let yDomainMax = yMax * 1.1
        // Steps stay raw (inventing slopes between bursts is exactly what the stepped view avoids);
        // the line view smooths, because a hairline through raw spiky data is unreadable.
        let base = bucketed(win, lower: lower, upper: now, buckets: 140, pickMax: true)
        let disp = stepped ? base : ema(base, 0.4)
        return VStack(alignment: .leading, spacing: 5) {
            if disp.isEmpty {
                chartPlaceholder("Warming up, collecting samples", p)
            } else {
                Chart {
                    if mean > 1500 {
                        // The dashed rule, with no label on it. The label sat at the trailing edge
                        // of the plot, which is exactly where the newest point lands, so on a busy
                        // chart it printed itself over the live data. The stat line under the chart
                        // already reads "avg NNN", so nothing is lost by taking it off the plot.
                        RuleMark(y: .value("avg", min(mean, yMax)))
                            .foregroundStyle(p.sub.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
                    ForEach(disp, id: \.t) { s in
                        if ctx.style == .area || ctx.style == .gradient {
                            AreaMark(x: .value("t", s.t), y: .value("v", min(s.v, yMax)))
                                .foregroundStyle(LinearGradient(colors: [ctx.accent.opacity(0.25), ctx.accent.opacity(0.02)],
                                                                startPoint: .top, endPoint: .bottom))
                                .interpolationMethod(stepped ? .stepEnd : .monotone)
                        }
                        LineMark(x: .value("t", s.t), y: .value("v", min(s.v, yMax)))
                            .foregroundStyle(ctx.accent)
                            .lineStyle(StrokeStyle(lineWidth: ctx.style == .hairline ? 1 : 1.6, lineJoin: .round))
                            .interpolationMethod(stepped ? .stepEnd : .monotone)
                    }
                    if sel == nil, let last = disp.last {
                        PointMark(x: .value("t", last.t), y: .value("v", min(last.v, yMax)))
                            .foregroundStyle(ctx.accent.opacity(0.18)).symbolSize(70)
                        PointMark(x: .value("t", last.t), y: .value("v", min(last.v, yMax)))
                            .foregroundStyle(ctx.accent).symbolSize(26)
                    }
                    if let s = sel {
                        RuleMark(x: .value("t", s.t)).foregroundStyle(p.ink.opacity(0.25))
                            .lineStyle(StrokeStyle(lineWidth: 1))
                        PointMark(x: .value("t", s.t), y: .value("v", min(s.v, yMax)))
                            .foregroundStyle(ctx.accent).symbolSize(44)
                            .annotation(position: .top, alignment: s.t > lower.addingTimeInterval(now.timeIntervalSince(lower) / 2) ? .trailing : .leading, spacing: 2) {
                                let dom = dominantProject(ctx.records, around: s.t, halfWidth: max(150, now.timeIntervalSince(lower) / 60))
                                chartCallout("\(fmtTok(Int(s.v)))/min", relTimeLabel(s.t, now: now), p, detail: dom.map { "→ \($0.name)" })
                            }
                    }
                }
                .chartYScale(domain: 0...yDomainMax)
                .chartXScale(domain: lower...now)
                .chartYAxis { tokenYAxis(yMax, p, style: ctx.style) }
                .chartXAxis { timeXAxis(lower, now, p, style: ctx.style) }
                .chartPlotStyle { $0.background(Color.clear) }
                .transaction { $0.animation = nil }
                .frame(height: ctx.plotH)
                .hoverCatcher { pt, proxy, geo in
                    guard ctx.hover else { return }
                    guard let pt, let d: Date = plotValue(proxy, geo, pt, as: Date.self) else { sel = nil; return }
                    let n = nearestSample(disp, to: d)
                    if n?.t != sel?.t { sel = n }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Burn rate")
                .accessibilityValue("Average \(fmtTok(Int(mean))) tokens per minute, peak \(fmtTok(Int(disp.map(\.v).max() ?? 0)))")
            }
            statLine(sel.map { "\(fmtTok(Int($0.v)))/min" } ?? "\(fmtTok(Int(max(0, ctx.currentRate))))/min",
                     sel != nil ? relTimeLabel(sel!.t, now: now) : "· avg \(fmtTok(Int(mean)))", p)
        }
    }
}

// MARK: - 3. Volume bars

struct VolumeBarsChart: View {
    let ctx: ChartCtx
    @State private var sel: TokBucket?
    @State private var memo = ChartMemo()
    var body: some View {
        let p = ctx.p
        let now = ctx.tick
        let lower = ctx.lower(ctx.records.first?.date, now: now)
        let n = 16
        let buckets = memo.value(ctx.dataKey) { bucketRecords(ctx.records, from: lower, to: now, buckets: n) }
        let peak = buckets.map(\.v).max() ?? 0
        let total = buckets.reduce(0) { $0 + $1.v }
        let per = now.timeIntervalSince(lower) / Double(n)
        return VStack(alignment: .leading, spacing: 5) {
            if peak == 0 {
                chartPlaceholder("No usage in this window", p)
            } else {
                Chart {
                    // RectangleMark, not BarMark: on a continuous Date scale BarMark collapses to zero
                    // width. Explicit bounds also give exact bucket widths.
                    ForEach(buckets) { b in
                        RectangleMark(xStart: .value("t0", b.t.addingTimeInterval(-per * 0.36)),
                                      xEnd: .value("t1", b.t.addingTimeInterval(per * 0.36)),
                                      yStart: .value("y0", 0.0),
                                      yEnd: .value("y1", b.v))
                            .foregroundStyle(ctx.accent.opacity(sel == nil || sel?.id == b.id ? 0.85 : 0.35))
                            .cornerRadius(1.5)
                    }
                    if let s = sel {
                        RuleMark(x: .value("t", s.t)).foregroundStyle(p.ink.opacity(0.18))
                            .lineStyle(StrokeStyle(lineWidth: 1))
                            .annotation(position: .top, alignment: s.t > lower.addingTimeInterval(now.timeIntervalSince(lower) / 2) ? .trailing : .leading, spacing: 2) {
                                chartCallout(fmtTok(Int(s.v)), relTimeLabel(s.t, now: now), p)
                            }
                    }
                }
                .chartYScale(domain: 0...(peak * 1.15))
                .chartXScale(domain: lower...now)
                .chartYAxis { tokenYAxis(peak, p, style: ctx.style) }
                .chartXAxis { timeXAxis(lower, now, p, style: ctx.style) }
                .chartPlotStyle { $0.background(Color.clear) }
                .transaction { $0.animation = nil }
                .frame(height: ctx.plotH)
                .hoverCatcher { pt, proxy, geo in
                    guard ctx.hover else { return }
                    guard let pt, let d: Date = plotValue(proxy, geo, pt, as: Date.self) else { sel = nil; return }
                    sel = buckets.min { abs($0.t.timeIntervalSince(d)) < abs($1.t.timeIntervalSince(d)) }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Volume per bucket")
                .accessibilityValue("\(fmtTok(Int(total))) tokens total, busiest \(fmtTok(Int(peak)))")
            }
            statLine(sel.map { fmtTok(Int($0.v)) } ?? fmtTok(Int(total)),
                     sel != nil ? "in \(fmtDuration(per))" : "· peak \(fmtTok(Int(peak))) per \(fmtDuration(per))", p)
        }
    }
}

// MARK: - 4. Cumulative

struct CumulativeChart: View {
    let ctx: ChartCtx
    @State private var sel: TokBucket?
    @State private var memo = ChartMemo()
    var body: some View {
        let p = ctx.p
        let now = ctx.tick
        let lower = ctx.lower(ctx.records.first?.date, now: now)
        let pts = memo.value(ctx.dataKey) { cumulativeRecords(ctx.records, from: lower, to: now, buckets: 90) }
        let total = pts.last?.v ?? 0
        return VStack(alignment: .leading, spacing: 5) {
            if total == 0 {
                chartPlaceholder("No usage in this window", p)
            } else {
                Chart {
                    ForEach(pts) { b in
                        AreaMark(x: .value("t", b.t), y: .value("total", b.v))
                            .foregroundStyle(LinearGradient(colors: [ctx.accent.opacity(0.22), ctx.accent.opacity(0.02)],
                                                            startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.monotone)
                        LineMark(x: .value("t", b.t), y: .value("total", b.v))
                            .foregroundStyle(ctx.accent).lineStyle(StrokeStyle(lineWidth: ctx.lineW))
                            .interpolationMethod(.monotone)
                    }
                    if let s = sel {
                        RuleMark(x: .value("t", s.t)).foregroundStyle(p.ink.opacity(0.25))
                        PointMark(x: .value("t", s.t), y: .value("total", s.v))
                            .foregroundStyle(ctx.accent).symbolSize(44)
                            .annotation(position: .top, alignment: .leading, spacing: 2) {
                                chartCallout(fmtTok(Int(s.v)), "by \(relTimeLabel(s.t, now: now))", p)
                            }
                    }
                }
                .chartYScale(domain: 0...(total * 1.1))
                .chartXScale(domain: lower...now)
                .chartYAxis { tokenYAxis(total, p, style: ctx.style) }
                .chartXAxis { timeXAxis(lower, now, p, style: ctx.style) }
                .chartPlotStyle { $0.background(Color.clear) }
                .transaction { $0.animation = nil }
                .frame(height: ctx.plotH)
                .hoverCatcher { pt, proxy, geo in
                    guard ctx.hover else { return }
                    guard let pt, let d: Date = plotValue(proxy, geo, pt, as: Date.self) else { sel = nil; return }
                    sel = pts.min { abs($0.t.timeIntervalSince(d)) < abs($1.t.timeIntervalSince(d)) }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Cumulative tokens")
                .accessibilityValue("\(fmtTok(Int(total))) tokens in this window")
            }
            statLine(sel.map { fmtTok(Int($0.v)) } ?? fmtTok(Int(total)),
                     sel != nil ? "cumulative" : "· total this window", p)
        }
    }
}

// MARK: - 5/6. Burndown (session, week)

struct BurndownChart: View {
    let ctx: ChartCtx
    var samples: [TimedSample]
    var currentPct: Double
    var resetAt: Date?
    var window: TimeInterval
    var tint: Color
    @State private var sel: (t: Date, r: Double)?

    /// Recent drain in "fraction of the limit per second". Prefers the recent tail because that is what
    /// you are doing NOW; falls back to the average pace when the tail is too short to trust, so a cold
    /// start still forecasts while genuinely going idle clears the warning instead of freezing it.
    private func drainPerSecond(_ pts: [(t: Date, r: Double)], now: Date, start: Date, remaining: Double) -> Double? {
        let lookback = min(window / 4, 45 * 60)
        let tail = pts.filter { $0.t >= now.addingTimeInterval(-lookback) }
        if let first = tail.first, let last = tail.last {
            let dt = last.t.timeIntervalSince(first.t)
            if dt > 120 {
                let drop = first.r - last.r
                return drop > 0.001 ? drop / dt : nil
            }
        }
        let elapsed = now.timeIntervalSince(start)
        guard elapsed > 300, remaining < 1 else { return nil }
        let used = 1 - remaining
        return used > 0.001 ? used / elapsed : nil
    }

    var body: some View {
        let p = ctx.p
        guard let reset = resetAt else {
            return AnyView(VStack(alignment: .leading, spacing: 5) {
                chartPlaceholder("Waiting for the reset time", p)
                statLine("--", "no window yet", p)
            })
        }
        let now = Date()
        let start = reset.addingTimeInterval(-window)
        let remainingNow = max(0, 1 - currentPct)
        // Within ONE window usage only accumulates, so remaining can only fall, and it can never sit
        // below what the API reports right now. Enforcing both turns a stale sample into a flat stretch
        // instead of a dip-then-jump zigzag.
        let raw = samples.filter { $0.t >= start && $0.t <= now }
            .map { (t: $0.t, r: max(0, min(1, 1 - $0.v))) }.sorted { $0.t < $1.t }
        var pts: [(t: Date, r: Double)] = []
        var runMin = 1.0
        for s in raw { runMin = min(runMin, s.r); pts.append((t: s.t, r: max(runMin, remainingNow))) }
        if pts.first?.t ?? now > start.addingTimeInterval(60) { pts.insert((t: start, r: 1.0), at: 0) }
        pts.append((t: now, r: remainingNow))
        let drain = drainPerSecond(pts, now: now, start: start, remaining: remainingNow)
        let runOut: Date? = {
            guard let d = drain, d > 0, remainingNow > 0 else { return nil }
            let secs = remainingNow / d
            guard secs.isFinite, secs > 0 else { return nil }
            let t = now.addingTimeInterval(secs)
            return t < reset ? t : nil
        }()
        // The curve keeps its METRIC's colour, always. Swapping the entire line, area and dots to
        // warning whenever a run-out exists is why the week reads in a different colour here than
        // in every other place it appears, which looks like a different measurement rather than the
        // same one in trouble. The warning is already carried three times over: by the dashed
        // forecast segment, the run-out point, and the "Empty ~" caption.
        let curve = tint
        let idx = Array(pts.indices)
        return AnyView(VStack(alignment: .leading, spacing: 5) {
            Chart {
                RectangleMark(xStart: .value("t", now), xEnd: .value("t", reset),
                              yStart: .value("y", 0.0), yEnd: .value("y", 1.0))
                    .foregroundStyle(p.ink.opacity(0.03))
                LineMark(x: .value("t", start), y: .value("pace", 1.0), series: .value("s", "pace"))
                    .foregroundStyle(p.sub.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                LineMark(x: .value("t", reset), y: .value("pace", 0.0), series: .value("s", "pace"))
                    .foregroundStyle(p.sub.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                // The "even pace" caption is gone. It rode an invisible PointMark at the middle of
                // the plot, which is exactly where the diagonal it labels crosses the data line, so
                // the words sat on top of the curve. The dashed diagonal is self-explanatory next
                // to the curve it is compared against, and the stat line and the spoken value both
                // say the same thing in words already. (BurnRateChart lost its in-plot label for
                // the same reason.)
                RuleMark(x: .value("t", now)).foregroundStyle(p.ink.opacity(0.18)).lineStyle(StrokeStyle(lineWidth: 1))
                if ctx.style == .area || ctx.style == .gradient {
                    ForEach(idx, id: \.self) { i in
                        AreaMark(x: .value("t", pts[i].t), y: .value("left", pts[i].r), series: .value("s", "left"))
                            .foregroundStyle(LinearGradient(colors: [curve.opacity(0.22), curve.opacity(0.02)],
                                                            startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.monotone)
                    }
                }
                ForEach(idx, id: \.self) { i in
                    LineMark(x: .value("t", pts[i].t), y: .value("left", pts[i].r), series: .value("s", "left"))
                        .foregroundStyle(curve).lineStyle(StrokeStyle(lineWidth: ctx.lineW, lineJoin: .round))
                        .interpolationMethod(.monotone)
                }
                if let ro = runOut {
                    LineMark(x: .value("t", now), y: .value("fc", remainingNow), series: .value("s", "fc"))
                        .foregroundStyle(p.warning.opacity(0.75)).lineStyle(StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                    LineMark(x: .value("t", ro), y: .value("fc", 0.0), series: .value("s", "fc"))
                        .foregroundStyle(p.warning.opacity(0.75)).lineStyle(StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                    PointMark(x: .value("t", ro), y: .value("fc", 0.0)).foregroundStyle(p.warning).symbolSize(26)
                }
                PointMark(x: .value("t", now), y: .value("left", remainingNow))
                    .foregroundStyle(curve.opacity(0.18)).symbolSize(70)
                PointMark(x: .value("t", now), y: .value("left", remainingNow))
                    .foregroundStyle(curve).symbolSize(26)
                if let s = sel {
                    RuleMark(x: .value("t", s.t)).foregroundStyle(p.ink.opacity(0.25))
                    PointMark(x: .value("t", s.t), y: .value("left", s.r))
                        .foregroundStyle(curve).symbolSize(44)
                        .annotation(position: .top, alignment: .leading, spacing: 2) {
                            chartCallout("\(Int((s.r * 100).rounded()))% left", relTimeLabel(s.t, now: now), p)
                        }
                }
            }
            .chartYScale(domain: 0...1)
            .chartXScale(domain: start...reset)
            .chartYAxis { percentYAxis(p, style: ctx.style) }
            .chartXAxis {
                if ctx.style != .minimal {
                    AxisMarks(values: [start, reset]) { _ in AxisGridLine().foregroundStyle(p.ink.opacity(0.06)) }
                }
            }
            .chartPlotStyle { $0.background(Color.clear) }
            .transaction { $0.animation = nil }
            .frame(height: ctx.plotH)
            .hoverCatcher { pt, proxy, geo in
                guard ctx.hover else { return }
                guard let pt, let d: Date = plotValue(proxy, geo, pt, as: Date.self), d <= now else { sel = nil; return }
                sel = pts.min { abs($0.t.timeIntervalSince(d)) < abs($1.t.timeIntervalSince(d)) }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Burndown")
            .accessibilityValue({
                let pctLeft = Int((remainingNow * 100).rounded())
                if let ro = runOut { return "\(pctLeft) percent left, empty about \(shortClock(ro)), before the reset" }
                return "\(pctLeft) percent left, on pace to last to the reset"
            }())
            HStack(spacing: 0) {
                Text(windowEdgeLabel(start, window: window)).font(.system(size: 8.5, design: .monospaced)).foregroundStyle(p.faint)
                Spacer(minLength: 2)
                Text("now").font(.system(size: 8.5)).foregroundStyle(p.sub)
                Spacer(minLength: 2)
                Text(windowEdgeLabel(reset, window: window)).font(.system(size: 8.5, design: .monospaced)).foregroundStyle(p.faint)
            }
            .padding(.leading, 26).padding(.trailing, 6)
            if let ro = runOut {
                statLine("Empty ~\(shortClock(ro))", "", p, tint: p.warning)
            } else {
                statLine("On pace", "· \(weekLeftString(reset)) left", p)   // one vocabulary for time remaining
            }
        })
    }
}

// MARK: - 7. Session + week %

struct UsageLinesChart: View {
    let ctx: ChartCtx
    @State private var selT: Date?
    @State private var memo = ChartMemo()
    @State private var memo2 = ChartMemo()   // the two headline series, keyed the same way
    var body: some View {
        let p = ctx.p
        let now = ctx.tick
        let lower = ctx.lower(ctx.usageSamples.first?.t, now: now)
        // Memoised with everything else in this body. These two filter and bucket the whole
        // retained series, and the body re-runs on every mouse move while the chart is hovered, so
        // they were the one part of this chart still paying full price per frame.
        let (s, w) = memo2.value(ctx.dataKey) {
            (bucketed(ctx.usageSamples.filter { $0.t >= lower }, lower: lower, upper: now, buckets: 120, pickMax: false),
             bucketed(ctx.weeklySamples.filter { $0.t >= lower }, lower: lower, upper: now, buckets: 120, pickMax: false))
        }
        // One line per model, each showing the share of the weekly allowance that model accounted
        // for, so the model lines add up to the Week line. See modelWeekShareSeries in ChartData.swift.
        // Memoised: it walks a week of records, and this body re-runs on every mouse move.
        // Only on day-scale windows and wider. A week's worth of share drawn across four hours is
        // a set of flat dashes, and a model with a single sample in that window is one floating
        // speck. The legend still lists them in its hidden style, so the capability stays visible.
        let models = ctx.window < 86_400 ? [] : memo.value(ctx.dataKey + "|wk\(ctx.weeklyPct)") {
            modelWeekShareSeries(records: ctx.records, weeklyPct: ctx.weeklyPct,
                                 weeklyResetAt: ctx.weeklyResetAt, now: now)
                .map { (label: $0.label,
                        samples: bucketed($0.samples.filter { $0.t >= lower }, lower: lower, upper: now,
                                          buckets: 120, pickMax: false)) }
        }
        let shown = { (k: String) in !ctx.hiddenSeries.contains(k) }
        let selS = selT.flatMap { nearestSample(s, to: $0) }
        let selW = selT.flatMap { nearestSample(w, to: $0) }
        // Everything the legend can offer, in draw order, with its colour.
        // `derived` marks the model lines: measured readings are solid, the per-model split is
        // worked out from the local logs, and the legend says which is which.
        let series: [(key: String, colour: Color, derived: Bool)] =
            [(key: "Session", colour: ctx.accent, derived: false),
             (key: "Week", colour: ctx.secondary, derived: false)]
            + models.map { (key: $0.label, colour: modelHue($0.label, p), derived: true) }
        return VStack(alignment: .leading, spacing: 5) {
            if s.isEmpty && w.isEmpty {
                chartPlaceholder("Warming up, collecting samples", p)
            } else {
                Chart {
                    if shown("Session") {
                        ForEach(s, id: \.t) { pt in
                            LineMark(x: .value("t", pt.t), y: .value("v", pt.v), series: .value("k", "Session"))
                                .foregroundStyle(ctx.accent).lineStyle(StrokeStyle(lineWidth: ctx.lineW)).interpolationMethod(.monotone)
                        }
                    }
                    if shown("Week") {
                        ForEach(w, id: \.t) { pt in
                            LineMark(x: .value("t", pt.t), y: .value("v", pt.v), series: .value("k", "Week"))
                                .foregroundStyle(ctx.secondary).lineStyle(StrokeStyle(lineWidth: ctx.lineW)).interpolationMethod(.monotone)
                        }
                    }
                    ForEach(models, id: \.label) { m in
                        if shown(m.label) {
                            ForEach(m.samples, id: \.t) { pt in
                                LineMark(x: .value("t", pt.t), y: .value("v", pt.v), series: .value("k", m.label))
                                    .foregroundStyle(modelHue(m.label, p))
                                    // Thinner and dashed, so a model never competes with the two
                                    // headline lines and you can tell a derived line from a measured one.
                                    .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [3, 2]))
                                    .interpolationMethod(.monotone)
                            }
                        }
                    }
                    if let t = selT {
                        RuleMark(x: .value("t", t)).foregroundStyle(p.ink.opacity(0.25))
                            .annotation(position: .top, alignment: .leading, spacing: 2) {
                                // The model lines are on this chart, so they belong in its readout.
                                // Showing only S and W meant hovering a chart with five lines on it
                                // answered for two of them and left the rest to be guessed at.
                                // Hidden series are left out: the legend switched them off.
                                let each = models.compactMap { m -> String? in
                                    guard shown(m.label), let v = nearestSample(m.samples, to: t)?.v,
                                          v >= 0.005 else { return nil }
                                    return "\(m.label) \(Int((v * 100).rounded()))%"
                                }
                                chartCallout(
                                    (shown("Session") ? "S \(Int(((selS?.v ?? 0) * 100).rounded()))%" : "")
                                    + (shown("Session") && shown("Week") ? "  \u{00B7}  " : "")
                                    + (shown("Week") ? "W \(Int(((selW?.v ?? 0) * 100).rounded()))%" : ""),
                                    // The SAMPLE's own time, not the pointer's. These readings
                                    // come from nearestSample, which can be minutes away in a
                                    // sparse stretch, and labelling them with wherever the mouse
                                    // happened to be told the reader a value belonged to a moment
                                    // it did not.
                                    relTimeLabel(selS?.t ?? selW?.t ?? t, now: now), p,
                                    detail: each.isEmpty ? nil : each.joined(separator: "  \u{00B7}  "))
                            }
                    }
                }
                .chartYScale(domain: 0...1)
                .chartXScale(domain: lower...now)
                .chartYAxis { percentYAxis(p, style: ctx.style) }
                .chartXAxis { timeXAxis(lower, now, p, style: ctx.style) }
                .chartPlotStyle { $0.background(Color.clear) }
                .transaction { $0.animation = nil }
                .frame(height: ctx.plotH)
                .hoverCatcher { pt, proxy, geo in
                    guard ctx.hover else { return }
                    guard let pt, let d: Date = plotValue(proxy, geo, pt, as: Date.self) else { selT = nil; return }
                    selT = d
                }
            }
            // The legend doubles as the switch: click a name to drop its line, click again to
            // bring it back. A hidden series fades rather than disappearing, so you can always
            // see what you turned off and how to get it back.
            // Every model in use gets an entry, so this can reach six. Six across one line runs off
            // the edge of a 264pt card, so it wraps in threes.
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(stride(from: 0, to: series.count, by: 3)), id: \.self) { start in
                    HStack(spacing: 10) {
                        ForEach(series[start..<min(start + 3, series.count)], id: \.key) { item in
                            Button { ctx.onToggleSeries(item.key) } label: {
                                HStack(spacing: 4) {
                                    // The swatch matches the STROKE, not just the colour. Session
                                    // and Fable can land on nearly the same hue (Fable's family
                                    // colour is clay, and clay is also the default accent), as can
                                    // Week and Opus. Solid versus dashed tells them apart even
                                    // when the colours do not.
                                    LegendSwatch(colour: item.colour, dashed: item.derived,
                                                 on: shown(item.key))
                                    Text(item.key).font(.system(size: 9.5)).foregroundStyle(p.sub).fixedSize()
                                }
                                // The fade stays, but it is no longer the only signal: a hollow
                                // swatch says "off" where a shade only says "quiet".
                                .opacity(shown(item.key) ? 1 : 0.45)
                                // Item 64: these rows hit-test about 12pt tall in a stack 3pt
                                // apart, so the pointer lands between two toggles as often as on
                                // one. A contiguous 18pt band per row fixes that without moving
                                // anything: the padding is inside the button's own label.
                                .padding(.vertical, 3)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain).focusable(false)
                            .accessibilityLabel("\(item.key), \(shown(item.key) ? "shown" : "hidden"). Click to toggle.")
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .animation(.easeInOut(duration: 0.15), value: ctx.hiddenSeries)
        }
    }
}

// MARK: - 8. By model

struct ByModelChart: View {
    let ctx: ChartCtx
    @State private var sel: Date?
    @State private var memo = ChartMemo()
    var body: some View {
        let p = ctx.p
        let now = ctx.tick
        let lower = ctx.lower(ctx.records.first?.date, now: now)
        let n = 14
        let rects = memo.value(ctx.dataKey) { modelStackRects(ctx.records, from: lower, to: now, buckets: n) }
        let families = Array(Set(rects.map(\.key))).sorted()
        // The legend shows the four BIGGEST families. Ranking by name and taking the first four
        // meant that with five models in play the omitted one was chosen alphabetically, so the
        // legend could leave out a heavier model than one it listed.
        let legendFamilies: [String] = {
            var tokens: [String: Double] = [:]
            for r in rects { tokens[r.key, default: 0] += (r.y1 - r.y0) }
            return families.sorted { (tokens[$0] ?? 0, $1) > (tokens[$1] ?? 0, $0) }.prefix(4).map { $0 }
        }()
        let colTop = rects.map(\.y1).max() ?? 0
        let total = rects.reduce(0) { $0 + ($1.y1 - $1.y0) }
        let selRects = sel.flatMap { d in rects.filter { $0.t0 <= d && $0.t1 >= d } } ?? []
        return VStack(alignment: .leading, spacing: 5) {
            if total == 0 {
                chartPlaceholder("No usage in this window", p)
            } else {
                Chart {
                    // Explicitly-bounded rectangles: BarMark stacking on a continuous Date scale draws
                    // nothing, and this way the stack order and bucket widths are exact.
                    ForEach(rects) { r in
                        RectangleMark(xStart: .value("t0", r.t0), xEnd: .value("t1", r.t1),
                                      yStart: .value("y0", r.y0), yEnd: .value("y1", r.y1))
                            .foregroundStyle(modelHue(r.key, p).opacity(sel == nil ? 0.9 : 0.5))
                    }
                    if let d = sel {
                        RuleMark(x: .value("t", d)).foregroundStyle(p.ink.opacity(0.2))
                            .annotation(position: .top, alignment: .leading, spacing: 2) {
                                let txt = selRects.sorted { ($0.y1 - $0.y0) > ($1.y1 - $1.y0) }
                                    .map { "\($0.key) \(fmtTok(Int($0.y1 - $0.y0)))" }.joined(separator: "  ")
                                chartCallout(txt.isEmpty ? "no usage" : txt, relTimeLabel(d, now: now), p)
                            }
                    }
                }
                .chartYScale(domain: 0...(colTop * 1.1))
                .chartXScale(domain: lower...now)
                .chartYAxis { tokenYAxis(colTop, p, style: ctx.style) }
                .chartXAxis { timeXAxis(lower, now, p, style: ctx.style) }
                .chartPlotStyle { $0.background(Color.clear) }
                .transaction { $0.animation = nil }
                .frame(height: ctx.plotH)
                .hoverCatcher { pt, proxy, geo in
                    guard ctx.hover else { return }
                    guard let pt, let d: Date = plotValue(proxy, geo, pt, as: Date.self) else { sel = nil; return }
                    sel = d
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Tokens by model")
                .accessibilityValue("\(fmtTok(Int(total))) tokens across \(families.count) models")
            }
            HStack(spacing: 8) {
                // Ranked by usage, not by name. `families` is a sorted SET, so taking the first
                // four dropped whichever family happened to sort last, which with five models
                // present meant the legend could omit a heavier one than it showed.
                ForEach(legendFamilies, id: \.self) { f in
                    HStack(spacing: 4) {
                        Circle().fill(modelHue(f, p)).frame(width: 5, height: 5)
                        Text(f).font(.system(size: 10)).foregroundStyle(p.sub).fixedSize()
                    }
                }
                Spacer(minLength: 4)
            }.padding(.leading, 26).padding(.trailing, 52)
        }
    }
}

// MARK: - 9. By project

struct ByProjectChart: View {
    let ctx: ChartCtx
    @State private var sel: CatValue?
    @State private var memo = ChartMemo()
    var body: some View {
        let p = ctx.p
        let now = ctx.tick
        let lower = ctx.lower(ctx.records.first?.date, now: now)
        let rows = memo.value(ctx.dataKey) { topProjects(ctx.records, from: lower) }
        let total = rows.reduce(0) { $0 + $1.v }
        return VStack(alignment: .leading, spacing: 5) {
            if rows.isEmpty {
                chartPlaceholder("No usage in this window", p)
            } else {
                Chart {
                    ForEach(rows) { r in
                        BarMark(x: .value("tokens", r.v), y: .value("project", r.name), height: .ratio(kBarFill))
                            .foregroundStyle(ctx.accent.opacity(sel == nil || sel?.id == r.id ? 0.8 : 0.35))
                            .cornerRadius(2)
                            .annotation(position: .trailing, spacing: 3) {
                                Text(fmtTok(Int(r.v))).font(.system(size: 8.5, design: .monospaced))
                                    .foregroundStyle(p.sub).monospacedDigit()
                            }
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading) { v in
                        AxisValueLabel {
                            if let s = v.as(String.self) {
                                Text(s).font(.system(size: 9)).foregroundStyle(p.sub).lineLimit(1).truncationMode(.middle)
                            }
                        }
                    }
                }
                .chartPlotStyle { $0.background(Color.clear) }
                .transaction { $0.animation = nil }
                .frame(height: ctx.plotH)
                .hoverCatcher { pt, proxy, geo in
                    guard ctx.hover else { return }
                    guard let pt, let name: String = proxy.value(atY: pt.y - geo[proxy.plotAreaFrame].minY) else { sel = nil; return }
                    sel = rows.first { $0.name == name }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Tokens by project")
                .accessibilityValue(rows.map { "\($0.name) \(fmtTok(Int($0.v)))" }.joined(separator: ", "))
            }
            statLine(sel.map { fmtTok(Int($0.v)) } ?? fmtTok(Int(total)),
                     sel.map { "· \($0.name)" } ?? "· across \(rows.count) projects", p)
        }
    }
}

// MARK: - 10. Cost per day

struct CostPerDayChart: View {
    let ctx: ChartCtx
    @State private var sel: CatValue?
    @State private var memo = ChartMemo()
    var body: some View {
        let p = ctx.p
        let rows = memo.value(ctx.dataKey) { costPerDay(ctx.records, days: ctx.days) }
        let peak = rows.map(\.v).max() ?? 0
        let total = rows.reduce(0) { $0 + $1.v }
        return VStack(alignment: .leading, spacing: 5) {
            if peak == 0 {
                chartPlaceholder("No spend in the last \(ctx.days) days", p)
            } else {
                Chart {
                    ForEach(rows) { r in
                        BarMark(x: .value("day", r.name), y: .value("cost", r.v), width: .ratio(kBarFill))
                            .foregroundStyle(ctx.accent.opacity(sel == nil || sel?.id == r.id ? 0.85 : 0.35))
                            .cornerRadius(1.5)
                    }
                }
                .chartYAxis {
                    // Three labels, like the percent axes. Two give a reader the floor and the ceiling and
        // nothing to judge a value in between against.
        AxisMarks(position: .leading, values: [0, peak / 2, peak]) { v in
                        AxisGridLine().foregroundStyle(p.ink.opacity(v.as(Double.self) == 0 ? 0.14 : 0.07))
                        AxisValueLabel {
                            if let d = v.as(Double.self) {
                                Text(moneyAxisLabel(d)).font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .foregroundStyle(p.sub).shadow(color: p.bg, radius: 1.5)
                            }
                        }
                    }
                }
                .chartXAxis { thinnedCatXAxis(rows.map(\.name), p, maxLabels: 7) }
                .chartPlotStyle { $0.background(Color.clear) }
                .transaction { $0.animation = nil }
                .frame(height: ctx.plotH)
                .hoverCatcher { pt, proxy, geo in
                    guard ctx.hover else { return }
                    guard let pt, let name: String = plotValue(proxy, geo, pt, as: String.self) else { sel = nil; return }
                    sel = rows.first { $0.name == name }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Cost per day")
                .accessibilityValue("About \(moneyCents(total)) over \(ctx.days) days")
            }
            statLine(sel.map { moneyCents($0.v) } ?? moneyCents(total),
                     sel.map { "· \($0.name)" } ?? "· last \(ctx.days) days", p)
        }
    }
}

// MARK: - 11. Hour of day

struct HourProfileChart: View {
    let ctx: ChartCtx
    @State private var sel: TokBucket?
    @State private var memo = ChartMemo()
    var body: some View {
        let p = ctx.p
        let rows = memo.value(ctx.dataKey) { hourOfDayProfile(ctx.records, days: ctx.days) }
        let peak = rows.map(\.v).max() ?? 0
        let busiest = rows.max { $0.v < $1.v }
        let thisHour = Calendar.current.component(.hour, from: Date())
        return VStack(alignment: .leading, spacing: 5) {
            if peak == 0 {
                chartPlaceholder("No usage in the last \(ctx.days) days", p)
            } else {
                Chart {
                    // Explicit bounds: a numeric x scale gives BarMark no step to infer, so it would
                    // render nothing at all.
                    ForEach(rows) { r in
                        RectangleMark(xStart: .value("h0", Double(r.id) - 0.38),
                                      xEnd: .value("h1", Double(r.id) + 0.38),
                                      yStart: .value("y0", 0.0), yEnd: .value("y1", r.v))
                            .foregroundStyle(ctx.accent.opacity(r.id == thisHour ? 1.0 : (sel == nil || sel?.id == r.id ? 0.7 : 0.3)))
                            .cornerRadius(1)
                    }
                }
                .chartXScale(domain: -0.5...23.5)
                .chartYScale(domain: 0...(peak * 1.1))
                .chartYAxis { tokenYAxis(peak, p, style: ctx.style) }
                .chartXAxis {
                    AxisMarks(values: [0.0, 6.0, 12.0, 18.0]) { v in
                        AxisGridLine().foregroundStyle(p.ink.opacity(0.06))
                        AxisValueLabel {
                            if let h = v.as(Double.self) {
                                Text(hourLabel(Int(h))).font(.system(size: 8.5, design: .monospaced)).foregroundStyle(p.faint)
                            }
                        }
                    }
                }
                .chartPlotStyle { $0.background(Color.clear) }
                .transaction { $0.animation = nil }
                .frame(height: ctx.plotH)
                .hoverCatcher { pt, proxy, geo in
                    guard ctx.hover else { return }
                    guard let pt, let h: Double = plotValue(proxy, geo, pt, as: Double.self) else { sel = nil; return }
                    sel = rows.first { $0.id == Int(h.rounded()) }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Usage by hour of day")
                .accessibilityValue("Busiest around \(hourLabel(busiest?.id ?? 0))")
            }
            statLine(sel.map { fmtTok(Int($0.v)) } ?? fmtTok(Int(busiest?.v ?? 0)),
                     sel.map { "· avg at \(hourLabel($0.id))" } ?? "· avg at \(hourLabel(busiest?.id ?? 0)), your peak hour", p)
        }
    }
}

// MARK: - 12. Activity heatmap

struct DayHeatmapChart: View {
    let ctx: ChartCtx
    @State private var sel: HeatCell?
    @State private var memo = ChartMemo()
    var body: some View {
        let p = ctx.p
        // Weekday labels repeat past 7 days, which would collide on the axis, so the grid is a week.
        let days = min(7, max(3, ctx.days))
        let cells = memo.value(ctx.dataKey) { heatCells(ctx.records, days: days) }
        let peak = cells.map(\.v).max() ?? 0
        let dayLabels = cells.filter { $0.hour == 0 }.map(\.dayLabel)
        return VStack(alignment: .leading, spacing: 5) {
            if peak == 0 {
                chartPlaceholder("No usage in the last \(days) days", p)
            } else {
                GeometryReader { geo in
                    let cols = 24, rows = days
                    let cw = geo.size.width / CGFloat(cols)
                    let ch = geo.size.height / CGFloat(rows)
                    ZStack(alignment: .topLeading) {
                        ForEach(cells) { c in
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(ctx.accent.opacity(c.v <= 0 ? 0.05 : 0.15 + 0.75 * (c.v / peak)))
                                .frame(width: max(1, cw - 1.5), height: max(1, ch - 1.5))
                                .offset(x: CGFloat(c.hour) * cw, y: CGFloat(c.dayIndex) * ch)
                                .overlay(alignment: .topLeading) {
                                    if sel?.id == c.id {
                                        RoundedRectangle(cornerRadius: 1.5).stroke(p.ink.opacity(0.6), lineWidth: 1)
                                            .frame(width: max(1, cw - 1.5), height: max(1, ch - 1.5))
                                            .offset(x: CGFloat(c.hour) * cw, y: CGFloat(c.dayIndex) * ch)
                                    }
                                }
                        }
                    }
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        guard ctx.hover else { return }
                        switch phase {
                        case .active(let pt):
                            let col = Int(pt.x / cw), row = Int(pt.y / ch)
                            sel = cells.first { $0.hour == col && $0.dayIndex == row }
                        case .ended: sel = nil
                        }
                    }
                }
                .frame(height: ctx.plotH)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Activity heatmap")
                .accessibilityValue("\(days) days by hour, busiest cell \(fmtTok(Int(peak))) tokens")
                HStack(spacing: 0) {
                    Text(dayLabels.first ?? "").font(.system(size: 8.5)).foregroundStyle(p.faint)
                    Spacer(minLength: 2)
                    Text("12p").font(.system(size: 8.5, design: .monospaced)).foregroundStyle(p.faint)
                    Spacer(minLength: 2)
                    Text(dayLabels.last ?? "").font(.system(size: 8.5)).foregroundStyle(p.faint)
                }
            }
            statLine(sel.map { fmtTok(Int($0.v)) } ?? fmtTok(Int(peak)),
                     sel.map { "· \($0.dayLabel) \(hourLabel($0.hour))" } ?? "· busiest hour, last \(days) days", p)
        }
    }
}

// MARK: - Shared axes

@AxisContentBuilder func tokenYAxis(_ peak: Double, _ p: Palette, style: ChartStyle) -> some AxisContent {
    if style != .minimal {
        AxisMarks(position: .leading, values: [0, peak]) { v in
            AxisGridLine().foregroundStyle(p.ink.opacity(v.as(Double.self) == 0 ? 0.14 : 0.07))
            AxisValueLabel {
                if let d = v.as(Double.self) {
                    Text(fmtTok(Int(d))).font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(p.sub).shadow(color: p.bg, radius: 1.5)
                }
            }
        }
    }
}

@AxisContentBuilder func percentYAxis(_ p: Palette, style: ChartStyle) -> some AxisContent {
    if style != .minimal {
        AxisMarks(position: .leading, values: [0, 0.5, 1.0]) { v in
            AxisGridLine().foregroundStyle(p.ink.opacity(v.as(Double.self) == 0 ? 0.14 : 0.07))
            AxisValueLabel {
                if let d = v.as(Double.self) {
                    // Rounded, like every other percent in the app. Truncating an axis label puts
                    // "49%" on a gridline drawn at 49.6, which is a tick that lies about where it is.
                    Text("\(Int((d * 100).rounded()))%").font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(p.sub).shadow(color: p.bg, radius: 1.5)
                }
            }
        }
    }
}

@AxisContentBuilder func timeXAxis(_ lower: Date, _ now: Date, _ p: Palette, style: ChartStyle) -> some AxisContent {
    if style != .minimal {
        AxisMarks(values: [lower, lower.addingTimeInterval(now.timeIntervalSince(lower) / 2)]) { v in
            AxisGridLine().foregroundStyle(p.ink.opacity(0.06))
            AxisValueLabel {
                if let d = v.as(Date.self) {
                    Text(relTimeLabel(d, now: now)).font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(p.sub).shadow(color: p.bg, radius: 1.5)
                }
            }
        }
    }
}

/// "12m" / "1h" / "6h" - the width of one bucket, for the volume caption.
func fmtDuration(_ s: TimeInterval) -> String {
    if s < 90 { return "\(max(1, Int(s.rounded())))s" }
    if s < 5400 { return "\(Int((s / 60).rounded()))m" }
    if s < 172800 { return "\(Int((s / 3600).rounded()))h" }
    return "\(Int((s / 86400).rounded()))d"
}
