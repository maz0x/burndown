import Foundation

// Foundation-pure export and audit trail (FEATURE_IDEAS.md feature #8): turns raw UsageRecords into
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
