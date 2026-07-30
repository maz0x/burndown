import SwiftUI
import Charts

// The second dozen charts. Same contract as the first: ~74pt tall, legible over glass in both
// appearances, and a hover that answers with the real number.

// MARK: - 13. Burn distribution

struct BurnHistogramChart: View {
    let ctx: ChartCtx
    @State private var sel: CatValue?
    var body: some View {
        let p = ctx.p
        let now = Date()
        let lower = ctx.lower(ctx.burnSamples.first?.t, now: now)
        let bands = burnHistogram(ctx.burnSamples, from: lower)
        let peak = bands.map(\.v).max() ?? 0
        let total = bands.reduce(0) { $0 + $1.v }
        let busiest = bands.filter { $0.v > 0 }.last
        return VStack(alignment: .leading, spacing: 5) {
            if peak == 0 {
                chartPlaceholder("Warming up, collecting samples", p)
            } else {
                Chart {
                    ForEach(bands) { b in
                        BarMark(x: .value("band", b.name), y: .value("count", b.v), width: .ratio(0.72))
                            .foregroundStyle(ctx.accent.opacity(sel == nil || sel?.id == b.id ? 0.8 : 0.3))
                            .cornerRadius(1.5)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: [0, peak]) { v in
                        AxisGridLine().foregroundStyle(p.ink.opacity(v.as(Double.self) == 0 ? 0.14 : 0.07))
                        AxisValueLabel {
                            if let d = v.as(Double.self) {
                                Text("\(Int(d))").font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .foregroundStyle(p.sub).shadow(color: p.bg, radius: 1.5)
                            }
                        }
                    }
                }
                .chartXAxis {
                    // Label alternating bands only: all seven at 7.5pt collide at narrow widths
                    // (the Settings gallery cards). Hover still names every band exactly.
                    AxisMarks(values: bands.enumerated().filter { $0.offset % 2 == 0 }.map { $0.element.name }) { v in
                        AxisValueLabel {
                            if let s = v.as(String.self) {
                                Text(s).font(.system(size: 7.5, design: .monospaced)).foregroundStyle(p.faint)
                            }
                        }
                    }
                }
                .chartPlotStyle { $0.background(Color.clear) }
                .transaction { $0.animation = nil }
                .frame(height: kChartH)
                .hoverCatcher { pt, proxy, geo in
                    guard ctx.hover else { return }
                    guard let pt, let s: String = plotValue(proxy, geo, pt, as: String.self) else { sel = nil; return }
                    sel = bands.first { $0.name == s }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Burn rate distribution")
                .accessibilityValue("\(Int(total)) samples, heaviest band \(busiest?.name ?? "none")")
            }
            statLine(sel.map { "\(Int($0.v)) samples" } ?? "\(Int(total)) samples",
                     sel.map { "· at \($0.name)/min" } ?? "· top band \(busiest?.name ?? "-")/min", p)
        }
    }
}

/// The top half of a circle, swept left to right, filled to `frac` of the way round. Anchored to the
/// bottom of its rect so the flat edge sits on the baseline.
struct SemiArc: Shape {
    var frac: Double
    func path(in r: CGRect) -> Path {
        var path = Path()
        let radius = max(1, min(r.width / 2, r.height) - 3)
        let center = CGPoint(x: r.midX, y: r.maxY - 1)
        path.addArc(center: center, radius: radius,
                    startAngle: .degrees(180),
                    endAngle: .degrees(180 + 180 * max(0.001, min(1, frac))),
                    clockwise: false)
        return path
    }
}

// MARK: - 14. Pace gauge

struct PaceGaugeChart: View {
    let ctx: ChartCtx
    var body: some View {
        let p = ctx.p
        let now = Date()
        // Compare the session and the week on the same footing: elapsed share of the window against
        // spent share of the budget. Ratio > 1 means you are spending faster than the window refills.
        func ratio(pct: Double, reset: Date?, window: TimeInterval) -> Double? {
            guard let reset else { return nil }
            let elapsed = window - max(0, reset.timeIntervalSince(now))
            guard elapsed > 60 else { return nil }
            let timeShare = min(1, elapsed / window)
            guard timeShare > 0.01 else { return nil }
            return pct / timeShare
        }
        let rS = ratio(pct: ctx.sessionPct, reset: ctx.sessionResetAt, window: 5 * 3600)
        let rW = ratio(pct: ctx.weeklyPct, reset: ctx.weeklyResetAt, window: 7 * 86400)
        let worst = max(rS ?? 0, rW ?? 0)
        let hue: Color = worst >= 1.6 ? p.overLimit : (worst >= 1.0 ? p.warning : p.live)
        return VStack(alignment: .leading, spacing: 5) {
            if rS == nil && rW == nil {
                chartPlaceholder("Waiting for a full window", p)
            } else {
                HStack(spacing: 14) {
                    // The dial: an explicit top semicircle, 0 to 2x, with 1.0x marked at its apex.
                    // (Trimming a Circle starts at 12 o'clock and needed rotation gymnastics that flipped
                    // the readout upside down; an arc shape states the geometry outright.)
                    ZStack(alignment: .bottom) {
                        SemiArc(frac: 1).stroke(p.track, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        SemiArc(frac: min(1, worst / 2)).stroke(hue, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        SemiArc(frac: 0.5).stroke(p.bg, style: StrokeStyle(lineWidth: 7, dash: [1.5, 999]))
                        HStack(alignment: .firstTextBaseline, spacing: 1) {
                            Text(String(format: "%.1f", worst)).font(.system(size: 15, weight: .semibold, design: .serif))
                                .foregroundStyle(hue).monospacedDigit()
                            Text("×").font(.system(size: 8.5)).foregroundStyle(p.faint)
                        }
                    }
                    .frame(width: 62, height: 38)
                    VStack(alignment: .leading, spacing: 7) {
                        paceRow("Session", rS, p)
                        paceRow("Week", rW, p)
                    }
                    Spacer(minLength: 0)
                }
                .frame(height: kChartH)
                .help("Spent share of the budget divided by elapsed share of the window. 1.0x is exactly on pace.")
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Pace gauge")
                .accessibilityValue(String(format: "%.1f times the even pace", worst))
            }
            statLine(worst >= 1.0 ? "Over pace" : "Comfortable",
                     worst >= 1.0 ? "· faster than the window refills" : "· on an even pace",
                     p, tint: worst >= 1.0 ? hue : nil)
        }
    }
    private func paceRow(_ name: String, _ r: Double?, _ p: Palette) -> some View {
        HStack(spacing: 6) {
            Text(name).font(.system(size: 10)).foregroundStyle(p.sub).frame(width: 46, alignment: .leading)
            if let r {
                ZStack(alignment: .leading) {
                    Capsule().fill(p.track).frame(width: 54, height: 4)
                    Capsule().fill(r >= 1.0 ? p.warning : p.live).frame(width: max(3, 54 * min(1, r / 2)), height: 4)
                    Rectangle().fill(p.ink.opacity(0.35)).frame(width: 1, height: 7).offset(x: 27)
                }
                Text(String(format: "%.1f×", r)).font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(p.ink).monospacedDigit()
            } else {
                Text("--").font(.system(size: 10)).foregroundStyle(p.faint)
            }
        }
    }
}

// MARK: - 15. Model limits

struct ModelCapsChart: View {
    let ctx: ChartCtx
    var body: some View {
        let p = ctx.p
        var rows: [(name: String, pct: Double, active: Bool)] = [("All models", ctx.weeklyPct, false)]
        rows += ctx.modelLimits.map { (name: $0.label, pct: $0.pct, active: $0.active) }
        return VStack(alignment: .leading, spacing: 5) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(rows.indices, id: \.self) { i in
                    let r = rows[i]
                    HStack(spacing: 8) {
                        if r.active { Circle().fill(p.session).frame(width: 4, height: 4) } else { Spacer().frame(width: 4) }
                        Text(r.name).font(.system(size: 11, weight: r.active ? .semibold : .regular))
                            .foregroundStyle(r.active ? p.ink : p.sub)
                            .frame(width: 62, alignment: .leading).lineLimit(1)
                        HBar(pct: r.pct, color: r.active ? p.session : kSlate, track: p.track, height: 5,
                             a11yLabel: "\(r.name) weekly limit")
                        Text("\(Int(((1 - r.pct) * 100).rounded()))%")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(p.ink).monospacedDigit().fixedSize()
                    }
                }
                if rows.count < 3 { Spacer(minLength: 0) }
            }
            // minHeight, not height: the API can report several per-model caps, and a fixed frame
            // would clip the fourth row. The card grows with the rows instead.
            .frame(minHeight: kChartH, alignment: .top)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Weekly limits")
            .accessibilityValue(rows.map { "\($0.name) \(Int((1 - $0.pct) * 100)) percent left" }.joined(separator: ", "))
            statLine("\(rows.count) weekly limit\(rows.count == 1 ? "" : "s")",
                     ctx.modelLimits.contains(where: { $0.active }) ? "· dot marks the one binding first" : "· percentages are what is LEFT", p)
        }
    }
}

// MARK: - 16. Top chats

struct TopChatsChart: View {
    let ctx: ChartCtx
    @State private var sel: CatValue?
    var body: some View {
        let p = ctx.p
        let now = Date()
        let lower = ctx.lower(ctx.records.first?.date, now: now)
        let rows = topChats(ctx.records, from: lower)
        let total = rows.reduce(0) { $0 + $1.v }
        return VStack(alignment: .leading, spacing: 5) {
            if rows.isEmpty {
                chartPlaceholder("No chat activity in this window", p)
            } else {
                Chart {
                    ForEach(rows) { r in
                        BarMark(x: .value("tokens", r.v), y: .value("chat", r.name), height: .ratio(0.6))
                            .foregroundStyle(ctx.accent.opacity(sel == nil || sel?.id == r.id ? 0.8 : 0.3))
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
                                Text(s).font(.system(size: 9)).foregroundStyle(p.sub)
                                    .lineLimit(1).truncationMode(.middle)
                            }
                        }
                    }
                }
                .chartPlotStyle { $0.background(Color.clear) }
                .transaction { $0.animation = nil }
                .frame(height: kChartH)
                .hoverCatcher { pt, proxy, geo in
                    guard ctx.hover else { return }
                    guard let pt, let name: String = proxy.value(atY: pt.y - geo[proxy.plotAreaFrame].minY) else { sel = nil; return }
                    sel = rows.first { $0.name == name }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Top chats")
                .accessibilityValue(rows.map { "\($0.name) \(fmtTok(Int($0.v)))" }.joined(separator: ", "))
            }
            statLine(sel.map { fmtTok(Int($0.v)) } ?? fmtTok(Int(total)),
                     sel.map { "· \($0.name)" } ?? "· top \(rows.count) chats", p)
        }
    }
}

