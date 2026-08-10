import Foundation
import Combine

/// One timestamped chart sample. `v` is raw (burn = tokens/min; usage = 0…1 fraction)
/// so the chart can plot it on a fixed wall-clock X axis and a fixed value Y axis.
struct TimedSample: Equatable { let t: Date; let v: Double }

/// Near-real-time token-consumption monitor.
///
/// Tails `~/.claude/projects/**/*.jsonl` every ~1.5s, reading only the bytes
/// APPENDED since the previous tick (never re-parsing history), and reports a
/// token *rate* (tokens/min over the last 60s) plus an `active` flag. This is
/// what makes the speedometer needle swing and the odometer roll when Claude is
/// actively working - a different signal from the cumulative % the API reports.
final class LiveActivity: ObservableObject {
    @Published private(set) var rate: Double = 0       // tokens in the last 60s
    @Published private(set) var active: Bool = false    // tokens landed in the last few seconds
    @Published private(set) var pulse: Int = 0          // bumps whenever new tokens arrive
    @Published private(set) var history: [Double] = []  // recent normalized rate samples (for the menu-bar spark, ~1.2s)
    /// Concurrent burn attribution: the chats/sessions that produced tokens in the last 60 s,
    /// as (display name, tokens), busiest first. Two or more = parallel sessions competing.
    @Published private(set) var activeStreams: [(name: String, project: String, tok: Int)] = []
    /// Demo mode: synthesizes organic burn activity so every live surface (flame, charts, tide,
    /// popover) can be seen in motion without spending real tokens. Never persisted to disk.
    @Published private(set) var demo = false

    // ── Time-stamped, wall-clock-windowed chart series (P0-A) ──
    // Burn = raw tokens/min, one sample per refresh, last 60 min.
    // Usage = session fraction 0…1, downsampled to ~1/60 s, last 6 h.
    // Both persist to disk so a relaunch keeps the curve instead of starting blank.
    @Published private(set) var burnSamples: [TimedSample] = []
    @Published private(set) var usageSamples: [TimedSample] = []   // session %
    @Published private(set) var weeklySamples: [TimedSample] = []  // weekly %, sampled alongside session

    /// Tokens/min that maps to a "pinned" needle / full burn scale. Heavy Opus
    /// streaming with cache reads runs ~10-40k tok/min; 60k = full dial.
    static let RATE_FULL: Double = 60_000
    static let HISTORY_LEN = 28
    static let burnWindow: TimeInterval = 35 * 24 * 60 * 60  // retain 35 d of burn so the 1w/1mo/All windows have data (thinned for old points)
    static let usageWindow: TimeInterval = 35 * 24 * 60 * 60 // retain 35 days of usage (so "1 month" / "All time" have data)
    static let usageMinSpacing: TimeInterval = 58            // downsample usage to ~1/60 s
    private static let burnCap = 8000                        // hard cap on burn point count (safety)

    /// 0…1 needle position.
    var norm: Double { min(1.0, rate / Self.RATE_FULL) }

    /// Append the current burn rate as one chart point - called once per refresh, so the
    /// Burn curve advances on every refresh (and on manual LIVE taps). Raw tokens/min.
    func recordBurn(at now: Date = Date()) {
        burnSamples.append(TimedSample(t: now, v: max(0, rate)))
        if burnSamples.count > Self.burnCap { burnSamples.removeFirst(burnSamples.count - Self.burnCap) }
        trimAndPersist(now)
    }

    /// Append the current session + weekly % as Usage points, downsampled to ~1/60 s regardless
    /// of the (possibly 2 s) refresh cadence - driven by a separate coarse timer in the app.
    func recordUsage(session: Double, weekly: Double, at now: Date = Date()) {
        guard now.timeIntervalSince(lastUsageAt) >= Self.usageMinSpacing else { return }
        lastUsageAt = now
        usageSamples.append(TimedSample(t: now, v: min(1, max(0, session))))
        weeklySamples.append(TimedSample(t: now, v: min(1, max(0, weekly))))
        trimAndPersist(now)
    }

