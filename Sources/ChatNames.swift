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

    /// THE ALIAS KEY, once, for every surface that renames a chat.
    ///
    /// Two paths reach the reader with a chat's name and both must land on the SAME entry, or a
    /// rename made in one place silently applies to nothing in the other:
    ///   burning-now rows -> LiveActivity.streamName(path) -> UsageEngine.resolvedTitle(sid:url:)
    ///   top-chats rows   -> UsageRecord.session           -> UsageEngine.resolvedTitle(sid:url:)
    /// Both are therefore RESOLVED TITLES, not raw session ids, and the two agree. The one case
    /// where they can diverge is a name that arrives as a bare id anyway (an older cache, a log
    /// whose title could not be read): `display` already resolves such a key before looking it up,
    /// so writing had to resolve it too. Without this, an alias stored under an id was found only
    /// by the surface that happened to hold the id.
    private func key(_ original: String) -> String {
        guard looksLikeSessionID(original) else { return original }
        return SessionTitles.shared.title(for: original) ?? original
    }

    func setAlias(_ alias: String, for original: String) {
        let k = key(original)
        let a = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        if a.isEmpty || a == k { aliases.removeValue(forKey: k) } else { aliases[k] = a }
        save()
    }
    func reset(_ original: String) { aliases.removeValue(forKey: key(original)); save() }
    /// Has the reader renamed this chat? Asked by every row that offers a Reset, and it has to ask
    /// under the same keys `display` reads, in the same order: an alias stored against a raw id by
    /// an older build is found by `display` and would otherwise be reported here as no rename at
    /// all, hiding the Reset for the one chat that needs it.
    func isRenamed(_ original: String) -> Bool {
        aliases[original] != nil || aliases[key(original)] != nil
    }
}
