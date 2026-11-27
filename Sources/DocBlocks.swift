import Foundation

// The documents bundled with the app (RELEASE_NOTES.md, PRIVACY.md) used to be handed to
// NSWorkspace, which opened whatever owns .md files on the reader's Mac: usually a code editor
// pointed inside the app bundle, or nothing at all. The About window now shows them in its own
// reader, and this is the part of that reader that turns the text into blocks. It is Foundation
// only so it can be tested headless (run-docblocks-tests.sh).

/// One block of a bundled document. Inline markdown (bold, `code`, links) stays in the text,
/// untouched: the view renders it.
enum DocBlock: Equatable {
    case heading(level: Int, text: String)
    case bullet(text: String)
    case paragraph(text: String)
    case rule
}

/// Split a bundled markdown document into blocks.
///
/// The files are hard-wrapped at about 100 columns, so the one rule that matters most is that a
/// source line is never a display line: consecutive lines of a paragraph are joined with single
/// spaces, and the indented lines under a bullet are joined onto that bullet. Only the constructs
/// the bundled files really use are recognised; anything else reads as a plain paragraph.
func docBlocks(_ markdown: String) -> [DocBlock] {
    var blocks: [DocBlock] = []
    var para: [String] = []          // lines of the paragraph being collected
    var bullet: [String]? = nil      // lines of the bullet being collected, nil when none is open
    var inFence = false

    func flush() {
        if !para.isEmpty { blocks.append(.paragraph(text: para.joined(separator: " "))); para = [] }
        if let b = bullet { blocks.append(.bullet(text: b.joined(separator: " "))); bullet = nil }
    }

    let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
    for raw in lines {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)

        // Code fences: every line inside is kept as it is, one block per line, because joining
        // them would run separate commands together. The fence lines themselves are not shown.
        if trimmed.hasPrefix("```") { flush(); inFence.toggle(); continue }
        if inFence {
            if !trimmed.isEmpty { blocks.append(.paragraph(text: raw)) }
            continue
        }

        if trimmed.isEmpty { flush(); continue }

        // A heading: one to six '#', then a space.
        let hashes = trimmed.prefix(while: { $0 == "#" }).count
        if (1...6).contains(hashes), trimmed.dropFirst(hashes).first == " " {
            flush()
            let text = trimmed.dropFirst(hashes).trimmingCharacters(in: .whitespaces)
            blocks.append(.heading(level: hashes, text: text))
            continue
        }

        // A rule: three or more '-' and nothing else.
        if trimmed.count >= 3, trimmed.allSatisfy({ $0 == "-" }) { flush(); blocks.append(.rule); continue }

        // A new bullet.
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
            flush()
            bullet = [trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces)]
            continue
        }

        // An indented line under an open bullet carries on that bullet.
        if bullet != nil, raw.first == " " || raw.first == "\t" {
            bullet?.append(trimmed)
            continue
        }

        // Anything else is paragraph text. A quote marker is dropped; the quote reads as prose.
        if bullet != nil { flush() }
        var text = trimmed
        if text == ">" { flush(); continue }
        if text.hasPrefix("> ") { text = text.dropFirst(2).trimmingCharacters(in: .whitespaces) }
        para.append(text)
    }
    flush()
    return blocks
}
