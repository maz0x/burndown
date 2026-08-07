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
/// Type scale for the Insights window.
///
/// Every fixed size in this file goes through it, so A- / A+ moves the whole window together
/// instead of leaving half of it at the old size, and the column widths scale with the type or the
/// numbers outgrow the columns holding them.
///
/// A global rather than a view method because the small helper views in this file (the stat
/// plaques, the rows) are drawn outside the main view and would otherwise be the half left behind.
/// It is set once when the window draws and read everywhere.
private var gInsightsTextScale: CGFloat = 1
private func ts(_ v: CGFloat) -> CGFloat { v * gInsightsTextScale }

private struct StatPlaque: View {
    let value: String
    let label: String
    let p: Palette
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(.system(size: ts(18), weight: .semibold, design: .serif))
                .foregroundStyle(p.ink).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text(label.uppercased()).font(.system(size: ts(9.5), weight: .semibold)).tracking(1.1)
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
    /// Cached aggregations. Every table and chart here walked the whole record set inside body,
    /// and body re-runs on every hover, so moving the pointer across the 14-day bars re-filtered
    /// nearly a hundred thousand records per frame. That is the lag.
    @State private var memo = Memo()
    /// The Home folder row's disclosure state. Sessions started from the home directory all land
    /// in one row, so it opens into the conversations underneath.
    @State private var homeOpen = false
    @State private var exportToast: String? = nil        // save confirmation, self-dismissing

    /// A clock that moves once a minute.
    ///
    /// Everything here takes its window from "now", so with the real clock no two redraws agree
    /// and nothing can be cached. This window is not a live chart: a minute of staleness is
    /// invisible, and it turns a hover storm into one piece of work.
    private var now: Date { Date(timeIntervalSinceReferenceDate:
        (Date().timeIntervalSinceReferenceDate / 60).rounded(.down) * 60) }
    private var records: [UsageRecord] { engine.records }



    /// Everything the aggregations below depend on. Hovering a bar changes none of it.
    private var dataKey: String {
        "\(scope.rawValue)|\(scanned)|\(allRecords.count)|\(records.count)"
        + "|\(allSessions.count)|\(now.timeIntervalSinceReferenceDate)"
    }
    /// The scope's record slice. The full-history scan feeds everything once it lands; before
    /// that (and always for the engine-bounded windows) engine.records is the honest source.
    private var scopedRecs: [UsageRecord] {
        memo.value("scoped", dataKey) {
            let source = scanned && !allRecords.isEmpty ? allRecords : records
            switch scope {
            case .today: return recordsInWindow(source, since: Calendar.current.startOfDay(for: now), until: now.addingTimeInterval(1))
            case .week:  return recordsInWindow(source, since: now.addingTimeInterval(-7 * 86_400), until: now.addingTimeInterval(1))
            case .month: return recordsInWindow(source, since: now.addingTimeInterval(-30 * 86_400), until: now.addingTimeInterval(1))
            case .all:   return source
            }
        }
    }
    /// Per-conversation rows inside the scope (sessions carry their last-activity date).
    private var scopedSessions: [SessionUsage] {
        memo.value("scopedSessions", dataKey) {
        switch scope {
        case .today: return allSessions.filter { $0.date >= Calendar.current.startOfDay(for: now) }
        case .week:  return allSessions.filter { $0.date >= now.addingTimeInterval(-7 * 86_400) }
        case .month: return allSessions.filter { $0.date >= now.addingTimeInterval(-30 * 86_400) }
        case .all:   return allSessions
        }
        }
    }
    private var blockRecs: [UsageRecord] {
        guard let start = engine.activeBlockStart else { return [] }
        return memo.value("block", dataKey + "|\(start.timeIntervalSince1970)") {
            recordsInWindow(records, since: start, until: now.addingTimeInterval(1))
        }
    }

    /// QA/marketing renders set CUB_NOSCROLL: ImageRenderer cannot render a ScrollView's
    /// contents (same limitation the Settings pane works around), so the window is drawn as a
    /// plain stack instead. Live app runs are always scrolled.
    private static let noScroll = ProcessInfo.processInfo.environment["CUB_NOSCROLL"] != nil