// MARK: - 17/18. Proportional share (model, project)

struct ShareSplitChart: View {
    let ctx: ChartCtx
    var byModel: Bool
    @State private var sel: CatValue?
    var body: some View {
        let p = ctx.p
        let now = Date()
        let lower = ctx.lower(ctx.records.first?.date, now: now)
        let rows = byModel ? shareSplit(ctx.records, from: lower) { modelFamily($0.model) }
                           : shareSplit(ctx.records, from: lower) { $0.project.isEmpty ? "(unknown)" : $0.project }
        let shown = Array(rows.prefix(6))
        func hue(_ i: Int, _ name: String) -> Color {
            byModel ? modelHue(name, p) : categoryHue(i, ctx.accent, p)
        }
        return VStack(alignment: .leading, spacing: 7) {
            if shown.isEmpty {
                chartPlaceholder("No usage in this window", p)
            } else {
                // One proportional bar: the whole window is the bar, each slice is a share of it.
                GeometryReader { g in
                    let gap: CGFloat = 2
                    let avail = max(0, g.size.width - gap * CGFloat(max(0, shown.count - 1)))
                    HStack(spacing: gap) {
                        ForEach(Array(shown.enumerated()), id: \.element.id) { i, r in
                            hue(i, r.name)
                                .opacity(sel == nil || sel?.id == r.id ? 1 : 0.4)
                                .frame(width: avail * min(1, max(0.004, r.v)))
                                .onHover { inside in
                                    guard ctx.hover else { return }
                                    sel = inside ? r : (sel?.id == r.id ? nil : sel)
                                }
                        }
                    }
                }
                .frame(height: 22).clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                // THREE legend rows total, overflow row included: a fourth row runs past the card and
                // collides with the stat line beneath it.
                VStack(alignment: .leading, spacing: 3) {
                    let overflow = shown.count > 3
                    let lead = Array(shown.prefix(overflow ? 2 : 3))
                    ForEach(Array(lead.enumerated()), id: \.element.id) { i, r in
                        legendRow(hue(i, r.name), r.name, r.v, p)
                    }
                    if overflow {
                        let rest = shown.dropFirst(2).reduce(0) { $0 + $1.v }
                        legendRow(p.faint, "\(shown.count - 2) more", rest, p)
                    }
                }
                .frame(height: kChartH - 30, alignment: .top)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(byModel ? "Model mix" : "Project mix")
                .accessibilityValue(shown.map { "\($0.name) \(Int($0.v * 100)) percent" }.joined(separator: ", "))
            }
            statLine(sel.map { "\(Int(($0.v * 100).rounded()))%" } ?? "\(shown.count) \(shown.count == 1 ? (byModel ? "model" : "project") : (byModel ? "models" : "projects"))",
                     sel.map { "· \($0.name)" } ?? "· share of window", p)
        }
    }

