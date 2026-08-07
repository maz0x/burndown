import Foundation

// Foundation-pure export and audit trail: turns raw UsageRecords into
// CSV, JSON, or a per-day Markdown table. Kept AppKit / Combine / SwiftUI free so the headless harness
// (run-export-tests.sh) can compile it against the real Aggregation and Pricing tables with no UI.
// Deterministic: same records in, same string out (stable column / key order, day rollups sorted).

/// ISO8601 timestamp (e.g. "2026-06-28T12:00:00Z") used in the CSV and JSON rows. A single shared
/// formatter so every row formats identically and we do not pay setup cost per record.
private let iso8601: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    f.timeZone = TimeZone(secondsFromGMT: 0)
    return f
}()

/// Round a USD amount to 4 decimal places (the export precision), avoiding scientific notation.
private func usd4(_ v: Double) -> String {
    String(format: "%.4f", v)
}

/// Strip characters that would break a bare (unquoted) CSV field: commas, quotes, and newlines all
/// become spaces. Project rule is to avoid commas inside fields rather than quote them.
private func csvSafe(_ s: String) -> String {
    var out = s
    for bad in [",", "\"", "\n", "\r"] { out = out.replacingOccurrences(of: bad, with: " ") }
    return out
}

/// JSON-escape a string for embedding in a double-quoted JSON value (no Foundation JSON encoder, so the
/// key order stays stable and the output is byte-for-byte deterministic).
private func jsonSafe(_ s: String) -> String {
    var out = ""
    for ch in s.unicodeScalars {
        switch ch {
        case "\"": out += "\\\""
        case "\\": out += "\\\\"
        case "\n": out += "\\n"
        case "\r": out += "\\r"
        case "\t": out += "\\t"
        default:
            if ch.value < 0x20 { out += String(format: "\\u%04x", ch.value) }
            else { out.unicodeScalars.append(ch) }
        }
    }
    return out
}

/// The shared column / field order, exposed so callers and tests agree on the schema.
let exportFields = ["date", "model", "project", "input", "output",
                    "cache5m", "cache1h", "cacheRead", "tokens", "costUSD"]

/// CSV of one row per record. Header line is exportFields joined by commas; date is ISO8601, costUSD is
/// rounded to 4 decimals, and free-text fields (model, project) are stripped of commas. Empty input
/// yields a header-only CSV (one line, no trailing newline beyond the rows).
func exportCSV(_ records: [UsageRecord]) -> String {
    var lines = [exportFields.joined(separator: ",")]
    for r in records {
        lines.append([
            iso8601.string(from: r.date),
            csvSafe(r.model),
            csvSafe(r.project),
            String(r.input),
            String(r.output),
            String(r.cache5m),
            String(r.cache1h),
            String(r.cacheRead),
            String(r.totalTokens),
            usd4(r.cost),
        ].joined(separator: ","))
    }
    return lines.joined(separator: "\n")
}

/// Pretty JSON array of objects, one object per record, with the stable exportFields key order. Numbers
/// stay numeric (no quotes); costUSD is a 4-decimal number. Empty input yields the array "[]".
func exportJSON(_ records: [UsageRecord]) -> String {
    if records.isEmpty { return "[]" }
    var objs: [String] = []
    for r in records {
        let lines = [
            "    \"date\": \"\(jsonSafe(iso8601.string(from: r.date)))\"",
            "    \"model\": \"\(jsonSafe(r.model))\"",
            "    \"project\": \"\(jsonSafe(r.project))\"",
            "    \"input\": \(r.input)",
            "    \"output\": \(r.output)",
            "    \"cache5m\": \(r.cache5m)",
            "    \"cache1h\": \(r.cache1h)",
            "    \"cacheRead\": \(r.cacheRead)",
            "    \"tokens\": \(r.totalTokens)",
            "    \"costUSD\": \(usd4(r.cost))",
        ]
        objs.append("  {\n" + lines.joined(separator: ",\n") + "\n  }")
    }
    return "[\n" + objs.joined(separator: ",\n") + "\n]"
}

/// Markdown table of per-day rollups (Day, Records, Tokens, Cost USD) built on rollupByDay, so days are
/// in chronological order. Empty input still yields the header row and separator (no data rows).
func exportMarkdownByDay(_ records: [UsageRecord], calendar: Calendar = .current) -> String {
    var lines = ["| Day | Records | Tokens | Cost USD |",
                 "| --- | --- | --- | --- |"]
    for day in rollupByDay(records, calendar: calendar) {
        lines.append("| \(day.key) | \(day.records) | \(day.tokens) | \(usd4(day.cost)) |")
    }
    return lines.joined(separator: "\n")
}

// MARK: - The report

