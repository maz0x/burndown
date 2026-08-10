import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    print(ok ? "  ok   \(what)" : "  FAIL \(what)"); if !ok { failures += 1 }
}

func sample() -> [String: CachedFile] {
    let recs = (0..<500).map { i in
        CachedRecord(ts: 1_754_000_000 + Double(i) * 60, model: i % 2 == 0 ? "claude-opus-5" : "claude-fable-5",
                     input: i, output: i * 2, cache5m: i * 3, cache1h: 0, cacheRead: i * 7,
                     key: ScanCache.keyHash("msg_\(i):req_\(i)"))
    }
    return [
        "/a/one.jsonl": CachedFile(mod: 1_754_000_100, size: 4096, offset: 4000,
                                   project: "Fine Print Doctor", title: "Rebuild the site", records: recs),
        "/a/two.jsonl": CachedFile(mod: 1_754_000_200, size: 8192, offset: 8192,
                                   project: "Home folder", title: "Untitled chat \u{00B7} Aug 5", records: []),
    ]
}

print("round trip:")
let original = sample()
guard let back = ScanCache.decode(ScanCache.encode(original)) else {
    print("  FAIL decode returned nil"); exit(1)
}
check(back.count == original.count, "every file comes back")
check(back["/a/one.jsonl"]?.records.count == 500, "and every record with it")
check(back["/a/one.jsonl"]?.offset == 4000, "the byte offset survives, so a grown file resumes correctly")
check(back["/a/one.jsonl"]?.project == "Fine Print Doctor", "project survives")
check(back["/a/two.jsonl"]?.title == "Untitled chat \u{00B7} Aug 5", "non-ASCII in a title survives")
check(back["/a/two.jsonl"]?.records.isEmpty == true, "a file with no usage rows survives as empty")

let a = original["/a/one.jsonl"]!.records[499], b = back["/a/one.jsonl"]!.records[499]
check(a.ts == b.ts && a.model == b.model && a.input == b.input && a.output == b.output
      && a.cache5m == b.cache5m && a.cache1h == b.cache1h && a.cacheRead == b.cacheRead,
      "the last record is identical field for field")

print("compactness:")
let bytes = ScanCache.encode(original).count
check(bytes < 500 * 48 + 2048, "1000 records pack into well under 48 bytes each (\(bytes) bytes)")

print("refusing bad input:")
check(ScanCache.decode(Data()) == nil, "empty data decodes to nil rather than crashing")
check(ScanCache.decode(Data([1, 2, 3, 4, 5, 6, 7, 8])) == nil, "a wrong magic number is refused")
var truncated = ScanCache.encode(original)
truncated.removeLast(truncated.count / 3)
check(ScanCache.decode(truncated) == nil, "a truncated cache is refused, never half-read")
// A cache written by a future version must not be misread as this one.
var wrongVersion = ScanCache.encode(original)
wrongVersion[4] = 99
check(ScanCache.decode(wrongVersion) == nil, "a different format version is refused")


// The dedup key is the whole reason version 3 exists: without it the scan cannot tell one message
// from the copy of itself that Claude Code writes into the next log when a conversation resumes,
// and a chat resumed three times reports nearly four times its real usage.
print("dedup key:")
let k1 = ScanCache.keyHash("msg_01ABC:req_01XYZ")
check(k1 == ScanCache.keyHash("msg_01ABC:req_01XYZ"), "the same id always hashes to the same value")
check(k1 != ScanCache.keyHash("msg_01ABD:req_01XYZ"), "a different message id hashes differently")
check(k1 != ScanCache.keyHash("msg_01ABC:req_01XYW"), "a different request id hashes differently")
check(ScanCache.keyHash("") == 0, "no message id hashes to 0, the never-de-duplicate sentinel")
check(ScanCache.keyHash("msg_a:req_b") != 0, "a real id never collides with that sentinel")
check(back["/a/one.jsonl"]?.records[7].key == ScanCache.keyHash("msg_7:req_7"),
      "and the key survives the round trip, so a resumed chat is still recognizable after a restart")

// The flatten in UsageEngine de-dupes on exactly this, so prove the shape it relies on: two files
// holding the same message keep one copy, and rows with no id are never merged into each other.
print("de-duplicating the way the scan does:")
let shared = ScanCache.keyHash("msg_dup:req_dup")
let twoLogs: [CachedRecord] = [
    CachedRecord(ts: 1, model: "claude-fable-5", input: 100, output: 10, cache5m: 0, cache1h: 0, cacheRead: 0, key: shared),
    CachedRecord(ts: 1, model: "claude-fable-5", input: 100, output: 10, cache5m: 0, cache1h: 0, cacheRead: 0, key: shared),
    CachedRecord(ts: 2, model: "claude-fable-5", input: 50, output: 5, cache5m: 0, cache1h: 0, cacheRead: 0, key: 0),
    CachedRecord(ts: 3, model: "claude-fable-5", input: 50, output: 5, cache5m: 0, cache1h: 0, cacheRead: 0, key: 0),
]
var seenKeys = Set<UInt64>(); var kept = 0; var inputs = 0
for r in twoLogs {
    if r.key != 0 { if seenKeys.contains(r.key) { continue }; seenKeys.insert(r.key) }
    kept += 1; inputs += r.input
}
check(kept == 3, "the duplicated message counts once, the two unidentified rows both survive")
check(inputs == 200, "and the tokens follow: 100 once, not twice, plus the two 50s")

print(failures == 0 ? "\nALL PASS" : "\n\(failures) FAILURE(S)")
exit(failures == 0 ? 0 : 1)
