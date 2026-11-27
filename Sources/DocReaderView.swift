import SwiftUI

/// Shows a markdown document bundled with the app (Resources/<name>.md) in the app's own window,
/// opened from the About window's "What's new" and "Privacy" links. Handing the file to the system
/// opened a code editor inside the app bundle, or nothing; this reads like the rest of the app.
struct BundledDocView: View {
    let name: String
    @Environment(\.colorScheme) private var scheme

    /// Parsed once, when the view is made: the documents are small and never change while the app
    /// runs, so a theme change or any other redraw has no reason to read the file again.
    private let blocks: [DocBlock]?

    init(name: String) {
        self.name = name
        if let u = Bundle.main.url(forResource: name, withExtension: "md"),
           let s = try? String(contentsOf: u, encoding: .utf8) {
            blocks = docBlocks(s)
        } else {
            blocks = nil
        }
    }

    var body: some View {
        let p = Palette.of(scheme)
        Group {
            if let blocks {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(blocks.enumerated()), id: \.offset) { i, b in
                            block(b, first: i == 0, p)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 26)
                    .textSelection(.enabled)
                }
            } else {
                Text("This document is not included in this build.")
                    .font(.system(size: 12)).foregroundStyle(p.sub)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 380, minHeight: 320)
        .background(p.bg)
        .tint(p.session)   // links take the same accent as the About window's links
    }

    @ViewBuilder
    private func block(_ b: DocBlock, first: Bool, _ p: Palette) -> some View {
        switch b {
        case .heading(let level, let text):
            // More room above a heading than below, so each heading belongs to what follows it.
            let size: CGFloat = level == 1 ? 20 : level == 2 ? 15 : 12.5
            let above: CGFloat = first ? 0 : level == 1 ? 20 : level == 2 ? 16 : 10
            inline(text)
                .font(.system(size: size, weight: .semibold, design: .serif))
                .foregroundStyle(p.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, above).padding(.bottom, level <= 2 ? 2 : 0)
        case .paragraph(let text):
            inline(text)
                .font(.system(size: 12)).lineSpacing(3).foregroundStyle(p.ink)
                .fixedSize(horizontal: false, vertical: true)
        case .bullet(let text):
            // A hanging bullet: the dot sits in its own column, so wrapped lines align under the text.
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("•").font(.system(size: 12)).foregroundStyle(p.sub)
                inline(text)
                    .font(.system(size: 12)).lineSpacing(3).foregroundStyle(p.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, 4)
        case .rule:
            Rectangle().fill(p.divider).frame(height: 1).padding(.vertical, 6)
        }
    }

    /// Bold, `code` and links rendered; if the markdown will not parse, the plain words still show.
    private func inline(_ s: String) -> Text {
        if let a = try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return Text(a)
        }
        return Text(s)
    }
}