    var body: some View {
        let p = Palette.of(scheme)
        gInsightsTextScale = CGFloat(max(0.85, min(1.4, settings.insightsTextScale)))
        return Group {
            if Self.noScroll { stack(p) } else { ScrollView { stack(p) } }
        }
        // One dial for the whole window's type. The numbers here are read, not glanced at, and
        // the defaults were sized for a 420pt column. The popover has its own zoom; these are
        // deliberately separate settings because they are two different reading distances.
        .frame(minWidth: 900, idealWidth: 1160, minHeight: 600)
        .overlay(alignment: .topTrailing) { textSizeControl(p) }
        // Loading state: the full-history scan takes a few seconds; make that unmistakable
        // instead of showing partial numbers that read as final.
        .overlay { loadingOverlay(p) }
        .overlay(alignment: .bottom) { if let t = exportToast { toast(t, p) } }
        .onAppear { if scanned { return }
                    engine.scanAllUsage { recs, sess in allRecords = recs; allSessions = sess; scanned = true } }
    }

    /// A- / A+ in the corner. Nothing else in the window competes for that spot, and a reader who
    /// needs bigger text should not have to find a Settings pane to get it.
    private func textSizeControl(_ p: Palette) -> some View {
        let sc = settings.insightsTextScale
        // focusable(false) on both buttons, or macOS parks the keyboard focus ring on the first one
        // the moment the window opens: a green box sitting in the corner that cannot be dismissed
        // and does not belong to anything the reader did. Each letter also gets a real square to
        // sit in, so the pair reads as one control rather than two loose letters in the corner.
        return HStack(spacing: 4) {
            sizeStep(9.5, enabled: sc > 0.851, hint: "Smaller text", p: p) {
                settings.insightsTextScale = max(0.85, (sc - 0.1).rounded(toPlaces: 2))
            }
            Text("\(Int((sc * 100).rounded()))%")
                .font(.system(size: 9.5, design: .monospaced)).foregroundStyle(p.sub)
                .frame(width: 30).monospacedDigit()
            sizeStep(13.5, enabled: sc < 1.399, hint: "Bigger text", p: p) {
                settings.insightsTextScale = min(1.4, (sc + 0.1).rounded(toPlaces: 2))
            }
        }
        .padding(.horizontal, 7).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(p.track.opacity(0.6)))
        .padding(16)
        .help("Text size in this window")
    }

    private func sizeStep(_ size: CGFloat, enabled: Bool, hint: String, p: Palette,
                          _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Text("A").font(.system(size: size, weight: .semibold))
                .frame(width: 20, height: 20)
                .foregroundStyle(enabled ? p.ink : p.faint)
                .background(RoundedRectangle(cornerRadius: 5).fill(p.bg))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(p.divider, lineWidth: 0.5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .disabled(!enabled)
        .accessibilityLabel(hint)
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
                            Text("Insights").font(.system(size: ts(22), weight: .semibold, design: .serif)).foregroundStyle(p.ink)
                            Text("Where your Claude usage goes").font(.system(size: ts(11))).foregroundStyle(p.sub)
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
                        Text("Reading your usage history").font(.system(size: ts(12), weight: .medium)).foregroundStyle(p.ink)
                        Text("Numbers appear when the full scan finishes.").font(.system(size: ts(10.5))).foregroundStyle(p.sub)
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
                    Text("Nothing to analyze yet").font(.system(size: ts(13), weight: .semibold)).foregroundStyle(p.ink)
                    Text("Run a Claude Code session in a terminal (or just keep chatting) and your usage lands in ~/.claude automatically. This page fills itself.")
                        .font(.system(size: ts(11.5))).foregroundStyle(p.sub).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: Scoped recap: narrative + the stat plaque trio.
    private func recapCard(_ p: Palette) -> some View {
        // Three full walks of the record set. Memoised together, because they change together.
        let (r, agg, top) = memo.value("recap", dataKey) { () -> (RecapSummary, UsageRollup, String) in
            let recs = scopedRecs
            return (recap(recs, label: scope.label), totals(recs),
                    rollupByModelFamily(recs).max { $0.tokens < $1.tokens }?.key ?? "None")
        }
        return VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Recap \u{00B7} \(scope.suffix)", p,
                         info: "A plain-English summary of the period selected above. Tokens are counted exactly from the logs Claude Code writes on this Mac. The cost is an estimate of what those same tokens would cost at pay-as-you-go API prices; on a subscription you do not pay it, so treat it as a measure of how much work you got, not a bill.")
            Text(recapText(r)).font(.callout).foregroundStyle(p.ink).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                StatPlaque(value: fmtTok(agg.tokens), label: "Tokens burned", p: p)
                StatPlaque(value: usd(agg.cost), label: "Est. compute", p: p)
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
            sectionTitle("Current session", p,
                         info: "The five-hour window Claude is measuring you against right now, broken down by model. It starts at your first message after a quiet spell and it is the limit you are most likely to hit in a working day.")
            if blockRecs.isEmpty {
                Text("No active 5-hour block right now.").font(.callout).foregroundStyle(p.sub)
            } else {
                Text("By model").font(.caption).foregroundStyle(p.sub)
                rollupBars(rollupByModelFamily(blockRecs), p)
            }
        }
    }

    // MARK: Per-project inside the scope (#2). Grouped by the REAL cwd of each session (a repo
    // name, or "Home folder" for anything started from the home directory), not the log folder.
    //
    // "Home folder" is honest but it answers nothing on its own: run Claude from your home
    // directory, as many people do all day, and every session lands in that one row while the
    // work you actually did disappears into it. So the row opens: click it and it splits into the
    // conversations underneath. And when it is the ONLY row, the project table is not a table at
    // all, so the section becomes "By chat" outright rather than showing a one-row bar chart that
    // says "100% of your work happened somewhere".
    private func projects(_ p: Palette) -> some View {
        let rows = memo.value("projects", dataKey) { () -> [(key: String, tokens: Int, cost: Double)] in
            var by: [String: (tokens: Int, cost: Double)] = [:]
            for s in scopedSessions { var e = by[s.project] ?? (0, 0); e.tokens += s.tokens; e.cost += s.cost; by[s.project] = e }
            return by.map { (key: $0.key, tokens: $0.value.tokens, cost: $0.value.cost) }.sorted { $0.tokens > $1.tokens }
        }
        let maxT = max(1, rows.map { $0.tokens }.max() ?? 1)
        let totalTok = rows.reduce(0) { $0 + $1.tokens }
        let totalCost = rows.reduce(0.0) { $0 + $1.cost }
        let onlyHome = rows.count == 1 && rows[0].key == kHomeProject
        return VStack(alignment: .leading, spacing: 8) {
            sectionTitle(onlyHome ? "By chat \u{00B7} \(scope.suffix)" : "By project \u{00B7} \(scope.suffix)", p,
                         info: onlyHome
                            ? "Everything in this period ran from your home folder rather than a project folder, so there is nothing to group by and it is listed by conversation instead."
                            : "Where your usage went, grouped by the folder each conversation was started in. \"\(kHomeProject)\" collects everything you ran from your home directory rather than inside a project; click that row to see the conversations inside it.")
            if !scanned { Text("Reading your full history\u{2026}").font(.callout).foregroundStyle(p.sub) }
            else if rows.isEmpty { Text("No usage in this window.").font(.callout).foregroundStyle(p.sub) }
            else if onlyHome {
                Text("Everything in this window ran from your home folder rather than a project folder, so it is listed by conversation.")
                    .font(.caption).foregroundStyle(p.sub).fixedSize(horizontal: false, vertical: true)
                chatRows(of: kHomeProject, p: p, indent: 0)
            } else {
                ForEach(Array(rows.prefix(10).enumerated()), id: \.offset) { _, r in
                    let expandable = r.key == kHomeProject
                    let open = expandable && homeOpen
                    VStack(alignment: .leading, spacing: 4) {
                        Button {
                            guard expandable else { return }
                            withAnimation(.easeInOut(duration: 0.16)) { homeOpen.toggle() }
                        } label: {
                            HStack(spacing: 8) {
                                HStack(spacing: 3) {
                                    if expandable {
                                        Image(systemName: open ? "chevron.down" : "chevron.right")
                                            .font(.system(size: ts(8), weight: .semibold)).foregroundStyle(p.faint)
                                    }
                                    Text(r.key).font(.system(size: ts(12))).foregroundStyle(p.ink)
                                        .lineLimit(1).truncationMode(.tail)
                                }
                                .frame(width: ts(110), alignment: .leading)
                                GeometryReader { g in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(p.track)
                                        Capsule().fill(p.session.opacity(0.85))
                                            .frame(width: max(2, g.size.width * CGFloat(Double(r.tokens) / Double(maxT))))
                                    }
                                }.frame(height: 10)
                                Text(fmtTok(r.tokens)).font(.system(size: ts(11), design: .monospaced))
                                    .foregroundStyle(p.sub).frame(width: ts(78), alignment: .trailing)
                                Text(usd(r.cost)).font(.system(size: ts(11), design: .monospaced))
                                    .foregroundStyle(p.sub).frame(width: ts(78), alignment: .trailing)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).focusable(false)
                        .accessibilityLabel("\(r.key): \(fmtTok(r.tokens)) tokens, \(usd(r.cost))"
                                            + (expandable ? ", click to list the conversations" : ""))
                        if open { chatRows(of: kHomeProject, p: p, indent: 14) }
                    }
                }
                if scope == .all {
                    Text("Lifetime: \(fmtTok(totalTok)) tokens, about \(usd(totalCost)) estimated API cost.")
                        .font(.caption).foregroundStyle(p.sub).fixedSize(horizontal: false, vertical: true).padding(.top, 2)
                }
            }
        }
    }

    /// The conversations inside one project, biggest first. Used both for the opened Home folder
    /// row and for the whole section when that row is all there is.
    @ViewBuilder private func chatRows(of project: String, p: Palette, indent: CGFloat) -> some View {
        let rows = memo.value("chatsOf" + project, dataKey) {
            Array(mergeSessions(scopedSessions.filter { $0.project == project })
                    .sorted { $0.tokens > $1.tokens }.prefix(10))
        }
        let maxT = max(1, rows.map(\.tokens).max() ?? 1)
        if rows.isEmpty {
            Text("No conversations in this window.").font(.caption).foregroundStyle(p.faint)
                .padding(.leading, indent)
        } else {
            ForEach(rows, id: \.id) { s in
                HStack(spacing: 8) {
                    Text(ChatNames.shared.display(s.title)).font(.system(size: ts(11.5))).foregroundStyle(p.ink)
                        .frame(width: 110 - indent, alignment: .leading).lineLimit(1).truncationMode(.middle)
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(p.track)
                            Capsule().fill(p.weekly.opacity(0.8))
                                .frame(width: max(2, g.size.width * CGFloat(Double(s.tokens) / Double(maxT))))
                        }
                    }.frame(height: 8)
                    Text(fmtTok(s.tokens)).font(.system(size: ts(11), design: .monospaced))
                        .foregroundStyle(p.sub).frame(width: ts(78), alignment: .trailing)
                    Text(usd(s.cost)).font(.system(size: ts(11), design: .monospaced))
                        .foregroundStyle(p.sub).frame(width: ts(78), alignment: .trailing)
                }
                .padding(.leading, indent)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(ChatNames.shared.display(s.title)): \(fmtTok(s.tokens)) tokens, \(usd(s.cost))")
            }
        }
    }

    /// One money format across the window, shared with the rest of the app (Format.swift).
    private func usd(_ v: Double) -> String { moneyTable(v) }

    // MARK: Biggest chats inside the scope. Each chat is one conversation, labeled by its own title.
    private func chats(_ p: Palette) -> some View {
        // Merged: Claude Code starts a new log when a conversation is resumed or compacted, so one
        // long piece of work showed up as four identical rows with four different numbers.
        let rows = memo.value("topChats", dataKey) {
            Array(mergeSessions(scopedSessions).sorted { $0.tokens > $1.tokens }.prefix(12))
        }
        let maxT = max(1, rows.map { $0.tokens }.max() ?? 1)
        return VStack(alignment: .leading, spacing: 9) {
            sectionTitle("Biggest chats \u{00B7} \(scope.suffix)", p,
                         info: "The individual conversations that used the most tokens in this period, with the project each one ran in and when it was last active. A long conversation costs more per message as it grows, because the whole thread is re-read each turn, so the biggest chats here are usually the longest rather than the busiest.")
            if !scanned { Text("Reading your full history\u{2026}").font(.callout).foregroundStyle(p.sub) }
            else if rows.isEmpty { Text("No chats in this window.").font(.callout).foregroundStyle(p.sub) }
            else {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(chatNames.display(r.title)).font(.system(size: ts(12.5), weight: .medium)).foregroundStyle(p.ink)
                            .lineLimit(1).truncationMode(.tail)
                        HStack(spacing: 8) {
                            Text("\(r.project) \u{00B7} \(shortDate(r.date))"
                                 + (r.parts > 1 ? " \u{00B7} \(r.parts) logs" : ""))
                                .font(.system(size: ts(10.5))).foregroundStyle(p.faint)
                                .frame(width: ts(168), alignment: .leading).lineLimit(1).truncationMode(.tail)
                            GeometryReader { g in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(p.track)
                                    Capsule().fill(p.session.opacity(0.85))
                                        .frame(width: max(2, g.size.width * CGFloat(Double(r.tokens) / Double(maxT))))
                                }
                            }.frame(height: 8)
                            Text(fmtTok(r.tokens)).font(.system(size: ts(11))).foregroundStyle(p.sub).frame(width: ts(46), alignment: .trailing)
                            Text(usd(r.cost)).font(.system(size: ts(11))).foregroundStyle(p.sub).frame(width: ts(52), alignment: .trailing)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(chatNames.display(r.title)): \(fmtTok(r.tokens)) tokens")
                }
                Text("Each row is one conversation, named by its own title. Claude Code starts a new log file when a chat is resumed or compacted, so a long conversation can span several; those are added together here and the count is shown.")
                    .font(.caption2).foregroundStyle(p.faint).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    /// "22" normally, "Aug 1" for the first bar and for the first day of any month after it.
    private func dayAxisLabel(_ key: String, first: String?) -> String {
        let parts = key.split(separator: "-")
        guard parts.count == 2, let m = Int(parts[0]), let d = Int(parts[1]) else { return key }
        let months = ["", "Jan", "Feb", "Mar", "Apr", "May", "Jun",
                      "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        let name = (m >= 1 && m <= 12) ? months[m] : ""
        if key == first || d == 1 { return "\(name) \(d)" }
        return String(d)
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
        // Quiet days included: a day with no usage is a zero bar, never a missing column.
        let days = memo.value("days14", dataKey) { rollupByDaysBack(source, days: 14, now: now) }
        let maxT = days.map { $0.tokens }.max() ?? 0
        let avgT = days.isEmpty ? 0 : days.reduce(0) { $0 + $1.tokens } / days.count
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionTitle("Last 14 days", p,
                         info: "Your daily rhythm over the last two weeks, whichever period is selected above. Days with no usage show as empty rather than being left out, so the shape of your week is honest. Hover a bar for that day's exact total.")
                Spacer()
                if let s = histSel {
                    Text("\(String(s.key.suffix(5))): \(fmtTok(s.tokens))")
                        .font(.system(size: ts(10.5), weight: .medium, design: .monospaced))
                        // The one place a hero hue was used for words. It is a readout, and the
                        // session colour is tuned to be SEEN as a bar, not READ as 10.5pt text,
                        // where it falls under 4.5:1 in eighteen of the themes.
                        .foregroundStyle(p.ink).monospacedDigit()
                }
            }
            if days.isEmpty { Text("No history yet.").font(.callout).foregroundStyle(p.sub) }
            else {
                Chart {
                    ForEach(days, id: \.key) { d in
                        BarMark(x: .value("day", String(d.key.suffix(5))), y: .value("tokens", d.tokens))
                            // The hovered bar gets darker. It used to fade every OTHER bar instead,
                            // so pointing at one changed thirteen and dimmed the whole chart.
                            .foregroundStyle(p.session.opacity(histSel?.key == d.key ? 1.0 : 0.8))
                            .cornerRadius(2)
                    }
                }
                .chartXAxis {
                    AxisMarks { v in
                        AxisValueLabel {
                            if let s = v.as(String.self) {
                                // A bare day number runs 30, 31, 01, 02 across a month boundary and
                                // reads as a chart that went backwards. The first bar and any bar
                                // that starts a new month carry the month with them.
                                Text(dayAxisLabel(s, first: days.first.map { String($0.key.suffix(5)) }))
                                    .font(.system(size: ts(9))).foregroundStyle(p.sub)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { v in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 2])).foregroundStyle(p.divider)
                        AxisValueLabel {
                            if let i = v.as(Int.self) {
                                Text(fmtTok(i)).font(.system(size: ts(8.5), design: .monospaced)).foregroundStyle(p.sub)
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
                    Text("peak \(fmtTok(maxT))").font(.system(size: ts(11), weight: .semibold)).foregroundStyle(p.ink).monospacedDigit()
                    Text("· avg \(fmtTok(avgT)) per day").font(.system(size: ts(9.5))).foregroundStyle(p.faint)
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

    /// A budget toggle with its own explanation, since none of these say what they do from the
    /// label alone, and a switch whose effect you cannot predict is a switch nobody touches.
    private func budgetRow(_ title: String, _ isOn: Binding<Bool>, _ p: Palette, _ info: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            toggleRow(title, isOn)
            InfoDot(text: info, p: p)
            Spacer(minLength: 0)
        }
    }

    // MARK: Budget controls
    private func budgetControls(_ p: Palette) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Budget", p,
                         info: "Optional warnings. A spend budget notifies you when the estimated cost for a period passes an amount you choose. Runaway burn watches for a sudden jump far above your own recent normal, which usually means a loop or an agent that got stuck. Both are local notifications; nothing is sent anywhere.")
            budgetRow("Track a spend budget", $settings.budgetEnabled, p,
                      "Warns you when the estimated cost of a day or a week passes a number you set. Useful as a sense of scale on a subscription, and as a real ceiling if you also use pay-as-you-go API keys.")
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
                budgetRow("Alert when approaching the budget", $settings.alertBudget, p,
                          "Notifies you as you approach the limit above, rather than only once you have passed it.")
            }
            budgetRow("Alert on runaway burn", $settings.alertRunaway, p,
                      "Watches for a burn rate far above your own recent normal, which usually means a loop or an agent that got stuck. The threshold adapts to how you actually work, so it does not fire simply because you had a busy afternoon.")
        }
    }

    // MARK: Export: the scope's data, to a location the user chooses.
    //
    // Each button said only what file type it wrote, so the only way to find out what was IN one
    // was to export it and open it. Now each says what it contains, and the scope is in the
    // filename so two exports of different periods cannot be confused on disk.
    private func exportRow(_ p: Palette) -> some View {
        let slug = scope.suffix.replacingOccurrences(of: " ", with: "")
        let stamp = DateFormatter(); stamp.dateFormat = "yyyy-MM-dd"
        let date = stamp.string(from: Date())
        return VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Export \u{00B7} \(scope.suffix)", p,
                         info: "Saves the period selected above to a file you choose. The report is written for reading; the spreadsheet and raw data are one row per usage record for your own analysis. Nothing is uploaded: the file is written straight to the folder you pick.")
            // Fixed columns with the slack at the END.
            HStack(alignment: .top, spacing: 20) {
                exportButton("Report", "Markdown. Everything on this page: totals, models, projects, biggest chats, day by day.", p) {
                    saveExport(exportReportMarkdown(records: scopedRecs, sessions: scopedSessions,
                                                    scopeLabel: scope.label, generated: Date()),
                               "burndown-report-\(slug)-\(date).md")
                }
                exportButton("Spreadsheet", "CSV. One row per usage record, for your own analysis.", p) {
                    saveExport(exportCSV(scopedRecs), "burndown-usage-\(slug)-\(date).csv")
                }
                exportButton("Raw data", "JSON. The same rows, machine readable.", p) {
                    saveExport(exportJSON(scopedRecs), "burndown-usage-\(slug)-\(date).json")
                }
                Spacer(minLength: 0)
            }
            Text("Nothing leaves this Mac: the file is written wherever you choose to save it.")
                .font(.system(size: ts(10))).foregroundStyle(p.faint)
        }
    }

    private func exportButton(_ title: String, _ what: String, _ p: Palette,
                              _ action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Button(title, action: action)
            Text(what).font(.system(size: ts(10))).foregroundStyle(p.faint)
                .fixedSize(horizontal: false, vertical: true)
        }
        // A fixed column, not a flexible one. Sharing the window's width meant the three buttons
        // drifted further apart every time the window was widened, until they were a metre apart
        // with their captions stretched between them.
        .frame(width: ts(240), alignment: .leading)
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
            Text(msg).font(.system(size: ts(12), weight: .medium)).foregroundStyle(p.ink)
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
                    Text(label(r.key)).font(.system(size: ts(12))).foregroundStyle(p.ink).frame(width: ts(130), alignment: .leading)
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
                    Text(fmtTok(r.tokens)).font(.system(size: ts(11))).foregroundStyle(p.sub)
                        .frame(width: ts(54), alignment: .trailing)
                }
            }
        }
    }
    /// A section heading, with the same info mark the popover and Settings use.
    ///
    /// Every section in this window shows a number derived from local logs in a way that is not
    /// obvious from the label alone: which window it covers, whether the dollars are real, why a
    /// project is called what it is. The card explains itself section by section; there was no
    /// reason this window did not.
    private func sectionTitle(_ t: String, _ p: Palette, info: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            // The one eyebrow token: SF 11pt semibold, +1.4 tracking, sub, uppercase.
            Text(t.uppercased()).font(.system(size: ts(11), weight: .semibold))
                .foregroundStyle(p.sub).tracking(1.4)
            if let info { InfoDot(text: info, p: p) }
        }
    }
    private func advisoryRow(_ symbol: String, _ text: String, _ p: Palette) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol).foregroundStyle(p.sub).frame(width: 16)
            Text(text).font(.callout).foregroundStyle(p.ink).fixedSize(horizontal: false, vertical: true)
        }
    }
}
