import SwiftUI
import AppKit
import Charts

// The Insights window: the Analytical Studio. It surfaces the analytics that build on the
// usage-aggregation layer underneath: live session attribution (#1), per-project usage (#2), a
// spend budget (#3), weekly pacing (#5), history and trends (#6), model-mix advice (#7), export
// (#8), and the recap (#9). A time-scope filter (Today · 7 days · 30 days · All time) re-indexes
// the recap, the attribution lists, and the exports; the 14-day rhythm chart deliberately stays
// fixed (a scoped "Today" would degenerate to a single bar). It is read-only on the engine; the
// only writes are the user-chosen file exports. Kept in a separate window so the tuned popover
// stays untouched.
// The shared card token for Insights sections: track 45% fill, divider 0.5 stroke, r12,
// 16pt internal padding, no shadow.
struct InsightsCard: ViewModifier {
    let p: Palette
    func body(content: Content) -> some View {
        content.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(p.track.opacity(0.45))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(p.divider, lineWidth: 0.5)))
    }
}

/// The recap stat trio plaque: eyebrow-style label under a serif stat numeral.
private struct StatPlaque: View {
    let value: String
    let label: String
    let p: Palette
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(.system(size: 18, weight: .semibold, design: .serif))
                .foregroundStyle(p.ink).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text(label.uppercased()).font(.system(size: 9.5, weight: .semibold)).tracking(1.1)
                .foregroundStyle(p.sub)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(p.raisedBg))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value)")
    }
}

struct InsightsView: View {
    @ObservedObject var engine: UsageEngine
    @ObservedObject var settings: AppSettings
    @State private var allRecords: [UsageRecord] = []   // full-history records for history + lifetime
    @State private var allSessions: [SessionUsage] = []  // per-conversation totals, labeled by title
    @State private var scanned = false
    /// True only under the offscreen marketing/QA renderer. ImageRenderer cannot draw native
    /// AppKit controls: a real Toggle comes out as a yellow placeholder blob. Insights is never
    /// captured from a real window (it would expose the signed-in email, projects and chat
    /// titles), so the preview path draws its own switch instead.
    private let isPreview: Bool

    init(engine: UsageEngine, settings: AppSettings,
         preview: (records: [UsageRecord], sessions: [SessionUsage])? = nil) {
        self.engine = engine
        self.settings = settings
        self.isPreview = preview != nil
        // Seeding the state up front is what makes an offscreen render (which never runs
        // onAppear, so the async scan never completes) show real content instead of the
        // loading card. Only the QA/marketing harness passes this.
        if let preview {
            _allRecords = State(initialValue: preview.records)
            _allSessions = State(initialValue: preview.sessions)
            _scanned = State(initialValue: true)
        }
    }
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var chatNames = ChatNames.shared

    // MARK: Time scope: re-indexes the recap, attribution lists, and exports.
    private enum Scope: Int, CaseIterable, Identifiable {
        case today, week, month, all
        var id: Int { rawValue }
        var label: String {
            switch self { case .today: return "Today"; case .week: return "7 days"
                          case .month: return "30 days"; case .all: return "All time" }
        }
        /// Suffix for section titles ("By project, 7 days").
        var suffix: String {
            switch self { case .today: return "today"; case .week: return "7 days"
                          case .month: return "30 days"; case .all: return "all time" }
        }
    }
    @State private var scope: Scope = .week
    @State private var histSel: UsageRollup? = nil       // hover selection on the rhythm chart
    @State private var exportToast: String? = nil        // save confirmation, self-dismissing

    private var now: Date { Date() }
    private var records: [UsageRecord] { engine.records }
    /// The scope's record slice. The full-history scan feeds everything once it lands; before
    /// that (and always for the engine-bounded windows) engine.records is the honest source.
    private var scopedRecs: [UsageRecord] {
        let source = scanned && !allRecords.isEmpty ? allRecords : records
        switch scope {
        case .today: return recordsInWindow(source, since: Calendar.current.startOfDay(for: now), until: now.addingTimeInterval(1))
        case .week:  return recordsInWindow(source, since: now.addingTimeInterval(-7 * 86_400), until: now.addingTimeInterval(1))
        case .month: return recordsInWindow(source, since: now.addingTimeInterval(-30 * 86_400), until: now.addingTimeInterval(1))
        case .all:   return source
        }
    }
    /// Per-conversation rows inside the scope (sessions carry their last-activity date).
    private var scopedSessions: [SessionUsage] {
        switch scope {
        case .today: return allSessions.filter { $0.date >= Calendar.current.startOfDay(for: now) }
        case .week:  return allSessions.filter { $0.date >= now.addingTimeInterval(-7 * 86_400) }
        case .month: return allSessions.filter { $0.date >= now.addingTimeInterval(-30 * 86_400) }
        case .all:   return allSessions
        }
    }
    private var blockRecs: [UsageRecord] {
        guard let start = engine.activeBlockStart else { return [] }
        return recordsInWindow(records, since: start, until: now.addingTimeInterval(1))
    }

