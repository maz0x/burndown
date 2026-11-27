import Foundation

// docBlocks comes from the real Sources/DocBlocks.swift (compiled in by run-docblocks-tests.sh).
// Same check()/failures/exit pattern as Tests/recap/main.swift.

var failures = 0
func check(_ cond: Bool, _ msg: String) {
    print(cond ? "  ok   \(msg)" : "  FAIL \(msg)")
    if !cond { failures += 1 }
}

print("headings:")
check(docBlocks("# One") == [.heading(level: 1, text: "One")], "one '#' is level 1")
check(docBlocks("## Two") == [.heading(level: 2, text: "Two")], "two '#' is level 2")
check(docBlocks("### Three") == [.heading(level: 3, text: "Three")], "three '#' is level 3")
check(docBlocks("###### Six") == [.heading(level: 6, text: "Six")], "six '#' is level 6")
check(docBlocks("####### Seven") == [.paragraph(text: "####### Seven")], "seven '#' is not a heading")
check(docBlocks("#tag") == [.paragraph(text: "#tag")], "a '#' with no space after it is not a heading")

print("paragraphs:")
check(docBlocks("Two things in this release. Burndown asked\nClaude for your limits far more often\nthan you told it to.")
      == [.paragraph(text: "Two things in this release. Burndown asked Claude for your limits far more often than you told it to.")],
      "a hard-wrapped paragraph is joined into one")
check(docBlocks("First paragraph.\n\nSecond paragraph.")
      == [.paragraph(text: "First paragraph."), .paragraph(text: "Second paragraph.")],
      "a blank line splits paragraphs")
check(docBlocks("Has **bold**, `code` and [a link](https://example.com).")
      == [.paragraph(text: "Has **bold**, `code` and [a link](https://example.com).")],
      "inline markdown is left untouched for the view")

print("bullets:")
check(docBlocks("- **Refresh every** now means\n  what it says.")
      == [.bullet(text: "**Refresh every** now means what it says.")],
      "a bullet's indented continuation line is joined onto it")
check(docBlocks("- First\n- Second") == [.bullet(text: "First"), .bullet(text: "Second")], "two bullets stay two")
check(docBlocks("* Star bullet") == [.bullet(text: "Star bullet")], "'* ' starts a bullet too")
check(docBlocks("- A bullet\n\nA paragraph after it.")
      == [.bullet(text: "A bullet"), .paragraph(text: "A paragraph after it.")],
      "a blank line ends a bullet")
check(docBlocks("Intro line:\n- item") == [.paragraph(text: "Intro line:"), .bullet(text: "item")],
      "a bullet right after a paragraph line starts its own block")

print("rules, quotes, code:")
check(docBlocks("Above\n\n---\n\nBelow") == [.paragraph(text: "Above"), .rule, .paragraph(text: "Below")], "--- is a rule")
check(docBlocks("-----") == [.rule], "a longer run of dashes is a rule too")
check(docBlocks("> Quoted words here.") == [.paragraph(text: "Quoted words here.")], "the quote marker is stripped")
check(docBlocks("```\nfor f in run-*.sh; do\n  bash \"$f\"\ndone\n```")
      == [.paragraph(text: "for f in run-*.sh; do"), .paragraph(text: "  bash \"$f\""), .paragraph(text: "done")],
      "a code fence keeps one block per line, text unchanged")
check(docBlocks("```\n# not a heading\n- not a bullet\n```")
      == [.paragraph(text: "# not a heading"), .paragraph(text: "- not a bullet")],
      "markdown inside a fence is not interpreted")

print("edges:")
check(docBlocks("") == [], "empty input gives no blocks")
check(docBlocks("\n\n   \n") == [], "blank-only input gives no blocks")
check(docBlocks("Windows line\r\nendings") == [.paragraph(text: "Windows line endings")], "CRLF line endings are handled")

// The real files, so a change to either one cannot quietly break the reader.
print("the bundled documents:")
for name in ["docs/RELEASE_NOTES.md", "docs/PRIVACY.md"] {
    guard let s = try? String(contentsOfFile: name, encoding: .utf8) else {
        check(false, "\(name) can be read"); continue
    }
    let b = docBlocks(s)
    func text(_ d: DocBlock) -> String {
        switch d {
        case .heading(_, let t), .bullet(let t), .paragraph(let t): return t
        case .rule: return ""
        }
    }
    check(b.count > 10, "\(name) yields more than 10 blocks (\(b.count))")
    check(!b.contains { text($0).contains("\n") }, "\(name): no block text contains a newline")
    check(!b.contains { if case .heading(_, let t) = $0 { return t.hasPrefix("#") }; return false },
          "\(name): no heading text starts with '#'")
    check(b.first.map { if case .heading(1, _) = $0 { return true }; return false } ?? false,
          "\(name) opens with its title heading")
    check(b.contains { if case .bullet = $0 { return true }; return false }, "\(name) has bullets")
}

print(failures == 0 ? "\nALL DOCBLOCKS TESTS PASSED" : "\n\(failures) FAILURE(S)")
exit(failures == 0 ? 0 : 1)
