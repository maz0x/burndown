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
    /// Window start, clamped to the earliest sample for the "all time" sentinel.
    func lower(_ earliest: Date?, now: Date) -> Date {
        window >= 3.0e9 ? (earliest ?? now.addingTimeInterval(-1800)) : now.addingTimeInterval(-window)
    }
}

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

/// The one-line summary under every chart. Bold headline, faint continuation.
@ViewBuilder func statLine(_ big: String, _ small: String, _ p: Palette, tint: Color? = nil) -> some View {
    HStack(spacing: 4) {
        Text(big).font(.system(size: 11, weight: .semibold)).foregroundStyle(tint ?? p.ink)
            .monospacedDigit().lineLimit(1).fixedSize()
        if !small.isEmpty {
            Text(small).font(.system(size: 9.5)).foregroundStyle(p.faint).lineLimit(1)
        }
        Spacer(minLength: 4)
    }
    .padding(.leading, 26).padding(.trailing, 52)   // room for the cadence indicator at the trailing edge
}

// MARK: - 1/2. Burn rate (line, steps)

struct BurnRateChart: View {
    let ctx: ChartCtx
    var stepped = false
    @State private var sel: TimedSample?
    var body: some View {
        let p = ctx.p
        let now = Date()
        let lower = ctx.lower(ctx.burnSamples.first?.t, now: now)
        let win = ctx.burnSamples.filter { $0.t >= lower }
        let mean = win.isEmpty ? 0 : win.map(\.v).reduce(0, +) / Double(win.count)
        let yMax = burnCeiling(percentile(win.map(\.v), 0.97))
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
                        RuleMark(y: .value("avg", min(mean, yMax)))
                            .foregroundStyle(p.sub.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .annotation(position: .top, alignment: .trailing, spacing: 1) {
                                Text("avg \(fmtTok(Int(mean)))").font(.system(size: 9, weight: .medium)).foregroundStyle(p.sub)
                            }
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
                                chartCallout("\(fmtTok(Int(s.v))) / min", relTimeLabel(s.t, now: now), p, detail: dom.map { "→ \($0.name)" })
                            }
                    }
                }
                .chartYScale(domain: 0...yMax)
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
            statLine(sel.map { "\(fmtTok(Int($0.v))) / min" } ?? "\(fmtTok(Int(disp.last?.v ?? 0))) / min",
                     sel != nil ? relTimeLabel(sel!.t, now: now) : "· avg \(fmtTok(Int(mean)))", p)
        }
    }
}

// MARK: - 3. Volume bars

