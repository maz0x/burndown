import Foundation

// Headless harness for the live JSON contract (Sources/LiveContract.swift). Same check()/failures/exit(1)
// pattern as Tests/chartdata/main.swift. BurndownLive lives in LiveContract.swift, which is Foundation-pure,
// so unlike the chart tests there is no value type to redeclare here.

var failures = 0
func check(_ cond: Bool, _ msg: String) {
    print(cond ? "  ok   \(msg)" : "  FAIL \(msg)")
    if !cond { failures += 1 }
}

// A fully populated value (every optional present) and a minimal value (every optional nil).
let full = BurndownLive(
    schemaVersion: 1,
    generatedAt: "2026-06-28T12:00:00Z",
    plan: "Max 20x",
    sessionPct: 0.42,
    weeklyPct: 0.73,
    opusPct: 0.55,
    sonnetPct: 0.18,
    sessionResetAt: "2026-06-28T17:00:00Z",
    weeklyResetAt: "2026-07-01T00:00:00Z",
    burnPerMin: 1234.5
)
let minimal = BurndownLive(
    schemaVersion: 1,
    generatedAt: "2026-06-28T12:00:00Z",
    plan: nil,
    sessionPct: 0.0,
    weeklyPct: 0.0,
    opusPct: nil,
    sonnetPct: nil,
    sessionResetAt: nil,
    weeklyResetAt: nil,
    burnPerMin: nil
)

print("encode (valid JSON / required keys):")
let fullJSON = encodeBurndownLive(full)
check(fullJSON.contains("\"schemaVersion\""), "output contains schemaVersion")
check(fullJSON.contains("\"sessionPct\""), "output contains sessionPct")
check(fullJSON.contains("\"weeklyPct\""), "output contains weeklyPct")
// Pretty-printed output is multi-line with two-space indentation.
check(fullJSON.contains("\n"), "pretty-printed output is multi-line")
// Re-parse the emitted string as generic JSON to prove it is valid.
let fullData = fullJSON.data(using: .utf8)!
let obj = try? JSONSerialization.jsonObject(with: fullData) as? [String: Any]
check((obj ?? nil) != nil, "emitted string is valid JSON object")
check((obj ?? [:])["schemaVersion"] as? Int == 1, "schemaVersion serializes as 1")

print("round-trip (encode then decode == original):")
check(decodeBurndownLive(fullJSON) == full, "fully populated value round-trips equal")
let minJSON = encodeBurndownLive(minimal)
check(decodeBurndownLive(minJSON) == minimal, "minimal (all-nil optionals) value round-trips equal")

print("sortedKeys stability:")
// sortedKeys means key order is deterministic, so re-encoding yields a byte-identical string.
check(encodeBurndownLive(full) == fullJSON, "re-encoding the same value is byte-stable")
// Keys appear in ascending alphabetical order: burnPerMin before generatedAt before schemaVersion.
let iBurn = fullJSON.range(of: "\"burnPerMin\"")!.lowerBound
let iGen = fullJSON.range(of: "\"generatedAt\"")!.lowerBound
let iSchema = fullJSON.range(of: "\"schemaVersion\"")!.lowerBound
check(iBurn < iGen && iGen < iSchema, "keys are emitted in sorted (alphabetical) order")

print("optionals omitted when nil:")
check(!minJSON.contains("\"plan\""), "nil optional (plan) is omitted from output")
check(!minJSON.contains("\"opusPct\""), "nil optional (opusPct) is omitted from output")
check(fullJSON.contains("\"plan\""), "present optional (plan) is included in output")

print("decode boundary / empty input:")
check(decodeBurndownLive("") == nil, "empty string decodes to nil")
check(decodeBurndownLive("not json") == nil, "garbage string decodes to nil")
// Missing a required (non-optional) field must fail to decode.
check(decodeBurndownLive("{\"schemaVersion\":1}") == nil, "missing required fields decodes to nil")
// A minimal valid object (only the required fields) decodes, with optionals nil.
let bare = "{\"schemaVersion\":1,\"generatedAt\":\"2026-06-28T12:00:00Z\",\"sessionPct\":0.5,\"weeklyPct\":0.25}"
let decodedBare = decodeBurndownLive(bare)
check(decodedBare?.sessionPct == 0.5 && decodedBare?.plan == nil, "object with only required fields decodes, optionals nil")
// Boundary pct values 0 and 1 survive the round trip exactly.
let edge = BurndownLive(schemaVersion: 1, generatedAt: "2026-06-28T00:00:00Z", plan: nil,
                        sessionPct: 0.0, weeklyPct: 1.0, opusPct: 1.0, sonnetPct: 0.0,
                        sessionResetAt: nil, weeklyResetAt: nil, burnPerMin: 0.0)
check(decodeBurndownLive(encodeBurndownLive(edge)) == edge, "boundary pct values (0 and 1) round-trip exactly")

print(failures == 0 ? "\nALL LIVECONTRACT TESTS PASSED" : "\n\(failures) FAILURE(S)")
exit(failures == 0 ? 0 : 1)