    private func legendRow(_ c: Color, _ name: String, _ v: Double, _ p: Palette) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 1.5).fill(c).frame(width: 7, height: 7)
            Text(name).font(.system(size: 9.5)).foregroundStyle(p.sub).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 4)
            Text("\(Int((v * 100).rounded()))%").font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(p.faint).monospacedDigit()
        }
    }
}

/// Distinct-but-calm hues for category slices that have no inherent colour of their own.
func categoryHue(_ i: Int, _ accent: Color, _ p: Palette) -> Color {
    let ramp: [Color] = [accent, kSlate,
                         Color(red: 0.46, green: 0.58, blue: 0.52),
                         Color(red: 0.66, green: 0.56, blue: 0.44),
                         Color(red: 0.55, green: 0.50, blue: 0.62),
                         Color(red: 0.70, green: 0.45, blue: 0.45)]
    return ramp[i % ramp.count]
}

// MARK: - 19. Day of week

struct WeekdayProfileChart: View {
    let ctx: ChartCtx
    @State private var sel: CatValue?
    var body: some View {
        let p = ctx.p
        let rows = weekdayProfile(ctx.records, days: ctx.days)
        let peak = rows.map(\.v).max() ?? 0
        let today = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"][(Calendar.current.component(.weekday, from: Date()) + 5) % 7]
        let busiest = rows.max { $0.v < $1.v }
        return VStack(alignment: .leading, spacing: 5) {
            if peak == 0 {
                chartPlaceholder("No usage in the last \(ctx.days) days", p)
            } else {
                Chart {
                    ForEach(rows) { r in
                        BarMark(x: .value("day", r.name), y: .value("tokens", r.v), width: .ratio(0.68))
                            .foregroundStyle(ctx.accent.opacity(r.name == today ? 1.0 : (sel == nil || sel?.id == r.id ? 0.7 : 0.3)))
                            .cornerRadius(1.5)
                    }
                }
                .chartYAxis { tokenYAxis(peak, p, style: ctx.style) }
                .chartXAxis {
                    AxisMarks { v in
                        AxisValueLabel {
                            if let s = v.as(String.self) {
                                Text(s).font(.system(size: 8.5)).foregroundStyle(p.faint)
                            }
                        }
                    }
                }
                .chartPlotStyle { $0.background(Color.clear) }
                .transaction { $0.animation = nil }
                .frame(height: kChartH)
                .hoverCatcher { pt, proxy, geo in
                    guard ctx.hover else { return }
                    guard let pt, let s: String = plotValue(proxy, geo, pt, as: String.self) else { sel = nil; return }
                    sel = rows.first { $0.name == s }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Usage by day of week")
                .accessibilityValue("Busiest \(busiest?.name ?? "none")")
            }
            statLine(sel.map { fmtTok(Int($0.v)) } ?? fmtTok(Int(busiest?.v ?? 0)),
                     sel.map { "· \($0.name) average" } ?? "· \(busiest?.name ?? "-") is your heaviest day", p)
        }
    }
}

// MARK: - 20. Tokens per day

struct DailyTokensChart: View {
    let ctx: ChartCtx
    @State private var sel: CatValue?
    var body: some View {
        let p = ctx.p
        let rows = dailyTokens(ctx.records, days: ctx.days)
        let peak = rows.map(\.v).max() ?? 0
        let active = rows.filter { $0.v > 0 }
        let avg = active.isEmpty ? 0 : active.reduce(0) { $0 + $1.v } / Double(active.count)
        return VStack(alignment: .leading, spacing: 5) {
            if peak == 0 {
                chartPlaceholder("No usage in the last \(ctx.days) days", p)
            } else {
                Chart {
                    ForEach(rows) { r in
                        BarMark(x: .value("day", r.name), y: .value("tokens", r.v), width: .ratio(0.7))
                            .foregroundStyle(ctx.accent.opacity(sel == nil || sel?.id == r.id ? 0.8 : 0.3))
                            .cornerRadius(1.5)
                    }
                    if avg > 0 {
                        RuleMark(y: .value("avg", avg))
                            .foregroundStyle(p.sub.opacity(0.55))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .annotation(position: .top, alignment: .leading, spacing: 1) {
                                Text("avg \(fmtTok(Int(avg)))").font(.system(size: 8.5, weight: .medium)).foregroundStyle(p.sub)
                            }
                    }
                }
                .chartYAxis { tokenYAxis(peak, p, style: ctx.style) }
                .chartXAxis {
                    AxisMarks { v in
                        AxisValueLabel {
                            if let s = v.as(String.self) {
                                Text(s).font(.system(size: 8, design: .monospaced)).foregroundStyle(p.faint)
                            }
                        }
                    }
                }
                .chartPlotStyle { $0.background(Color.clear) }
                .transaction { $0.animation = nil }
                .frame(height: kChartH)
                .hoverCatcher { pt, proxy, geo in
                    guard ctx.hover else { return }
                    guard let pt, let s: String = plotValue(proxy, geo, pt, as: String.self) else { sel = nil; return }
                    sel = rows.first { $0.name == s }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Tokens per day")
                .accessibilityValue("Average \(fmtTok(Int(avg))) per active day")
            }
            statLine(sel.map { fmtTok(Int($0.v)) } ?? fmtTok(Int(avg)),
                     sel.map { "· \($0.name)" } ?? "· per active day, last \(ctx.days)d", p)
        }
    }
}

// MARK: - 21. Session blocks

struct SessionBlocksChart: View {
    let ctx: ChartCtx
    @State private var sel: SessionBlock?
    var body: some View {
        let p = ctx.p
        let blocks = sessionBlocks(ctx.records, days: ctx.days)
        let shown = Array(blocks.suffix(18))
        let peak = shown.map(\.tokens).max() ?? 0
        let avg = shown.isEmpty ? 0 : shown.reduce(0) { $0 + $1.tokens } / Double(shown.count)
        return VStack(alignment: .leading, spacing: 5) {
            if shown.isEmpty {
                chartPlaceholder("No session blocks in the last \(ctx.days) days", p)
            } else {
                Chart {
                    // Explicit bounds: block ids form a continuous numeric scale, where BarMark has no
                    // step to infer and renders nothing.
                    ForEach(shown) { b in
                        RectangleMark(xStart: .value("b0", Double(b.id) - 0.36),
                                      xEnd: .value("b1", Double(b.id) + 0.36),
                                      yStart: .value("y0", 0.0), yEnd: .value("y1", b.tokens))
                            .foregroundStyle(ctx.accent.opacity(sel == nil || sel?.id == b.id ? 0.8 : 0.3))
                            .cornerRadius(1.5)
                    }
                }
                .chartXScale(domain: (Double(shown.first?.id ?? 0) - 0.6)...(Double(shown.last?.id ?? 1) + 0.6))
                .chartYScale(domain: 0...(peak * 1.1))
                .chartXAxis(.hidden)
                .chartYAxis { tokenYAxis(peak, p, style: ctx.style) }
                .chartPlotStyle { $0.background(Color.clear) }
                .transaction { $0.animation = nil }
                .frame(height: kChartH)
                .hoverCatcher { pt, proxy, geo in
                    guard ctx.hover else { return }
                    guard let pt, let x: Double = plotValue(proxy, geo, pt, as: Double.self) else { sel = nil; return }
                    sel = shown.min { abs(Double($0.id) - x) < abs(Double($1.id) - x) }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Session blocks")
                .accessibilityValue("\(shown.count) blocks, average \(fmtTok(Int(avg)))")
                HStack(spacing: 0) {
                    Text(shortClock(shown.first?.start ?? Date())).font(.system(size: 8.5, design: .monospaced)).foregroundStyle(p.faint)
                    Spacer(minLength: 2)
                    Text("\(shown.count) blocks").font(.system(size: 8.5)).foregroundStyle(p.faint)
                    Spacer(minLength: 2)
                    Text("now").font(.system(size: 8.5)).foregroundStyle(p.sub)
                }.padding(.leading, 26).padding(.trailing, 6)
            }
            statLine(sel.map { fmtTok(Int($0.tokens)) } ?? fmtTok(Int(avg)),
                     sel.map { "· block from \(shortClock($0.start))" } ?? "· average block", p)
        }
    }
}

// MARK: - 22/23. Composition (cache mix, input vs output)

struct CompositionChart: View {
    let ctx: ChartCtx
    var cacheOnly: Bool
    @State private var sel: Date?
    var body: some View {
        let p = ctx.p
        let now = Date()
        let lower = ctx.lower(ctx.records.first?.date, now: now)
        let n = 14
        let rects = cacheOnly ? cacheMixRects(ctx.records, from: lower, to: now, buckets: n)
                              : inputOutputRects(ctx.records, from: lower, to: now, buckets: n)
        // Short legend labels: the full names ("Cache write") made the legend row wider than the card,
        // which pushed the whole chart out past the popover's edge.
        let keys = cacheOnly ? ["Fresh", "Cache read"] : ["Input", "Output", "Cache write", "Cache read"]
        let legendName: [String: String] = ["Input": "In", "Output": "Out", "Cache write": "Write", "Cache read": "Read"]
        let colTop = rects.map(\.y1).max() ?? 0
        let selRects = sel.flatMap { d in rects.filter { $0.t0 <= d && $0.t1 >= d } } ?? []
        // Cache hit share across the window: what fraction of everything came from cache reads.
        let cacheTotal = rects.filter { $0.key == "Cache read" }.reduce(0) { $0 + ($1.y1 - $1.y0) }
        let grand = rects.reduce(0) { $0 + ($1.y1 - $1.y0) }
        func hue(_ k: String) -> Color {
            switch k {
            case "Cache read":  return kSlate
            case "Cache write": return Color(red: 0.46, green: 0.58, blue: 0.52)
            case "Output":      return ctx.accent
            case "Input":       return ctx.accent.opacity(0.55)
            default:            return ctx.accent
            }
        }
        return VStack(alignment: .leading, spacing: 5) {
            if grand == 0 {
                chartPlaceholder("No usage in this window", p)
            } else {
                Chart {
                    ForEach(rects) { r in
                        RectangleMark(xStart: .value("t0", r.t0), xEnd: .value("t1", r.t1),
                                      yStart: .value("y0", r.y0), yEnd: .value("y1", r.y1))
                            .foregroundStyle(hue(r.key).opacity(sel == nil ? 0.9 : 0.5))
                    }
                    if let d = sel {
                        RuleMark(x: .value("t", d)).foregroundStyle(p.ink.opacity(0.2))
                            .annotation(position: .top, alignment: .leading, spacing: 2) {
                                let txt = selRects.map { "\($0.key) \(fmtTok(Int($0.y1 - $0.y0)))" }.joined(separator: "  ")
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
                .frame(height: kChartH)
                .hoverCatcher { pt, proxy, geo in
                    guard ctx.hover else { return }
                    guard let pt, let d: Date = plotValue(proxy, geo, pt, as: Date.self) else { sel = nil; return }
                    sel = d
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(cacheOnly ? "Cache efficiency" : "Token composition")
                .accessibilityValue(cacheOnly ? "\(Int(cacheTotal / max(1, grand) * 100)) percent from cache" : "\(fmtTok(Int(grand))) tokens")
                HStack(spacing: 7) {
                    ForEach(keys, id: \.self) { k in
                        HStack(spacing: 3) {
                            Circle().fill(hue(k)).frame(width: 5, height: 5)
                            Text(legendName[k] ?? k).font(.system(size: 8.5)).foregroundStyle(p.sub)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 26).padding(.trailing, 52)
            }
            if cacheOnly {
                statLine("\(Int(cacheTotal / max(1, grand) * 100))% cached",
                         "· \(fmtTok(Int(grand - cacheTotal))) fresh", p)
            } else {
                statLine(fmtTok(Int(grand)), "· all token types", p)
            }
        }
    }
}

// MARK: - 24. Spend to date

struct MonthCostChart: View {
    let ctx: ChartCtx
    @State private var sel: CatValue?
    var body: some View {
        let p = ctx.p
        let (pts, projected) = cumulativeCost(ctx.records, days: ctx.days)
        let total = pts.last?.v ?? 0
        let top = max(projected, total) * 1.1
        return VStack(alignment: .leading, spacing: 5) {
            if total == 0 {
                chartPlaceholder("No spend in the last \(ctx.days) days", p)
            } else {
                Chart {
                    ForEach(pts) { c in
                        AreaMark(x: .value("day", c.name), y: .value("spend", c.v))
                            .foregroundStyle(LinearGradient(colors: [ctx.accent.opacity(0.22), ctx.accent.opacity(0.02)],
                                                            startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.monotone)
                        LineMark(x: .value("day", c.name), y: .value("spend", c.v))
                            .foregroundStyle(ctx.accent).lineStyle(StrokeStyle(lineWidth: 1.6))
                            .interpolationMethod(.monotone)
                    }
                    if projected > total {
                        RuleMark(y: .value("proj", projected))
                            .foregroundStyle(p.sub.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .annotation(position: .top, alignment: .trailing, spacing: 1) {
                                Text("at this rate \(moneyCents(projected))").font(.system(size: 8.5, weight: .medium))
                                    .foregroundStyle(p.sub)
                            }
                    }
                    if let s = sel {
                        RuleMark(x: .value("day", s.name)).foregroundStyle(p.ink.opacity(0.25))
                            .annotation(position: .top, alignment: .leading, spacing: 2) {
                                chartCallout(moneyCents(s.v), "by \(s.name)", p)
                            }
                    }
                }
                .chartYScale(domain: 0...max(0.01, top))
                .chartYAxis {
                    AxisMarks(position: .leading, values: [0, top]) { v in
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
                    AxisMarks(values: .automatic(desiredCount: 4)) { v in
                        AxisValueLabel {
                            if let s = v.as(String.self) {
                                Text(s).font(.system(size: 8, design: .monospaced)).foregroundStyle(p.faint)
                            }
                        }
                    }
                }
                .chartPlotStyle { $0.background(Color.clear) }
                .transaction { $0.animation = nil }
                .frame(height: kChartH)
                .hoverCatcher { pt, proxy, geo in
                    guard ctx.hover else { return }
                    guard let pt, let s: String = plotValue(proxy, geo, pt, as: String.self) else { sel = nil; return }
                    sel = pts.first { $0.name == s }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Spend to date")
                .accessibilityValue("\(moneyCents(total)) so far, about \(moneyCents(projected)) at this rate")
            }
            statLine(sel.map { moneyCents($0.v) } ?? moneyCents(total),
                     sel.map { "· by \($0.name)" } ?? "· so far, last \(ctx.days)d", p)
        }
    }
}