struct VolumeBarsChart: View {
    let ctx: ChartCtx
    @State private var sel: TokBucket?
    var body: some View {
        let p = ctx.p
        let now = Date()
        let lower = ctx.lower(ctx.records.first?.date, now: now)
        let n = 16
        let buckets = bucketRecords(ctx.records, from: lower, to: now, buckets: n)
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
    var body: some View {
        let p = ctx.p
        let now = Date()
        let lower = ctx.lower(ctx.records.first?.date, now: now)
        let pts = cumulativeRecords(ctx.records, from: lower, to: now, buckets: 90)
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
                            .foregroundStyle(ctx.accent).lineStyle(StrokeStyle(lineWidth: 1.6))
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
        let curve = runOut != nil ? p.warning : tint
        let idx = Array(pts.indices)
        return AnyView(VStack(alignment: .leading, spacing: 5) {
            Chart {
                RectangleMark(xStart: .value("t", now), xEnd: .value("t", reset),
                              yStart: .value("y", 0.0), yEnd: .value("y", 1.0))
                    .foregroundStyle(p.ink.opacity(0.03))
                LineMark(x: .value("t", start), y: .value("pace", 1.0), series: .value("s", "pace"))
                    .foregroundStyle(p.sub.opacity(0.45)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                LineMark(x: .value("t", reset), y: .value("pace", 0.0), series: .value("s", "pace"))
                    .foregroundStyle(p.sub.opacity(0.45)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                PointMark(x: .value("t", start.addingTimeInterval(window / 2)), y: .value("pace", 0.5))
                    .symbolSize(0)
                    .annotation(position: .top, spacing: 1) {
                        Text("even pace").font(.system(size: 8)).foregroundStyle(p.faint)
                    }
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
                        .foregroundStyle(curve).lineStyle(StrokeStyle(lineWidth: 1.8, lineJoin: .round))
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
                statLine("On pace", "· \(weekLeftString(reset)) of runway", p)
            }
        })
    }
}

// MARK: - 7. Session + week %

struct UsageLinesChart: View {
    let ctx: ChartCtx
    @State private var selT: Date?
    var body: some View {
        let p = ctx.p
        let now = Date()
        let lower = ctx.lower(ctx.usageSamples.first?.t, now: now)
        let s = bucketed(ctx.usageSamples.filter { $0.t >= lower }, lower: lower, upper: now, buckets: 120, pickMax: false)
        let w = bucketed(ctx.weeklySamples.filter { $0.t >= lower }, lower: lower, upper: now, buckets: 120, pickMax: false)
        let selS = selT.flatMap { nearestSample(s, to: $0) }
        let selW = selT.flatMap { nearestSample(w, to: $0) }
        return VStack(alignment: .leading, spacing: 5) {
            if s.isEmpty && w.isEmpty {
                chartPlaceholder("Warming up, collecting samples", p)
            } else {
                Chart {
                    ForEach(s, id: \.t) { pt in
                        LineMark(x: .value("t", pt.t), y: .value("v", pt.v), series: .value("k", "Session"))
                            .foregroundStyle(ctx.accent).lineStyle(StrokeStyle(lineWidth: 1.6)).interpolationMethod(.monotone)
                    }
                    ForEach(w, id: \.t) { pt in
                        LineMark(x: .value("t", pt.t), y: .value("v", pt.v), series: .value("k", "Week"))
                            .foregroundStyle(ctx.secondary).lineStyle(StrokeStyle(lineWidth: 1.6)).interpolationMethod(.monotone)
                    }
                    if let t = selT {
                        RuleMark(x: .value("t", t)).foregroundStyle(p.ink.opacity(0.25))
                            .annotation(position: .top, alignment: .leading, spacing: 2) {
                                chartCallout("S \(Int(((selS?.v ?? 0) * 100).rounded()))%  ·  W \(Int(((selW?.v ?? 0) * 100).rounded()))%",
                                             relTimeLabel(t, now: now), p)
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
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Session and weekly percentage")
                .accessibilityValue("Session \(Int(ctx.sessionPct * 100)) percent, week \(Int(ctx.weeklyPct * 100)) percent")
            }
            HStack(spacing: 8) {
                legendDot("Session", ctx.accent, p)
                legendDot("Week", ctx.secondary, p)
                Spacer(minLength: 4)
            }.padding(.leading, 26).padding(.trailing, 52)
        }
    }
    private func legendDot(_ t: String, _ c: Color, _ p: Palette) -> some View {
        HStack(spacing: 4) {
            Circle().fill(c).frame(width: 5, height: 5)
            Text(t).font(.system(size: 10)).foregroundStyle(p.sub)
        }
    }
}

// MARK: - 8. By model

struct ByModelChart: View {
    let ctx: ChartCtx
    @State private var sel: Date?
    var body: some View {
        let p = ctx.p
        let now = Date()
        let lower = ctx.lower(ctx.records.first?.date, now: now)
        let n = 14
        let rects = modelStackRects(ctx.records, from: lower, to: now, buckets: n)
        let families = Array(Set(rects.map(\.key))).sorted()
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
                ForEach(families.prefix(4), id: \.self) { f in
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
    var body: some View {
        let p = ctx.p
        let now = Date()
        let lower = ctx.lower(ctx.records.first?.date, now: now)
        let rows = topProjects(ctx.records, from: lower)
        let total = rows.reduce(0) { $0 + $1.v }
        return VStack(alignment: .leading, spacing: 5) {
            if rows.isEmpty {
                chartPlaceholder("No usage in this window", p)
            } else {
                Chart {
                    ForEach(rows) { r in
                        BarMark(x: .value("tokens", r.v), y: .value("project", r.name), height: .ratio(0.62))
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
    var body: some View {
        let p = ctx.p
        let rows = costPerDay(ctx.records, days: ctx.days)
        let peak = rows.map(\.v).max() ?? 0
        let total = rows.reduce(0) { $0 + $1.v }
        return VStack(alignment: .leading, spacing: 5) {
            if peak == 0 {
                chartPlaceholder("No spend in the last \(ctx.days) days", p)
            } else {
                Chart {
                    ForEach(rows) { r in
                        BarMark(x: .value("day", r.name), y: .value("cost", r.v), width: .ratio(0.7))
                            .foregroundStyle(ctx.accent.opacity(sel == nil || sel?.id == r.id ? 0.85 : 0.35))
                            .cornerRadius(1.5)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: [0, peak]) { v in
                        AxisGridLine().foregroundStyle(p.ink.opacity(v.as(Double.self) == 0 ? 0.14 : 0.07))
                        AxisValueLabel {
                            if let d = v.as(Double.self) {
                                Text(d >= 1 ? "$\(Int(d))" : "$0").font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .foregroundStyle(p.sub).shadow(color: p.bg, radius: 1.5)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks { v in
                        AxisValueLabel {
                            if let s = v.as(String.self) {
                                Text(s).font(.system(size: 8.5, design: .monospaced)).foregroundStyle(p.faint)
                            }
                        }
                    }
                }
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
    var body: some View {
        let p = ctx.p
        let rows = hourOfDayProfile(ctx.records, days: ctx.days)
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
    var body: some View {
        let p = ctx.p
        // Weekday labels repeat past 7 days, which would collide on the axis, so the grid is a week.
        let days = min(7, max(3, ctx.days))
        let cells = heatCells(ctx.records, days: days)
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
                    Text("\(Int(d * 100))%").font(.system(size: 9, weight: .medium, design: .monospaced))
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
