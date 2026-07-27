import SwiftUI
import AppKit

// The Insights window. It surfaces the analytics that build on the usage-aggregation layer
// (see FEATURE_IDEAS.md): live session attribution (#1), per-project usage (#2), a spend
// budget (#3), weekly pacing (#5), history and trends (#6), model-mix advice (#7), export
// (#8), and the weekly recap (#9). It is read-only on the engine; the only writes are the
// user-triggered file exports. Kept in a separate window so the tuned popover stays untouched.
// The shared card token for Insights sections (spec 5.1/5.3): track 45% fill, divider 0.5 stroke, r12,
// 16pt internal padding, no shadow.
struct InsightsCard: ViewModifier {
    let p: Palette
    func body(content: Content) -> some View {
        content.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(p.track.opacity(0.45))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(p.divider, lineWidth: 0.5)))
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

    private var now: Date { Date() }
    private var records: [UsageRecord] { engine.records }
    private var weekRecs: [UsageRecord] {
        recordsInWindow(records, since: now.addingTimeInterval(-7 * 86_400), until: now.addingTimeInterval(1))
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
        .onAppear { if scanned { return }
                    engine.scanAllUsage { recs, sess in allRecords = recs; allSessions = sess; scanned = true } }
    }

    @ViewBuilder private func loadingOverlay(_ p: Palette) -> some View {
        if !scanned { loadingCard(p) }
    }

    private func stack(_ p: Palette) -> some View {
            VStack(alignment: .leading, spacing: 22) {
                // Hero band FLATTENED (spec 5.3): the shared card token, a STATIC FlameMark, no
                // gradient wash and no idle motion - the earned-by-data law applies here too.
                HStack(spacing: 12) {
                    FlameMark(size: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Insights").font(.system(size: 22, weight: .semibold, design: .serif)).foregroundStyle(p.ink)
                        Text("Where your Claude usage goes").font(.system(size: 11)).foregroundStyle(p.sub)
                    }
                    Spacer()
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(p.track.opacity(0.45))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(p.divider, lineWidth: 0.5))
                )
                // Every section wraps in the shared card token (spec 5.3).
                recapCard.modifier(InsightsCard(p: p))
                advisories
                attribution.modifier(InsightsCard(p: p))
                chats.modifier(InsightsCard(p: p))
                projects.modifier(InsightsCard(p: p))
                history.modifier(InsightsCard(p: p))
                budgetControls
                exportRow
                Text("Token counts are exact, read from your local ~/.claude logs. On a subscription you do not pay these dollar figures: cost is an estimate of what the same usage would cost on Anthropic's pay-as-you-go API at current list prices.")
                    .font(.caption2).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func loadingCard(_ p: Palette) -> some View {
                ZStack {
                    p.bg.opacity(0.6).ignoresSafeArea()
                    VStack(spacing: 12) {
                        LivingFlameMark(size: 36)   // the one loading exception where the mark may breathe (spec 5.3)
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

    // MARK: This week recap (#9)
    private var recapCard: some View {
        let r = recap(weekRecs, label: "This week")
        return VStack(alignment: .leading, spacing: 6) {
            sectionTitle("This week")
            Text(recapText(r)).font(.callout).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 18) {
                stat(fmtTok(r.totalTokens), "tokens")
                stat(String(format: "$%.2f", r.costUSD), "est. cost")
                stat("\(r.dayCount)", "active days")
            }
        }
    }

    // MARK: Advisory lines (#5 pacing, #7 model-mix, #3 budget)
    private var advisories: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let p = pacingLine { advisoryRow("clock", p) }
            if let m = modelMixLine { advisoryRow("arrow.triangle.swap", m) }
            if let b = budgetLine { advisoryRow("dollarsign.circle", b) }
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

    // MARK: Current session attribution (#1)
    private var attribution: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Current session")
            if blockRecs.isEmpty {
                Text("No active 5-hour block right now.").font(.callout).foregroundStyle(.secondary)
            } else {
                Text("By model").font(.caption).foregroundStyle(.secondary)
                rollupBars(rollupByModelFamily(blockRecs))
            }
        }
    }

    // MARK: Per-project, all time (#2). Grouped by the REAL cwd of each session (Home, a repo name, ...),
    // not the log folder, so it is not mangled.
    private var projects: some View {
        var by: [String: (tokens: Int, cost: Double)] = [:]
        for s in allSessions { var e = by[s.project] ?? (0, 0); e.tokens += s.tokens; e.cost += s.cost; by[s.project] = e }
        let rows = by.map { (key: $0.key, tokens: $0.value.tokens, cost: $0.value.cost) }.sorted { $0.tokens > $1.tokens }
        let maxT = max(1, rows.map { $0.tokens }.max() ?? 1)
        let totalTok = rows.reduce(0) { $0 + $1.tokens }
        let totalCost = rows.reduce(0.0) { $0 + $1.cost }
        return VStack(alignment: .leading, spacing: 8) {
            sectionTitle("By project (all time)")
            if !scanned { Text("Reading your full history\u{2026}").font(.callout).foregroundStyle(.secondary) }
            else if rows.isEmpty { Text("No usage found in your local logs.").font(.callout).foregroundStyle(.secondary) }
            else {
                ForEach(Array(rows.prefix(10).enumerated()), id: \.offset) { _, r in
                    HStack(spacing: 8) {
                        Text(r.key).font(.system(size: 12)).frame(width: 110, alignment: .leading).lineLimit(1).truncationMode(.tail)
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.secondary.opacity(0.15))
                                Capsule().fill(Palette.of(scheme).session.opacity(0.85))
                                    .frame(width: max(2, g.size.width * CGFloat(Double(r.tokens) / Double(maxT))))
                            }
                        }.frame(height: 10)
                        Text(fmtTok(r.tokens)).font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 46, alignment: .trailing)
                        Text(usd(r.cost)).font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 52, alignment: .trailing)
                    }
                }
                Text("Lifetime: \(fmtTok(totalTok)) tokens, about \(usd(totalCost)) est. API cost. Most sessions run from your home folder (grouped as Home); the chats below split that out by conversation.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).padding(.top, 2)
            }
        }
    }
    private func usd(_ v: Double) -> String { v >= 100 ? String(format: "$%.0f", v) : String(format: "$%.2f", v) }

    // MARK: Biggest chats, all time. Each chat is one conversation, labeled by its own title.
    private var chats: some View {
        let rows = allSessions.sorted { $0.tokens > $1.tokens }.prefix(12)
        let maxT = max(1, rows.map { $0.tokens }.max() ?? 1)
        return VStack(alignment: .leading, spacing: 9) {
            sectionTitle("Biggest chats (all time)")
            if !scanned { Text("Reading your full history\u{2026}").font(.callout).foregroundStyle(.secondary) }
            else if rows.isEmpty { Text("No chats found in your local logs.").font(.callout).foregroundStyle(.secondary) }
            else {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(chatNames.display(r.title)).font(.system(size: 12.5, weight: .medium)).lineLimit(1).truncationMode(.tail)
                        HStack(spacing: 8) {
                            Text("\(r.project) · \(shortDate(r.date))").font(.system(size: 10.5)).foregroundStyle(.tertiary)
                                .frame(width: 116, alignment: .leading).lineLimit(1).truncationMode(.tail)
                            GeometryReader { g in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.secondary.opacity(0.15))
                                    Capsule().fill(Palette.of(scheme).session.opacity(0.85))
                                        .frame(width: max(2, g.size.width * CGFloat(Double(r.tokens) / Double(maxT))))
                                }
                            }.frame(height: 8)
                            Text(fmtTok(r.tokens)).font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 46, alignment: .trailing)
                            Text(usd(r.cost)).font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 52, alignment: .trailing)
                        }
                    }
                }
                Text("Each chat is one conversation, labeled by its own title (the title Claude shows for it).")
                    .font(.caption2).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    private func shortDate(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "MMM d"; f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: d)
    }

    // MARK: History (#6)
    private var history: some View {
        let days = rollupByDay(recordsInWindow(records, since: now.addingTimeInterval(-14 * 86_400),
                                               until: now.addingTimeInterval(1)))
        let maxT = max(1, days.map { $0.tokens }.max() ?? 1)
        return VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Last 14 days")
            if days.isEmpty { Text("No history yet.").font(.callout).foregroundStyle(.secondary) }
            else {
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(Array(days.enumerated()), id: \.offset) { _, d in
                        VStack(spacing: 3) {
                            RoundedRectangle(cornerRadius: 2).fill(Palette.of(scheme).session.opacity(0.7))
                                .frame(height: max(2, 80 * CGFloat(Double(d.tokens) / Double(maxT))))
                            Text(String(d.key.suffix(2))).font(.system(size: 9)).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity)
                    }
                }.frame(height: 100)
            }
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

    // MARK: Budget controls (#3)
    private var budgetControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Budget")
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
                    TextField("limit", value: $settings.budgetLimit, format: .number)
                        .frame(width: 90).textFieldStyle(.roundedBorder)
                    Text(settings.budgetMetric == "usd" ? "USD" : "tokens").foregroundStyle(.secondary)
                }
                toggleRow("Alert when approaching the budget", $settings.alertBudget)
            }
            toggleRow("Alert on runaway burn", $settings.alertRunaway)
                .help("Warns when the burn rate suddenly runs far above your own recent normal, which usually means a loop or a runaway agent. The threshold adapts to how you actually work.")
        }
    }

    // MARK: Export (#8)
    private var exportRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Export")
            HStack(spacing: 10) {
                Button("CSV") { saveExport(exportCSV(records), "burndown-usage.csv") }
                Button("JSON") { saveExport(exportJSON(records), "burndown-usage.json") }
                Button("Markdown") { saveExport(exportMarkdownByDay(records), "burndown-usage.md") }
            }
            Text("Saved to your Downloads folder.").font(.caption2).foregroundStyle(.tertiary)
        }
    }
    private func saveExport(_ text: String, _ name: String) {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads/\(name)")
        try? text.data(using: .utf8)?.write(to: url)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: Shared bits
    private func rollupBars(_ rollups: [UsageRollup], label: @escaping (String) -> String = { $0 }) -> some View {
        let maxT = max(1, rollups.map { $0.tokens }.max() ?? 1)
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(rollups.prefix(8).enumerated()), id: \.offset) { _, r in
                HStack(spacing: 8) {
                    Text(label(r.key)).font(.system(size: 12)).frame(width: 130, alignment: .leading)
                        .lineLimit(1).truncationMode(.middle)
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.secondary.opacity(0.15))
                            Capsule().fill(Palette.of(scheme).session.opacity(0.85))
                                .frame(width: max(2, g.size.width * CGFloat(Double(r.tokens) / Double(maxT))))
                        }
                    }.frame(height: 10)
                    Text(fmtTok(r.tokens)).font(.system(size: 11)).foregroundStyle(.secondary)
                        .frame(width: 54, alignment: .trailing)
                }
            }
        }
    }
    private func sectionTitle(_ t: String) -> some View {
        // The one eyebrow token (spec 2.3): SF 11pt semibold, +1.4 tracking, sub, uppercase.
        Text(t.uppercased()).font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.of(scheme).sub).tracking(1.4)
    }
    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.system(size: 16, weight: .semibold))
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
    private func advisoryRow(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 16)
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
        }
    }
    // Turn a ~/.claude/projects encoded folder name into a shorter readable path.
    private func prettyProjectName(_ key: String) -> String {
        if key.isEmpty { return "(unknown)" }
        if key == "(unknown)" { return key }
        var s = key
        if s.hasPrefix("-") { s.removeFirst() }
        let parts = s.split(separator: "-").map(String.init)
        if parts.count > 3, parts.first == "Users" { return parts.dropFirst(2).joined(separator: "/") }
        return parts.joined(separator: "/")
    }
}
