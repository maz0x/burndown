import Foundation

// Headless tests for the Foundation-pure export helpers (Sources/Export.swift). Compiles against the
// real Aggregation and Pricing sources, so the cost numbers below are the actual rate-table results.
// Same check()/failures/exit(1) pattern as Tests/chartdata/main.swift.

var failures = 0
func check(_ cond: Bool, _ msg: String) {
    print(cond ? "  ok   \(msg)" : "  FAIL \(msg)")
    if !cond { failures += 1 }
}

// A fixed UTC instant so ISO8601 output is deterministic regardless of the test machine's time zone.
// 1_750_000_000 = 2025-06-15T15:06:40Z.
let base = Date(timeIntervalSince1970: 1_750_000_000)
func day(_ offsetDays: Int) -> Date { base.addingTimeInterval(Double(offsetDays) * 86_400) }

func rec(_ date: Date, model: String, project: String,
         input: Int = 0, output: Int = 0,
         cache5m: Int = 0, cache1h: Int = 0, cacheRead: Int = 0) -> UsageRecord {
    UsageRecord(date: date, model: model, project: project,
                input: input, output: output, cache5m: cache5m, cache1h: cache1h, cacheRead: cacheRead)
}

// A UTC calendar so dayKey grouping in the Markdown test is stable everywhere.
var utc = Calendar(identifier: .gregorian)
utc.timeZone = TimeZone(secondsFromGMT: 0)!

print("exportCSV:")
// 1,000,000 opus-4-8 input tokens = $5.00 at the real rate table (Pricing.swift). Exact pricing anchor.
let opusRec = rec(base, model: "opus-4-8", project: "burndown", input: 1_000_000)
let csv = exportCSV([opusRec])
let csvLines = csv.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
check(csvLines.count == 2, "one header + one data row")
check(csvLines[0] == "date,model,project,input,output,cache5m,cache1h,cacheRead,tokens,costUSD",
      "header is the schema fields")
check(csvLines[1].hasPrefix("2025-06-15T15:06:40Z,opus-4-8,burndown,1000000,0,0,0,0,1000000,"),
      "row has ISO8601 date, fields, and token total")
check(csvLines[1].hasSuffix(",5.0000"),
      "1,000,000 opus-4-8 input tokens = $5.00 (4 decimals)")

// Boundary: a model/project containing a comma must not break the column layout.
let dirty = rec(base, model: "opus,4-8", project: "a,b", input: 0)
let dirtyRow = exportCSV([dirty]).split(separator: "\n").map(String.init)[1]
check(dirtyRow.split(separator: ",", omittingEmptySubsequences: false).count == exportFields.count,
      "commas inside fields are stripped so column count stays \(exportFields.count)")

print("exportJSON:")
// Empty input boundary.
check(exportJSON([]) == "[]", "empty input -> []")
let json = exportJSON([opusRec])
check(json.hasPrefix("[\n") && json.hasSuffix("\n]"), "pretty array brackets on their own lines")
check(json.contains("\"model\": \"opus-4-8\""), "model key/value present")
check(json.contains("\"input\": 1000000"), "numeric input is unquoted")
check(json.contains("\"costUSD\": 5.0000"), "costUSD is a 4-decimal number")
check(json.contains("\"date\": \"2025-06-15T15:06:40Z\""), "ISO8601 date string")
// Valid JSON: round-trips through JSONSerialization into one object with the 10 fields.
let parsed = try? JSONSerialization.jsonObject(with: Data(json.utf8))
check(parsed != nil, "output is valid JSON")
if let arr = parsed as? [[String: Any]] {
    check(arr.count == 1 && arr[0].count == exportFields.count,
          "one object with \(exportFields.count) keys")
} else {
    check(false, "parses to an array of objects")
}
// Key order is stable: date appears before costUSD in the emitted text.
check(json.range(of: "\"date\"")!.lowerBound < json.range(of: "\"costUSD\"")!.lowerBound,
      "stable key order (date before costUSD)")

print("exportMarkdownByDay:")
// Empty input still yields the header + separator rows only.
let mdEmpty = exportMarkdownByDay([], calendar: utc)
let mdEmptyLines = mdEmpty.split(separator: "\n").map(String.init)
check(mdEmptyLines.count == 2, "empty input -> header + separator only")
check(mdEmptyLines[0] == "| Day | Records | Tokens | Cost USD |", "Markdown header row present")

