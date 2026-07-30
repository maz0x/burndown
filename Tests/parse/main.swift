import Foundation

// Golden-fixture tests for the REAL Foundation-pure parsers in Sources/Parsing.swift
// (compiled together by run-parse-tests.sh). No network, no token, no live API: hardcoded
// fixtures only. Reverting parseISO/clampPct in Parsing.swift must make these fail.

var failures = 0
func check(_ cond: Bool, _ msg: String) {
    if cond { print("  ok   \(msg)") } else { failures += 1; print("  FAIL \(msg)") }
}

print("parseISO:")
let base = parseISO("2026-06-26T12:00:00Z")
check(base != nil, "plain Z timestamp parses")
check(parseISO("2026-06-26T12:00:00.123456Z").map { abs($0.timeIntervalSince(base!)) < 0.001 } ?? false,
      "6-digit fractional seconds parse to the whole-second instant")
check(parseISO("2026-06-26T12:00:00+00:00").map { abs($0.timeIntervalSince(base!)) < 0.001 } ?? false,
      "+00:00 offset equals Z")
check(parseISO("2026-06-26T12:00:00-07:00").map { abs($0.timeIntervalSince(base!) - 7 * 3600) < 0.001 } ?? false,
      "-07:00 offset resolves 7h ahead in UTC")
check(parseISO("2026-06-26T12:00:00.500-07:00").map { abs($0.timeIntervalSince(base!) - 7 * 3600) < 0.001 } ?? false,
      "fractional seconds + offset resolve to the right instant")
check(parseISO("not-a-date") == nil, "garbage string -> nil")
check(parseISO("") == nil, "empty string -> nil")
check(parseISO("2026-13-99T99:99:99Z") == nil, "out-of-range components -> nil")

print("clampPct (utilization% -> 0...1):")
check(clampPct(0) == 0.0, "0% -> 0.0")
check(clampPct(100) == 1.0, "100% -> 1.0")
check(clampPct(137) == 1.0, "137% clamps to 1.0")
check(clampPct(-5) == 0.0, "-5% clamps to 0.0")
check(abs(clampPct(50) - 0.5) < 1e-12, "50% -> 0.5")
check(abs(clampPct(99.9) - 0.999) < 1e-12, "99.9% -> 0.999")

// fastISO8601Date must match the formatter to the integer second (the CPU fix must not corrupt dates).
func fmtParse(_ s: String) -> Date? {
    let a = ISO8601DateFormatter(); a.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let b = ISO8601DateFormatter(); b.formatOptions = [.withInternetDateTime]
    return a.date(from: s) ?? b.date(from: s)
}
for c in ["2026-07-06T00:26:11Z", "2026-07-06T00:26:11.123Z", "2024-02-29T12:34:56Z", "2020-01-01T00:00:00Z", "2026-12-31T23:59:59.9Z"] {
    let fast = fastISO8601Date(c)!.timeIntervalSince1970
    let slow = floor(fmtParse(c)!.timeIntervalSince1970)
    check(abs(fast - slow) < 0.001, "fastISO8601Date matches formatter for \(c)")
}
check(fastISO8601Date("garbage") == nil, "fastISO8601Date rejects garbage")

print(failures == 0 ? "\nALL PASS" : "\n\(failures) FAILURE(S)")
exit(failures == 0 ? 0 : 1)
