import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    print(ok ? "  ok   \(what)" : "  FAIL \(what)"); if !ok { failures += 1 }
}

print("looksLikeSessionID:")
check(looksLikeSessionID("ca73b9d7-2539-49ff-9995-b624c99e4a90"), "a real session id is recognised")
check(looksLikeSessionID("D78FC720-41D4-4136-A134-DA9300D9BB70"), "uppercase too")
check(!looksLikeSessionID("Burndown Settings redesign"), "a real chat title is left alone")
check(!looksLikeSessionID("ca73b9d7-2539-49ff-9995-b624c99e4a9"), "35 characters is not an id")
check(!looksLikeSessionID("zz73b9d7-2539-49ff-9995-b624c99e4a90"), "non-hex is not an id")
check(!looksLikeSessionID("ca73b9d7-2539-49ff-9995b624c99e4a900"), "wrong group shape is not an id")
check(!looksLikeSessionID(""), "empty is not an id")

print("cleanChatTitle:")
check(cleanChatTitle("  Fix the sync worker  ") == "Fix the sync worker", "trims")
check(cleanChatTitle("> > quoted opener") == "quoted opener", "strips quote markers")
check(cleanChatTitle("line one\nline two") == "line one line two", "newlines become spaces")
check(cleanChatTitle("<command-name>/model</command-name>args") == "/model", "a slash command reads as its name")
check(cleanChatTitle(nil) == nil, "nil in, nil out")
check(cleanChatTitle("   ") == nil, "whitespace only is nothing to show")
// The whole point: an id must never survive as a title.
check(cleanChatTitle("ca73b9d7-2539-49ff-9995-b624c99e4a90") == nil, "a session id is never a title")
let long = String(repeating: "a", count: 200)
check((cleanChatTitle(long) ?? "").count == 81, "long titles are cut to 80 plus an ellipsis")

// A tool line or a pasted path is not a title: it is unrecognisable, and it puts a filesystem
// path (account name included) on screen.
check(cleanChatTitle("Read `/private/tmp/claude-501/-Users-someone/x.md`") == nil, "a tool line is not a title")
check(cleanChatTitle("look at /Users/someone/notes.txt") == nil, "a path is not a title")
check(cleanChatTitle("<system-reminder>do the thing") == nil, "a wrapper tag is not a title")
check(cleanChatTitle("Rebuild example.com on Astro") == "Rebuild example.com on Astro",
      "a real title with a domain in it survives")

print("untitledChatLabel:")
let noon = Date(timeIntervalSince1970: 1_754_400_000)
check(untitledChatLabel(nil) == "Untitled chat", "no date, no date shown")
check(untitledChatLabel(noon, now: noon).hasPrefix("Untitled chat"), "always says untitled")
check(!looksLikeSessionID(untitledChatLabel(noon, now: noon)), "and never produces something id-shaped")
// A date from another day carries the day, so two untitled chats are told apart.
let otherDay = noon.addingTimeInterval(3 * 86_400)
check(untitledChatLabel(otherDay, now: noon) != untitledChatLabel(noon, now: noon),
      "different days read differently")

print(failures == 0 ? "\nALL PASS" : "\n\(failures) FAILURE(S)")
exit(failures == 0 ? 0 : 1)