// Two days, two records each, out of order on input -> chronological day rows.
let multi = [
    rec(day(1), model: "sonnet-4-5", project: "x", input: 1_000_000),  // $3.00
    rec(day(0), model: "opus-4-8",   project: "x", input: 1_000_000),  // $5.00
    rec(day(0), model: "haiku-4-5",  project: "y", output: 1_000_000), // $5.00
    rec(day(1), model: "sonnet-4-5", project: "y", output: 2_000_000), // $30.00
]
let md = exportMarkdownByDay(multi, calendar: utc)
let mdLines = md.split(separator: "\n").map(String.init)
check(mdLines.count == 4, "header + separator + 2 day rows")
check(mdLines[2].hasPrefix("| 2025-06-15 |") && mdLines[3].hasPrefix("| 2025-06-16 |"),
      "day rows are in chronological order")
check(mdLines[2] == "| 2025-06-15 | 2 | 2000000 | 10.0000 |",
      "day 0: 2 records, 2M tokens, $10.00 (opus $5 + haiku $5)")
check(mdLines[3] == "| 2025-06-16 | 2 | 3000000 | 33.0000 |",
      "day 1: 2 records, 3M tokens, $33.00 (sonnet $3 + $30)")

// --- the report ---
// The old Markdown export was a four-column per-day table and nothing else, which is what made it
// useless: no totals, no models, no projects, no chats, and no statement of what period it covers.
let repRecs = [
    UsageRecord(date: base, model: "claude-opus-5", project: "Home folder",
                session: "Redesign the settings", input: 1000, output: 500, cache5m: 0, cache1h: 0, cacheRead: 0),
    UsageRecord(date: base.addingTimeInterval(86_400), model: "claude-fable-5", project: "site",
                session: "Rebuild the site", input: 200, output: 100, cache5m: 0, cache1h: 0, cacheRead: 0),
]
let repSessions = [
    SessionUsage(id: "/a.jsonl", title: "Redesign the settings", project: "Home folder",
                 date: base, tokens: 1500, cost: 12.5),
    SessionUsage(id: "/b.jsonl", title: "Rebuild the site", project: "site",
                 date: base.addingTimeInterval(86_400), tokens: 300, cost: 1.25),
]
let report = exportReportMarkdown(records: repRecs, sessions: repSessions, scopeLabel: "7 days",
                                  generated: base.addingTimeInterval(2 * 86_400), calendar: utc)
for section in ["# Burndown usage report", "## Summary", "## By model", "## By project",
                "## Biggest conversations", "## Day by day"] {
    check(report.contains(section), "the report has a \(section) section")
}
check(report.contains("**Period:** 7 days"), "it says what period it covers")
check(report.contains("Redesign the settings"), "conversations are named")
check(report.contains("site"), "projects are named")
check(report.contains("Dollar figures are an estimate"), "and it explains what the money means")
check(!report.contains("| 0 | 0 |"), "no empty filler rows")
// Deterministic: the same input twice must produce the same bytes, or a diff is meaningless.
let again = exportReportMarkdown(records: repRecs, sessions: repSessions, scopeLabel: "7 days",
                                 generated: base.addingTimeInterval(2 * 86_400), calendar: utc)
check(report == again, "the same input produces the same bytes")
// A title containing a pipe must not break the table it sits in.
let piped = [SessionUsage(id: "/c.jsonl", title: "a | b", project: "p",
                          date: base.addingTimeInterval(86_400), tokens: 5, cost: 0.1)]
let escaped = exportReportMarkdown(records: repRecs, sessions: piped, scopeLabel: "7 days",
                                   generated: base.addingTimeInterval(2 * 86_400), calendar: utc)
check(escaped.contains("a \\| b"), "a pipe in a title is escaped, not left to break the table")
// Nothing to report is still a valid document rather than a crash or a blank file.
let empty = exportReportMarkdown(records: [], sessions: [], scopeLabel: "Today",
                                 generated: base.addingTimeInterval(2 * 86_400), calendar: utc)
check(empty.contains("# Burndown usage report") && empty.contains("**Period:** Today"),
      "an empty period still produces a real report")

print(failures == 0 ? "\nALL EXPORT TESTS PASSED" : "\n\(failures) FAILURE(S)")
exit(failures == 0 ? 0 : 1)
