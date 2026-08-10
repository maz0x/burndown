import Foundation

/// Persistent user aliases for harvested chat titles. Stored at
/// ~/.config/burndown/names.json (chmod 600), mapping original title -> alias. The alias replaces the
/// harvested name on every surface (popover chats, Insights); Reset removes it.
final class ChatNames: ObservableObject {
    static let shared = ChatNames()
    @Published private(set) var aliases: [String: String] = [:]

    private var url: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/burndown/names.json")
    }
    init() { load() }

    private func load() {
        guard let d = try? Data(contentsOf: url),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: String] else { return }
        aliases = o
    }
    private func save() {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let d = try? JSONSerialization.data(withJSONObject: aliases, options: [.sortedKeys]) else { return }
        writePrivate(d, to: url)
    }

    /// The name to show: the user's alias if set, else the harvested original.
    ///
    /// The last line of defence against a raw session id reaching the reader. Both data paths now
    /// carry real titles, but a record from an older cache, or a log whose title could not be
    /// read, could still arrive here as a bare UUID, and a UUID on screen is never the right
    /// answer. Checked at the point of display so no future caller can route around it.
    func display(_ original: String) -> String {
        if let a = aliases[original] { return a }
        if looksLikeSessionID(original) {
            // Check the alias table AGAIN against the resolved title. A chat first seen as a raw id
            // is renamed under the name the reader saw, which is the resolved one, so looking up
            // only the id meant a renamed chat kept surfacing under its old name wherever the id
            // arrived first.
            guard let resolved = SessionTitles.shared.title(for: original) else { return untitledChatLabel(nil) }
            return aliases[resolved] ?? resolved
        }
        return original
    }

    func setAlias(_ alias: String, for original: String) {
        let a = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        if a.isEmpty || a == original { aliases.removeValue(forKey: original) } else { aliases[original] = a }
        save()
    }
    func reset(_ original: String) { aliases.removeValue(forKey: original); save() }
}