/// A readable report, not a data dump.
///
/// The Markdown export used to be a four-column per-day table and nothing else: no totals, no
/// models, no projects, no chats, nothing that says what period it covers or what the numbers
/// mean. Everything the Insights window shows on screen is derived from these same records, so
/// there was no reason for the file to say less than the window does.
///
/// Pure and deterministic: same records in, same bytes out, so it can be tested and diffed.
func exportReportMarkdown(records: [UsageRecord], sessions: [SessionUsage], scopeLabel: String,
                          generated: Date, calendar: Calendar = .current) -> String {
    let agg = totals(records)
    let days = rollupByDay(records, calendar: calendar)
    let activeDays = days.filter { $0.tokens > 0 }
    let busiest = days.max { $0.tokens < $1.tokens }
    let stamp = DateFormatter()
    stamp.dateFormat = "yyyy-MM-dd HH:mm"
    stamp.calendar = calendar

    var out: [String] = []
    out.append("# Burndown usage report")
    out.append("")
    out.append("**Period:** \(scopeLabel)  ")
    out.append("**Generated:** \(stamp.string(from: generated))")
    out.append("")

    out.append("## Summary")
    out.append("")
    out.append("| | |")
    out.append("| --- | --- |")
    out.append("| Tokens | \(fmtTok(agg.tokens)) (\(agg.tokens)) |")
    out.append("| Estimated cost | \(moneyTable(agg.cost)) |")
    out.append("| Usage records | \(records.count) |")
    out.append("| Conversations | \(sessions.count) |")
    out.append("| Days with usage | \(activeDays.count) of \(days.count) |")
    if let b = busiest, b.tokens > 0 {
        out.append("| Busiest day | \(b.key), \(fmtTok(b.tokens)) |")
    }
    if activeDays.count > 0 {
        let avg = agg.tokens / activeDays.count
        out.append("| Average active day | \(fmtTok(avg)) |")
    }
    out.append("")

    // --- by model
    let byModel = rollupByModelFamily(records).sorted { $0.tokens > $1.tokens }
    if !byModel.isEmpty {
        out.append("## By model")
        out.append("")
        out.append("| Model | Tokens | Share | Estimated cost |")
        out.append("| --- | ---: | ---: | ---: |")
        for m in byModel {
            let share = agg.tokens > 0 ? Double(m.tokens) / Double(agg.tokens) * 100 : 0
            out.append("| \(m.key) | \(fmtTok(m.tokens)) | \(String(format: "%.1f", share))% | \(moneyTable(m.cost)) |")
        }
        out.append("")
    }

    // --- by project, from the sessions (they carry the resolved cwd)
    var byProject: [String: (tokens: Int, cost: Double, chats: Int)] = [:]
    for s in sessions {
        var e = byProject[s.project] ?? (0, 0, 0)
        e.tokens += s.tokens; e.cost += s.cost; e.chats += 1
        byProject[s.project] = e
    }
    if !byProject.isEmpty {
        out.append("## By project")
        out.append("")
        out.append("| Project | Conversations | Tokens | Estimated cost |")
        out.append("| --- | ---: | ---: | ---: |")
        for (name, v) in byProject.sorted(by: { $0.value.tokens > $1.value.tokens }) {
            out.append("| \(mdSafe(name)) | \(v.chats) | \(fmtTok(v.tokens)) | \(moneyTable(v.cost)) |")
        }
        out.append("")
        // The home bucket swallows every session started outside a project folder, so the report
        // breaks it out rather than leaving the reader with one enormous unexplained row.
        let homeChats = sessions.filter { $0.project == kHomeProject }
            .sorted { $0.tokens > $1.tokens }.prefix(10)
        if homeChats.count > 1 {
            out.append("### Inside \(kHomeProject)")
            out.append("")
            out.append("Sessions started from your home directory rather than a project folder.")
            out.append("")
            out.append("| Conversation | Tokens | Estimated cost |")
            out.append("| --- | ---: | ---: |")
            for s in homeChats {
                out.append("| \(mdSafe(s.title)) | \(fmtTok(s.tokens)) | \(moneyTable(s.cost)) |")
            }
            out.append("")
        }
    }

    // --- top conversations
    let top = sessions.sorted { $0.tokens > $1.tokens }.prefix(10)
    if !top.isEmpty {
        out.append("## Biggest conversations")
        out.append("")
        out.append("| Conversation | Project | Last active | Tokens | Estimated cost |")
        out.append("| --- | --- | --- | ---: | ---: |")
        let d = DateFormatter(); d.dateFormat = "yyyy-MM-dd"; d.calendar = calendar
        for s in top {
            out.append("| \(mdSafe(s.title)) | \(mdSafe(s.project)) | \(d.string(from: s.date)) "
                       + "| \(fmtTok(s.tokens)) | \(moneyTable(s.cost)) |")
        }
        out.append("")
    }

    // --- per day
    if !days.isEmpty {
        out.append("## Day by day")
        out.append("")
        out.append("| Day | Records | Tokens | Estimated cost |")
        out.append("| --- | ---: | ---: | ---: |")
        for day in days {
            out.append("| \(day.key) | \(day.records) | \(fmtTok(day.tokens)) | \(moneyTable(day.cost)) |")
        }
        out.append("")
    }

    out.append("---")
    out.append("")
    out.append("Token counts are exact, read from the local `~/.claude` logs on this Mac. "
               + "Dollar figures are an estimate of what the same tokens would cost at "
               + "pay-as-you-go API prices; on a subscription you do not pay them. "
               + "Nothing here was uploaded anywhere to produce this file.")
    return out.joined(separator: "\n")
}

/// Keep a title from breaking the table it sits in.
private func mdSafe(_ s: String) -> String {
    s.replacingOccurrences(of: "|", with: "\\|")
     .replacingOccurrences(of: "\n", with: " ")
}
