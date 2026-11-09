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

// A chat message can contain any text at all, including text that talks about the tags this parser
// looks for. The two tags were located independently and sliced between, so a message that merely
// mentioned the closing one first produced a range ending before it started, which is a crash
// rather than an empty result: the app died on opening a conversation whose first message
// discussed slash commands.
print("a message that mentions the tags does not crash:")
check(cleanChatTitle("the closing tag is </command-name> and the opening one is <command-name>") != nil,
      "tags in the wrong order are left alone rather than sliced")
check(cleanChatTitle("</command-name>") == nil, "a lone tag is still refused as a title, as anything starting with < is")
check(cleanChatTitle("<command-name>commit</command-name>") == "commit", "and a real pair still extracts the name")
check(cleanChatTitle("<command-name></command-name>") == nil, "an empty pair yields no title rather than a blank one")
_ = cleanChatTitle("</command-name><command-name>")   // reaching this line at all is the test

// MARK: - Subagent logs are named after the conversation that spawned them
//
// Claude Code writes each subagent to <project>/<parent-uuid>/subagents/agent-<id>.jsonl. Their
// opening message is a task prompt, so the title cleaner refuses it and every one of them used to
// render as "Untitled chat, 2:03 PM": on a real machine, 1,455 of 1,584 tracked sessions.
print("\nsubagent logs:")
let parentUUID = "93ec1bda-c591-4a35-a098-4583df822894"
let agentURL = URL(fileURLWithPath:
    "/Users/x/.claude/projects/-Users-x/\(parentUUID)/subagents/agent-a59a9244009ffd085.jsonl")
let chatURL = URL(fileURLWithPath: "/Users/x/.claude/projects/-Users-x/\(parentUUID).jsonl")

check(isSubagentLog(agentURL), "an agent-*.jsonl under subagents/ is recognised as a subagent")
check(!isSubagentLog(chatURL), "an ordinary conversation log is NOT treated as a subagent")

let parent = subagentParent(of: agentURL)
check(parent?.sid == parentUUID, "the parent session id is the folder the subagents/ dir sits in")
check(parent?.log.lastPathComponent == "\(parentUUID).jsonl", "and its log sits beside that folder")
check(subagentParent(of: chatURL) == nil, "a conversation log has no subagent parent")

// A path shaped like a subagent but whose parent folder is not a session id must not invent one.
check(subagentParent(of: URL(fileURLWithPath: "/tmp/notauuid/subagents/agent-1.jsonl")) == nil,
      "a subagents/ folder under a non-uuid parent yields no parent rather than a bogus id")

check(subagentLabel(parentTitle: "Fix UI overflow issues") == "Agent \u{00B7} Fix UI overflow issues",
      "a named parent gives the agent a recognisable label")
check(subagentLabel(parentTitle: nil) == "Agent tasks", "an unknown parent still says what the work IS")
check(subagentLabel(parentTitle: "Untitled chat \u{00B7} 2:03 PM") == "Agent tasks",
      "a parent that is itself a placeholder is not passed through as if it were a name")
check(!isGeneratedTitle(subagentLabel(parentTitle: "Fix UI overflow issues")),
      "an agent label is a real label, so rows sharing it are allowed to roll up together")

print(failures == 0 ? "\nALL PASS" : "\n\(failures) FAILURE(S)")
exit(failures == 0 ? 0 : 1)