    /// QA/marketing renders set CUB_NOSCROLL: ImageRenderer cannot render a ScrollView's
    /// contents (same limitation the Settings pane works around), so the window is drawn as a
    /// plain stack instead. Live app runs are always scrolled.
    private static let noScroll = ProcessInfo.processInfo.environment["CUB_NOSCROLL"] != nil

    var body: some View {
        let p = Palette.of(scheme)
        return Group {
            if Self.noScroll { stack(p) } else { ScrollView { stack(p) } }
        }
        .frame(minWidth: 380, idealWidth: 420, minHeight: 480)
        // Loading state: the full-history scan takes a few seconds; make that unmistakable
        // instead of showing partial numbers that read as final.
        .overlay { loadingOverlay(p) }
        .overlay(alignment: .bottom) { if let t = exportToast { toast(t, p) } }
        .onAppear { if scanned { return }
                    engine.scanAllUsage { recs, sess in allRecords = recs; allSessions = sess; scanned = true } }
    }

    @ViewBuilder private func loadingOverlay(_ p: Palette) -> some View {
        if !scanned { loadingCard(p) }
    }

    private func stack(_ p: Palette) -> some View {
            VStack(alignment: .leading, spacing: 22) {
                // Hero band FLATTENED: the shared card token, a STATIC FlameMark, no
                // gradient wash and no idle motion - the earned-by-data law applies here too.
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        FlameMark(size: 28)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Insights").font(.system(size: 22, weight: .semibold, design: .serif)).foregroundStyle(p.ink)
                            Text("Where your Claude usage goes").font(.system(size: 11)).foregroundStyle(p.sub)
                        }
                        Spacer()
                    }
                    scopePicker(p)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(p.track.opacity(0.45))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(p.divider, lineWidth: 0.5))
                )
                // Every section wraps in the shared card token.
                recapCard(p).modifier(InsightsCard(p: p))
                advisories(p)
                attribution(p).modifier(InsightsCard(p: p))
                if scanned && allSessions.isEmpty && records.isEmpty {
                    emptyState(p).modifier(InsightsCard(p: p))
                } else {
                    chats(p).modifier(InsightsCard(p: p))
                    projects(p).modifier(InsightsCard(p: p))
                }
                history(p).modifier(InsightsCard(p: p))
                budgetControls(p)
                exportRow(p)
                Text("Token counts are exact, read from your local ~/.claude logs. On a subscription you do not pay these dollar figures: cost is an estimate of what the same usage would cost on Anthropic's pay-as-you-go API at current list prices.")
                    .font(.caption2).foregroundStyle(p.faint).fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func loadingCard(_ p: Palette) -> some View {
                ZStack {
                    p.bg.opacity(0.6).ignoresSafeArea()
                    VStack(spacing: 12) {
                        LivingFlameMark(size: 36)   // the one loading exception where the mark may breathe
                        // Indeterminate session sweep over track, no spinner.
                        TimelineView(.animation(minimumInterval: 1.0 / 15.0)) { ctx in   // cap at 15fps
                            let t = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.44) / 1.44
                            Capsule().fill(p.track).frame(width: 120, height: 3)
                                .overlay(alignment: .leading) {
                                    Capsule().fill(p.session).frame(width: 40, height: 3)
                                        .offset(x: CGFloat(t) * 120 - 20)
                                        .mask(Capsule().frame(width: 120, height: 3))
                                }
                        }
                        Text("Reading your usage history").font(.system(size: 12, weight: .medium)).foregroundStyle(p.ink)
                        Text("Numbers appear when the full scan finishes.").font(.system(size: 10.5)).foregroundStyle(p.sub)
                    }
                    .padding(24).frame(width: 240)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(p.bg)
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(p.divider, lineWidth: 0.5)))
                    .shadow(color: .black.opacity(scheme == .dark ? 0.5 : 0.18), radius: 40, y: 12)
                }
    }

    /// Nothing scanned anywhere: an illustrated invitation instead of three bare "no data" lines.
    private func emptyState(_ p: Palette) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                FlameMark(size: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Nothing to analyze yet").font(.system(size: 13, weight: .semibold)).foregroundStyle(p.ink)
                    Text("Run a Claude Code session in a terminal (or just keep chatting) and your usage lands in ~/.claude automatically. This page fills itself.")
                        .font(.system(size: 11.5)).foregroundStyle(p.sub).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: Scoped recap: narrative + the stat plaque trio.
    private func recapCard(_ p: Palette) -> some View {
        let recs = scopedRecs
        let r = recap(recs, label: scope.label)
        let agg = totals(recs)
        let top = rollupByModelFamily(recs).max { $0.tokens < $1.tokens }?.key ?? "None"
        return VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Recap · \(scope.suffix)", p)
            Text(recapText(r)).font(.callout).foregroundStyle(p.ink).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                StatPlaque(value: fmtTok(agg.tokens), label: "Tokens burned", p: p)
                StatPlaque(value: String(format: "$%.2f", agg.cost), label: "Est. compute", p: p)
                StatPlaque(value: top, label: "Top model", p: p)
            }
        }
    }

    // MARK: Advisory lines (pacing, model-mix, budget)
    private func advisories(_ p: Palette) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let t = pacingLine { advisoryRow("clock", t, p) }
            if let m = modelMixLine { advisoryRow("arrow.triangle.swap", m, p) }
            if let b = budgetLine { advisoryRow("dollarsign.circle", b, p) }
        }
    }
    private var pacingLine: String? {
        let snap = engine.snapshot
        guard let reset = snap.weeklyResetAt else { return nil }
        let weekStart = reset.addingTimeInterval(-7 * 86_400)
        let hoursElapsed = max(0.5, now.timeIntervalSince(weekStart) / 3600)
        let ratePerHour = snap.weeklyPct / hoursElapsed
        let hoursUntilReset = max(0, reset.timeIntervalSince(now) / 3600)
        let sessionFraction = snap.weeklyCap > 0 ? Double(snap.sessionCap) / Double(snap.weeklyCap) : 0.1
        return weeklyPacing(fractionUsed: snap.weeklyPct, ratePerHour: ratePerHour,
                            hoursUntilReset: hoursUntilReset, sessionFraction: sessionFraction).summary
    }
    private var modelMixLine: String? {
        let snap = engine.snapshot
        let hr = [ModelHeadroom(family: "Opus", fractionUsed: snap.apiOpus?.pct ?? 0),
                  ModelHeadroom(family: "Sonnet", fractionUsed: snap.apiSonnet?.pct ?? 0)]
        let a = modelMixAdvice(hr)
        return a.shouldAdvise ? a.message : nil
    }
    private var budgetLine: String? {
        guard settings.budgetEnabled, settings.budgetLimit > 0 else { return nil }
        return budgetStatusNow().summary
    }
    private func budgetStatusNow() -> BudgetStatus {
        let metric: BudgetMetric = settings.budgetMetric == "tokens" ? .tokens : .usd
        let period: BudgetPeriod = settings.budgetPeriod == "day" ? .day : .week
        let start = period == .day ? Calendar.current.startOfDay(for: now) : now.addingTimeInterval(-7 * 86_400)
        let agg = totals(recordsInWindow(records, since: start, until: now.addingTimeInterval(1)))
        let spent = metric == .tokens ? Double(agg.tokens) : agg.cost
        let elapsed = period == .day ? min(1, max(0.0001, now.timeIntervalSince(start) / 86_400)) : 1.0
        return budgetStatus(spent: spent,
                            config: BudgetConfig(metric: metric, limit: settings.budgetLimit, period: period),
                            elapsedFraction: elapsed)
    }

    // MARK: Current session attribution
    private func attribution(_ p: Palette) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Current session", p)
            if blockRecs.isEmpty {
                Text("No active 5-hour block right now.").font(.callout).foregroundStyle(p.sub)
            } else {
                Text("By model").font(.caption).foregroundStyle(p.sub)
                rollupBars(rollupByModelFamily(blockRecs), p)
            }
        }
    }

    // MARK: Per-project inside the scope (#2). Grouped by the REAL cwd of each session (Home, a
    // repo name, ...), not the log folder, so it is not mangled.
    private func projects(_ p: Palette) -> some View {
        var by: [String: (tokens: Int, cost: Double)] = [:]
        for s in scopedSessions { var e = by[s.project] ?? (0, 0); e.tokens += s.tokens; e.cost += s.cost; by[s.project] = e }
        let rows = by.map { (key: $0.key, tokens: $0.value.tokens, cost: $0.value.cost) }.sorted { $0.tokens > $1.tokens }
        let maxT = max(1, rows.map { $0.tokens }.max() ?? 1)
        let totalTok = rows.reduce(0) { $0 + $1.tokens }
        let totalCost = rows.reduce(0.0) { $0 + $1.cost }
        return VStack(alignment: .leading, spacing: 8) {
            sectionTitle("By project · \(scope.suffix)", p)
            if !scanned { Text("Reading your full history\u{2026}").font(.callout).foregroundStyle(p.sub) }
            else if rows.isEmpty { Text("No usage in this window.").font(.callout).foregroundStyle(p.sub) }
            else {
                ForEach(Array(rows.prefix(10).enumerated()), id: \.offset) { _, r in
                    HStack(spacing: 8) {
                        Text(r.key).font(.system(size: 12)).foregroundStyle(p.ink)
                            .frame(width: 110, alignment: .leading).lineLimit(1).truncationMode(.tail)
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(p.track)
                                Capsule().fill(p.session.opacity(0.85))
                                    .frame(width: max(2, g.size.width * CGFloat(Double(r.tokens) / Double(maxT))))
                            }
                        }.frame(height: 10)
                        .accessibilityElement()
                        .accessibilityLabel("\(r.key): \(fmtTok(r.tokens)) tokens")
                        Text(fmtTok(r.tokens)).font(.system(size: 11)).foregroundStyle(p.sub).frame(width: 46, alignment: .trailing)
                        Text(usd(r.cost)).font(.system(size: 11)).foregroundStyle(p.sub).frame(width: 52, alignment: .trailing)
                    }
                }
                if scope == .all {
                    Text("Lifetime: \(fmtTok(totalTok)) tokens, about \(usd(totalCost)) est. API cost. Most sessions run from your home folder (grouped as Home); the chats above split that out by conversation.")
                        .font(.caption).foregroundStyle(p.sub).fixedSize(horizontal: false, vertical: true).padding(.top, 2)
                }
            }
        }
    }
    private func usd(_ v: Double) -> String { v >= 100 ? String(format: "$%.0f", v) : String(format: "$%.2f", v) }

    // MARK: Biggest chats inside the scope. Each chat is one conversation, labeled by its own title.
    private func chats(_ p: Palette) -> some View {
        let rows = scopedSessions.sorted { $0.tokens > $1.tokens }.prefix(12)
        let maxT = max(1, rows.map { $0.tokens }.max() ?? 1)
        return VStack(alignment: .leading, spacing: 9) {
            sectionTitle("Biggest chats · \(scope.suffix)", p)
            if !scanned { Text("Reading your full history\u{2026}").font(.callout).foregroundStyle(p.sub) }
            else if rows.isEmpty { Text("No chats in this window.").font(.callout).foregroundStyle(p.sub) }
            else {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(chatNames.display(r.title)).font(.system(size: 12.5, weight: .medium)).foregroundStyle(p.ink)
                            .lineLimit(1).truncationMode(.tail)
                        HStack(spacing: 8) {
                            Text("\(r.project) · \(shortDate(r.date))").font(.system(size: 10.5)).foregroundStyle(p.faint)
                                .frame(width: 116, alignment: .leading).lineLimit(1).truncationMode(.tail)
                            GeometryReader { g in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(p.track)
                                    Capsule().fill(p.session.opacity(0.85))
                                        .frame(width: max(2, g.size.width * CGFloat(Double(r.tokens) / Double(maxT))))
                                }
                            }.frame(height: 8)
                            Text(fmtTok(r.tokens)).font(.system(size: 11)).foregroundStyle(p.sub).frame(width: 46, alignment: .trailing)
                            Text(usd(r.cost)).font(.system(size: 11)).foregroundStyle(p.sub).frame(width: 52, alignment: .trailing)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(chatNames.display(r.title)): \(fmtTok(r.tokens)) tokens")
                }
                Text("Each chat is one conversation, labeled by its own title (the title Claude shows for it).")
                    .font(.caption2).foregroundStyle(p.faint).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    private func shortDate(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "MMM d"
        return f.string(from: d)
    }

    // MARK: History: the 14-day rhythm as a real chart with a hover scrubber. Deliberately NOT
    // scoped (a "Today" scope would collapse it to one bar); it answers "what is my rhythm",
    // the scope filter answers "where did it go".
    private func history(_ p: Palette) -> some View {
        let source = scanned && !allRecords.isEmpty ? allRecords : records
        let days = rollupByDay(recordsInWindow(source, since: now.addingTimeInterval(-14 * 86_400),
                                               until: now.addingTimeInterval(1)))
        let maxT = days.map { $0.tokens }.max() ?? 0
        let avgT = days.isEmpty ? 0 : days.reduce(0) { $0 + $1.tokens } / days.count
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionTitle("Last 14 days", p)
                Spacer()
                if let s = histSel {
                    Text("\(String(s.key.suffix(5))): \(fmtTok(s.tokens))")
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(p.session).monospacedDigit()
                }
            }
            if days.isEmpty { Text("No history yet.").font(.callout).foregroundStyle(p.sub) }
            else {
                Chart {
                    ForEach(days, id: \.key) { d in
                        BarMark(x: .value("day", String(d.key.suffix(5))), y: .value("tokens", d.tokens))
                            .foregroundStyle(p.session.opacity(histSel == nil || histSel?.key == d.key ? 0.8 : 0.35))
                            .cornerRadius(2)
                    }
                }
                .chartXAxis {
                    AxisMarks { v in
                        AxisValueLabel {
                            if let s = v.as(String.self) {
                                Text(String(s.suffix(2))).font(.system(size: 9)).foregroundStyle(p.sub)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { v in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 2])).foregroundStyle(p.divider)
                        AxisValueLabel {
                            if let i = v.as(Int.self) {
                                Text(fmtTok(i)).font(.system(size: 8.5, design: .monospaced)).foregroundStyle(p.sub)
                            }
                        }
                    }
                }
                .chartPlotStyle { $0.background(Color.clear) }
                .frame(height: 110)
                .hoverCatcher { pt, proxy, geo in
                    guard let pt, let key: String = proxy.value(atX: pt.x - geo[proxy.plotAreaFrame].minX)
                    else { histSel = nil; return }
                    histSel = days.first { String($0.key.suffix(5)) == key }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Fourteen day usage history")
                .accessibilityValue(days.map { "\(String($0.key.suffix(5))) \(fmtTok($0.tokens))" }.joined(separator: ", "))
                HStack(spacing: 4) {
                    Text("peak \(fmtTok(maxT))").font(.system(size: 11, weight: .semibold)).foregroundStyle(p.ink).monospacedDigit()
                    Text("· avg \(fmtTok(avgT)) per day").font(.system(size: 9.5)).foregroundStyle(p.faint)
                    Spacer()
                }
            }
        }
    }

    /// A real segmented Picker everywhere real, and a hand-drawn look-alike under the offscreen
    /// renderer (ImageRenderer paints native segmented controls as a yellow placeholder blob,
    /// the same limitation toggleRow works around).
    @ViewBuilder private func scopePicker(_ p: Palette) -> some View {
        if isPreview {
            HStack(spacing: 2) {
                ForEach(Scope.allCases) { s in
                    Text(s.label).font(.system(size: 11, weight: s == scope ? .semibold : .regular))
                        .foregroundStyle(s == scope ? p.ink : p.sub)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(s == scope ? p.bg : .clear))
                }
            }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(p.track))
        } else {
            Picker("Time scope", selection: $scope) {
                ForEach(Scope.allCases) { s in Text(s.label).tag(s) }
            }
            .pickerStyle(.segmented).labelsHidden()
            .accessibilityLabel("Time scope for the recap, attribution, and exports")
        }
    }

    /// A Toggle everywhere real, and a hand-drawn look-alike under the offscreen renderer.
    @ViewBuilder private func toggleRow(_ title: String, _ isOn: Binding<Bool>) -> some View {
        if isPreview {
            HStack(spacing: 8) {
                Capsule().fill(isOn.wrappedValue ? Color.accentColor : Color.gray.opacity(0.32))
                    .frame(width: 26, height: 15.5)
                    .overlay(alignment: isOn.wrappedValue ? .trailing : .leading) {
                        Circle().fill(.white).frame(width: 13, height: 13)
                            .shadow(color: .black.opacity(0.18), radius: 0.5, y: 0.5)
                            .padding(.horizontal, 1.25)
                    }
                Text(title)
            }
        } else {
            Toggle(title, isOn: isOn)
        }
    }

    // MARK: Budget controls
    private func budgetControls(_ p: Palette) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Budget", p)
            toggleRow("Track a spend budget", $settings.budgetEnabled)
            if settings.budgetEnabled {
                HStack(spacing: 10) {
                    Picker("", selection: $settings.budgetMetric) {
                        Text("Dollars").tag("usd"); Text("Tokens").tag("tokens")
                    }.pickerStyle(.segmented).labelsHidden().frame(width: 150)
                    Picker("", selection: $settings.budgetPeriod) {
                        Text("Per day").tag("day"); Text("Per week").tag("week")
                    }.pickerStyle(.segmented).labelsHidden().frame(width: 150)
                }
                HStack(spacing: 8) {
                    Text("Limit")
                    TextField("Amount", value: $settings.budgetLimit, format: .number)
                        .frame(width: 90).textFieldStyle(.roundedBorder)
                    Text(settings.budgetMetric == "usd" ? "USD" : "tokens").foregroundStyle(p.sub)
                }
                toggleRow("Alert when approaching the budget", $settings.alertBudget)
            }
            toggleRow("Alert on runaway burn", $settings.alertRunaway)
                .help("Warns when the burn rate suddenly runs far above your own recent normal, which usually means a loop or a runaway agent. The threshold adapts to how you actually work.")
        }
    }

    // MARK: Export: the scope's records, to a location the user chooses.
    private func exportRow(_ p: Palette) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Export · \(scope.suffix)", p)
            HStack(spacing: 10) {
                Button("CSV") { saveExport(exportCSV(scopedRecs), "burndown-usage.csv") }
                Button("JSON") { saveExport(exportJSON(scopedRecs), "burndown-usage.json") }
                Button("Markdown") { saveExport(exportMarkdownByDay(scopedRecs), "burndown-usage.md") }
            }
            Text("You choose where it goes.").font(.caption2).foregroundStyle(p.faint)
        }
    }
    /// Native save panel (the old path wrote straight into ~/Downloads, which fails silently
    /// when the folder is sandboxed or relocated); a toast confirms the write either way.
    private func saveExport(_ text: String, _ name: String) {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = name
        panel.begin { resp in
            guard resp == .OK, let url = panel.url else { return }
            do {
                try text.write(to: url, atomically: true, encoding: .utf8)
                showToast("Exported \(url.lastPathComponent)")
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
                showToast("Could not write the file: \(error.localizedDescription)")
            }
        }
    }
    private func showToast(_ msg: String) {
        withAnimation(.emberEase(Dur.d240)) { exportToast = msg }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation(.emberEase(Dur.d240)) { exportToast = nil }
        }
    }
    private func toast(_ msg: String, _ p: Palette) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(p.live)
            Text(msg).font(.system(size: 12, weight: .medium)).foregroundStyle(p.ink)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Capsule().fill(p.raisedBg).overlay(Capsule().stroke(p.divider, lineWidth: 1)))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        .padding(.bottom, 18)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    // MARK: Shared bits
    private func rollupBars(_ rollups: [UsageRollup], _ p: Palette, label: @escaping (String) -> String = { $0 }) -> some View {
        let maxT = max(1, rollups.map { $0.tokens }.max() ?? 1)
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(rollups.prefix(8).enumerated()), id: \.offset) { _, r in
                HStack(spacing: 8) {
                    Text(label(r.key)).font(.system(size: 12)).foregroundStyle(p.ink).frame(width: 130, alignment: .leading)
                        .lineLimit(1).truncationMode(.middle)
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(p.track)
                            Capsule().fill(p.session.opacity(0.85))
                                .frame(width: max(2, g.size.width * CGFloat(Double(r.tokens) / Double(maxT))))
                        }
                    }.frame(height: 10)
                    .accessibilityElement()
                    .accessibilityLabel("\(label(r.key)): \(fmtTok(r.tokens)) tokens")
                    Text(fmtTok(r.tokens)).font(.system(size: 11)).foregroundStyle(p.sub)
                        .frame(width: 54, alignment: .trailing)
                }
            }
        }
    }
    private func sectionTitle(_ t: String, _ p: Palette) -> some View {
        // The one eyebrow token: SF 11pt semibold, +1.4 tracking, sub, uppercase.
        Text(t.uppercased()).font(.system(size: 11, weight: .semibold)).foregroundStyle(p.sub).tracking(1.4)
    }
    private func advisoryRow(_ symbol: String, _ text: String, _ p: Palette) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol).foregroundStyle(p.sub).frame(width: 16)
            Text(text).font(.callout).foregroundStyle(p.ink).fixedSize(horizontal: false, vertical: true)
        }
    }
}