    private func trim(_ now: Date) {
        let bCut = now.addingTimeInterval(-Self.burnWindow)
        let uCut = now.addingTimeInterval(-Self.usageWindow)
        if let i = burnSamples.firstIndex(where: { $0.t >= bCut }), i > 0 { burnSamples.removeFirst(i) }
        else if burnSamples.last.map({ $0.t < bCut }) == true { burnSamples.removeAll() }
        func trimWin(_ arr: inout [TimedSample]) {
            if let i = arr.firstIndex(where: { $0.t >= uCut }), i > 0 { arr.removeFirst(i) }
            else if arr.last.map({ $0.t < uCut }) == true { arr.removeAll() }
        }
        trimWin(&usageSamples); trimWin(&weeklySamples)
        // Thin the older tail so a week/month of history stays cheap to store and draw, while
        // recent detail is kept intact. Burn keeps 2 h dense; usage keeps 24 h dense.
        burnSamples = decimate(burnSamples, now: now, tiers: [(7200, 60), (86400, 600), (604_800, 3600)])
        usageSamples = decimate(usageSamples, now: now, tiers: [(86400, 600), (604_800, 3600)])
        weeklySamples = decimate(weeklySamples, now: now, tiers: [(86400, 600), (604_800, 3600)])
    }

    // Keep at most one sample per `spacing` once a point is older than the tier threshold
    // (tiers sorted ascending; the largest matching spacing wins). The newest sample is always kept.
    private func decimate(_ arr: [TimedSample], now: Date, tiers: [(TimeInterval, TimeInterval)]) -> [TimedSample] {
        guard arr.count > 8 else { return arr }
        func minGap(_ age: TimeInterval) -> TimeInterval {
            var g: TimeInterval = 0
            for (olderThan, spacing) in tiers where age >= olderThan { g = spacing }
            return g
        }
        // Each retention window keeps its LARGEST sample, not its first.
        //
        // These are burn rates, and the charts that draw them bucket with pickMax precisely so a
        // spike survives being squeezed into a few hundred pixels. Thinning that kept whichever
        // sample happened to come first threw those spikes away before the chart ever saw them, so
        // yesterday's worst minute quietly flattened into whatever was happening around it. The
        // newest sample is still always kept, and recent samples (gap 0) are all kept.
        var out: [TimedSample] = []; out.reserveCapacity(arr.count)
        let lastT = arr.last?.t
        var pending: TimedSample?          // the biggest sample seen in the window being filled
        var windowStart: Date?
        for s in arr {
            let gap = minGap(now.timeIntervalSince(s.t))
            if gap <= 0 || s.t == lastT {
                if let p = pending { out.append(p); pending = nil; windowStart = nil }
                out.append(s)
                continue
            }
            if let ws = windowStart, s.t.timeIntervalSince(ws) < gap {
                if s.v > (pending?.v ?? -.infinity) { pending = s }
            } else {
                if let p = pending { out.append(p) }
                pending = s; windowStart = s.t
            }
        }
        if let p = pending { out.append(p) }
        return out
    }

