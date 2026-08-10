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

// The fast path computes a UTC instant, so a stamp carrying a zone offset must not go through it.
// It used to read the first nineteen characters and ignore the rest, which turned a local
// wall-clock time into a UTC one and moved that record by the size of the offset: a whole evening
// of work could land on the wrong day. Returning nil hands it to the tolerant formatter, which
// does honour the offset.
print("zone offsets:")
check(fastISO8601Date("2026-08-09T10:00:00+05:00") == nil, "a positive offset is refused, not silently read as UTC")
check(fastISO8601Date("2026-08-09T10:00:00-07:00") == nil, "and a negative one")
check(fastISO8601Date("2026-08-09T10:00:00.123-07:00") == nil, "including with fractional seconds")
check(fastISO8601Date("2026-08-09T10:00:00Z") != nil, "a Z stamp still takes the fast path")
check(fastISO8601Date("2026-08-09T10:00:00.123Z") != nil, "and so does one with fractional seconds")
check(fastISO8601Date("2026-08-09T10:00:00") != nil, "and a bare stamp with no suffix at all")
// The tolerant path is what actually reads the offset, so prove the pair works end to end.
let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime]
if let viaFormatter = iso.date(from: "2026-08-09T10:00:00+05:00"),
   let utc = fastISO8601Date("2026-08-09T05:00:00Z") {
    check(abs(viaFormatter.timeIntervalSince(utc)) < 1, "and the fallback lands on the same instant, five hours earlier")
} else {
    check(false, "the tolerant formatter should parse an offset stamp")
}

print(failures == 0 ? "\nALL PASS" : "\n\(failures) FAILURE(S)")
exit(failures == 0 ? 0 : 1)