    /// Write the full retained history to a timestamped CSV in ~/Downloads and return the URL.
    /// One tidy long-format file: series, ISO-8601 timestamp, value (burn = tokens/min; the two
    /// usage series = 0…1 fraction). Returns nil only if the write fails.
    func exportCSV() -> URL? {
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime]
        var rows = ["series,timestamp,value"]
        func add(_ name: String, _ arr: [TimedSample]) {
            for s in arr { rows.append("\(name),\(iso.string(from: s.t)),\(s.v)") }
        }
        add("burn_tokens_per_min", burnSamples)
        add("session_pct", usageSamples)
        add("weekly_pct", weeklySamples)
        let df = DateFormatter(); df.dateFormat = "yyyyMMdd-HHmmss"
        let name = "burndown-history-\(df.string(from: Date())).csv"
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads/\(name)")
        do { try rows.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8); return url }
        catch { return nil }
    }

    /// Clear all retained chart history (in memory and on disk). The live tailer keeps running,
    /// so fresh points start accumulating again immediately.
    func resetHistory() {
        burnSamples = []; usageSamples = []; weeklySamples = []; history = []
        lastUsageAt = .distantPast
        let url = storeURL
        q.async { try? FileManager.default.removeItem(at: url) }
    }

    private func trimAndPersist(_ now: Date) {
        trim(now)
        // Demo points live in memory only; setDemo(false) reloads the real persisted series.
        if !demo, now.timeIntervalSince(lastPersist) > 8 { lastPersist = now; persist() }
    }

    // ── Disk persistence (compact [epoch, value] pairs) ──
    private func persist() {
        let b = burnSamples, u = usageSamples, w = weeklySamples, url = storeURL
        q.async {
            let obj: [String: Any] = ["burn":   b.map { [$0.t.timeIntervalSince1970, $0.v] },
                                      "usage":  u.map { [$0.t.timeIntervalSince1970, $0.v] },
                                      "weekly": w.map { [$0.t.timeIntervalSince1970, $0.v] }]
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let d = try? JSONSerialization.data(withJSONObject: obj) {
                writePrivate(d, to: url)
            }
        }
    }

    private func load() {
        guard let d = try? Data(contentsOf: storeURL),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return }
        func arr(_ key: String) -> [TimedSample] {
            guard let raw = o[key] as? [[Double]] else { return [] }
            return raw.compactMap { $0.count == 2 ? TimedSample(t: Date(timeIntervalSince1970: $0[0]), v: $0[1]) : nil }
        }
        burnSamples = arr("burn"); usageSamples = arr("usage"); weeklySamples = arr("weekly")
        lastUsageAt = usageSamples.last?.t ?? .distantPast
        trim(Date())
    }

    private let projectsDir: URL
    private let storeURL: URL
    private var lastUsageAt: Date = .distantPast
    private var lastPersist: Date = .distantPast
    private let q = DispatchQueue(label: "com.maz.burndown.liveactivity")
    private var offsets: [String: UInt64] = [:]   // path → bytes already consumed
    private var events: [(ts: Date, tok: Int, path: String)] = []
    private var cwdByPath: [String: String] = [:]    // session file → its real cwd (for stream names)

    /// Forget files that no longer exist.
    ///
    /// Both maps above are keyed by path and were only ever added to, so every log the tail ever
    /// touched kept an entry for the life of the process, including ones deleted weeks ago. Small
    /// per entry and unbounded in aggregate, which is the shape of a leak rather than of a cache.
    private func pruneVanishedFiles(_ live: Set<String>) {
        guard offsets.count > live.count || cwdByPath.count > live.count
              || titleByPath.count > live.count || titleScanned.count > live.count else { return }
        offsets = offsets.filter { live.contains($0.key) }
        cwdByPath = cwdByPath.filter { live.contains($0.key) }
        titleByPath = titleByPath.filter { live.contains($0.key) }
        titleScanned = titleScanned.filter { live.contains($0) }
    }
    private var titleByPath: [String: String] = [:]  // session file → chat title (customTitle/aiTitle)
    private var customTitled: Set<String> = []       // paths with a user-set customTitle (authoritative)
    private var titleScanned: Set<String> = []       // paths whose head was already scanned for a title
    private var timer: Timer?
    private let iso: ISO8601DateFormatter
    private let isoNoFrac: ISO8601DateFormatter

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        projectsDir = home.appendingPathComponent(".claude/projects")
        storeURL = home.appendingPathComponent(".config/burndown/chart-history.json")
        iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        isoNoFrac = ISO8601DateFormatter(); isoNoFrac.formatOptions = [.withInternetDateTime]
        load()   // restore the persisted hour/6-hour curves
    }

    // QA only - seed the published state so the popover harness can render a chart.
    // Uses realistic sub-gap spacing (burn ~1/min, usage ~1/100s) so the preview shows a
    // continuous curve, matching how the live samplers actually feed the series.
    func seedForPreview(history: [Double], rate: Double, active: Bool) {
        self.history = history; self.rate = rate; self.active = active
        // Exercise the parallel-sessions rows with distinct chat titles (full-name presentation QA).
        activeStreams = [("Rebuild the marketing site", "Fine Print Doctor", 9_400),
                         ("Debug the sync worker", "Burndown", 3_200)]
        let now = Date()
        let src = history.isEmpty ? [0.0] : history
        func lerp(_ f: Double) -> Double {       // sample the pattern at 0…1
            let idx = f * Double(src.count - 1)
            let lo = Int(idx), hi = min(src.count - 1, lo + 1)
            return src[lo] + (src[hi] - src[lo]) * (idx - Double(lo))
        }
        // Burn: 50 points across the last 50 min (~1/min), scaled to raw tok/min.
        let bn = 50
        burnSamples = (0..<bn).map { i in
            TimedSample(t: now.addingTimeInterval(-Double(bn - 1 - i) * 60), v: lerp(Double(i) / Double(bn - 1)) * Self.RATE_FULL) }
        // Usage: 180 points across the last 5 h (~1/100s) - session ramp 0.18 → 0.46, weekly 0.30 → 0.43.
        let un = 180
        usageSamples = (0..<un).map { i in
            TimedSample(t: now.addingTimeInterval(-Double(un - 1 - i) * 100), v: 0.18 + Double(i) / Double(un - 1) * 0.28) }
        weeklySamples = (0..<un).map { i in
            TimedSample(t: now.addingTimeInterval(-Double(un - 1 - i) * 100), v: 0.06 + Double(i) / Double(un - 1) * 0.07) }
    }

    // ── Demo mode ──
    private var demoTimer: Timer?
    private var lastDemoBurn: Date = .distantPast

    func setDemo(_ on: Bool) {
        demo = on
        demoTimer?.invalidate(); demoTimer = nil
        if on {
            let t = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in self?.demoTick() }
            RunLoop.main.add(t, forMode: .common); demoTimer = t
            demoTick()
        } else {
            // Restore the real world: drop synthetic chart points by reloading the persisted
            // series (demo never persists), and let the real tailer repopulate rate/active.
            load()
            rate = 0; active = false; activeStreams = []
        }
    }

    // Organic synthetic burn: a slow swell + fast jitter + occasional spikes, so the flame
    // dances, the needle swings, the charts draw, and the tide warms - all with zero real usage.
    private func demoTick() {
        let t = Date().timeIntervalSinceReferenceDate
        let swell = (sin(t * 0.30) + 1) / 2                       // 0…1 slow wave (~21 s)
        let jitter = (sin(t * 2.3) + sin(t * 3.9)) * 0.07
        let spike = sin(t * 0.11) > 0.92 ? 0.38 : 0
        let n = min(1, max(0.05, swell * 0.55 + jitter + spike))
        rate = n * Self.RATE_FULL
        active = true
        var hist = history
        hist.append(n)
        if hist.count > Self.HISTORY_LEN { hist.removeFirst(hist.count - Self.HISTORY_LEN) }
        history = hist
        pulse += 1
        activeStreams = [("Rebuild the marketing site", "Fine Print Doctor", Int(rate * 0.6)),
                         ("Debug the sync worker", "Burndown", Int(rate * 0.3)),
                         ("Draft the launch email", "Home folder", Int(rate * 0.1))]
        // Feed the burn chart a point every ~4 s (in memory only; persistence is demo-gated).
        if Date().timeIntervalSince(lastDemoBurn) > 4 { lastDemoBurn = Date(); recordBurn() }
    }

    // Tailing 600+ session files means each scan stats the whole tree, so a fixed fast cadence
    // pegs a core for nothing when idle. Instead: baseline once, then self-reschedule - stay
    // responsive (2s) while tokens are flowing, back off (5s) when quiet. Burn is still caught
    // within one idle tick, and idle CPU drops ~4x versus the old fixed 1.2s.
    static let scanActive: TimeInterval = 2.0
    static let scanIdle: TimeInterval = 8.0
    // Byte needles: we scan the appended bytes for these before ever bridging a line to a Swift
    // String, so a 500KB tool-output line that carries neither is skipped for the cost of a memchr.
    private static let usageNeedle = Data("\"usage\"".utf8)
    private static let titleNeedle = Data("Title\"".utf8)   // matches customTitle"/aiTitle"

    func start() {
        stop()
        q.async { [weak self] in self?.scan(prime: true) }   // baseline offsets; don't count history
        scheduleScan(after: Self.scanActive)
    }

    private func scheduleScan(after delay: TimeInterval) {
        timer?.invalidate()
        let t = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.q.async { self.scan(prime: false) }
            self.scheduleScan(after: self.active ? Self.scanActive : Self.scanIdle)
        }
        RunLoop.main.add(t, forMode: .common); timer = t
    }

    func stop() { timer?.invalidate(); timer = nil }

    // Runs on `q` (serial) - `offsets`/`events` are only ever touched here.
    private func scan(prime: Bool) {
        let fm = FileManager.default
        let now = Date()
        let cutoff = now.addingTimeInterval(-180)   // ignore files untouched in the last 3 min
        var newTokens = 0
        guard let walker = fm.enumerator(at: projectsDir,
                                         includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                                         options: [.skipsHiddenFiles]) else { return }
        var seenPaths = Set<String>()
        for case let url as URL in walker {
            guard url.pathExtension == "jsonl" else { continue }
            seenPaths.insert(url.path)
            let vals = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let known = offsets[url.path] != nil
            if let mod = vals?.contentModificationDate, mod < cutoff, known { continue }
            let size = UInt64(vals?.fileSize ?? 0)
            guard let off = offsets[url.path] else { offsets[url.path] = size; continue }  // first sight → baseline
            guard size > off else { if size < off { offsets[url.path] = size }; continue }
            guard let h = try? FileHandle(forReadingFrom: url) else { offsets[url.path] = size; continue }
            try? h.seek(toOffset: off)
            let data = h.readDataToEndOfFile(); try? h.close()
            offsets[url.path] = size
            guard !prime else { continue }
            // Chat title: if this file never showed us a title (it usually appears near the start,
            // before we began tailing), scan its head once.
            if titleByPath[url.path] == nil, !titleScanned.contains(url.path) {
                titleScanned.insert(url.path)
                if let h2 = try? FileHandle(forReadingFrom: url) {
                    let head = h2.readData(ofLength: 96_000); try? h2.close()
                    if let headText = String(data: head, encoding: .utf8) { harvestTitles(from: headText, path: url.path) }
                }
            }
            // Process the appended bytes WITHOUT bridging the whole (possibly huge) delta to a Swift
            // String. Split on raw newlines and only decode the lines that actually carry a usage
            // record or a title - a session log can have 500KB+ lines (big tool outputs) that match
            // neither, and walking those as a bridged String was the entire scan cost.
            for lineData in data.split(separator: 0x0A, omittingEmptySubsequences: true) {
                let hasUsage = lineData.range(of: Self.usageNeedle) != nil
                let hasTitle = !hasUsage && lineData.range(of: Self.titleNeedle) != nil
                guard hasUsage || hasTitle, let line = String(data: lineData, encoding: .utf8) else { continue }
                if hasTitle { harvestTitles(from: line, path: url.path) }
                guard hasUsage,
                      let d = line.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                      let msg = obj["message"] as? [String: Any],
                      let usage = msg["usage"] as? [String: Any] else { continue }
                // Remember this session's real cwd → proper, full stream names.
                if let cwd = obj["cwd"] as? String, !cwd.isEmpty { self.cwdByPath[url.path] = cwd }
                let ts = (obj["timestamp"] as? String).flatMap { fastISO8601Date($0) ?? self.iso.date(from: $0) ?? self.isoNoFrac.date(from: $0) } ?? now
                let cc = usage["cache_creation"] as? [String: Any]
                let totalCreate = (usage["cache_creation_input_tokens"] as? Int) ?? 0
                let tok = ((usage["input_tokens"] as? Int) ?? 0)
                        + ((usage["output_tokens"] as? Int) ?? 0)
                        + ((cc?["ephemeral_5m_input_tokens"] as? Int) ?? (cc == nil ? totalCreate : 0))
                        + ((cc?["ephemeral_1h_input_tokens"] as? Int) ?? 0)
                if tok > 0 { self.events.append((ts, tok, url.path)); newTokens += tok }
            }
        }
        pruneVanishedFiles(seenPaths)
        events.removeAll { $0.ts < now.addingTimeInterval(-120) }
        let recent60 = now.addingTimeInterval(-60)
        let sum60 = events.reduce(0) { $0 + ($1.ts >= recent60 ? $1.tok : 0) }
        let isActive = events.contains { $0.ts >= now.addingTimeInterval(-6) }
        let bump = newTokens > 0
        let r = Double(sum60)
        // Per-stream attribution: which session files produced the last minute's tokens.
        var byPath: [String: Int] = [:]
        for e in events where e.ts >= recent60 { byPath[e.path, default: 0] += e.tok }
        let streams = byPath.sorted { $0.value > $1.value }.prefix(3)
            .map { let n = streamName($0.key); return (name: n.name, project: n.project, tok: $0.value) }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard !self.demo else { return }   // demo owns the published state while it runs
            self.rate = r
            self.active = isActive
            self.activeStreams = streams
            var hist = self.history
            hist.append(min(1.0, r / Self.RATE_FULL))
            if hist.count > Self.HISTORY_LEN { hist.removeFirst(hist.count - Self.HISTORY_LEN) }
            self.history = hist
            if bump { self.pulse += 1 }
        }
    }

    /// Pull the chat title out of raw log text. A user-set `customTitle` is authoritative and
    /// wins forever; otherwise the latest `aiTitle` is kept (titles can be refined over time).
    private func harvestTitles(from text: String, path: String) {
        guard text.contains("\"customTitle\"") || text.contains("\"aiTitle\"") else { return }
        text.enumerateLines { line, _ in
            guard line.contains("\"customTitle\"") || line.contains("\"aiTitle\"") else { return }
            guard let d = line.data(using: .utf8),
                  let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return }
            if let t = o["customTitle"] as? String, !t.isEmpty {
                self.titleByPath[path] = t; self.customTitled.insert(path)
            } else if let t = o["aiTitle"] as? String, !t.isEmpty, !self.customTitled.contains(path) {
                self.titleByPath[path] = t
            }
        }
    }

    /// FULL, human-readable label for one burning chat. Prefers the chat's real TITLE
    /// (so three chats in the same project stay distinguishable), then the project name,
    /// then the encoded folder - never a chopped fragment, never three identical rows.
    /// The conversation's name and the project it runs in.
    ///
    /// This used to fall back to "project + the last four characters of the session id", which is
    /// how "Home folder \u{00B7} 735f" ended up where a chat name belongs. The shared title index
    /// knows the real name, and reads it from the file itself when it does not.
    private func streamName(_ path: String) -> (name: String, project: String) {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let project = cwdByPath[path].map { cleanProjectName(cwd: $0, home: home) } ?? ""
        if let t = titleByPath[path] { return (t, project) }
        let sid = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        let title = UsageEngine.resolvedTitle(sid: sid, url: URL(fileURLWithPath: path))
        return (title, project)
    }
}
