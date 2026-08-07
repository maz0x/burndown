import Foundation

/// Session id (the log file's name) to the conversation's real title.
///
/// Claude Code names every session log after a UUID, and the title lives INSIDE the file. The live
/// parser reads those files for usage numbers only and named each chat by its filename, so every
/// surface fed by the live path (the card's TOP CHATS, "chats burning now") showed a raw
/// `ca73b9d7-2539-49ff-...` where a name belongs. Only the Insights full scan ever read titles, and
/// the card never runs it.
///
/// This is that missing half: one index both paths write into and every surface reads from. The
/// scan fills it wholesale; the live path fills it one file at a time, on demand, and remembers.
///
/// Kept on disk beside the chat aliases so the names survive a restart. It is derived data: losing
/// it costs one cheap re-read per session, never a wrong number.
final class SessionTitles: ObservableObject {
    static let shared = SessionTitles()

    /// Published so a title arriving after a card is already on screen redraws it.
    @Published private(set) var titles: [String: String] = [:]
    private let lock = NSLock()
    private var dirty = false

    private var url: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/burndown/session-titles.json")
    }

    init() { load() }

    /// The title for a session id, or nil when it has not been read yet.
    func title(for sid: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return titles[sid]
    }

    /// Record a title. Called from the parse queue, so the publish is hopped to the main thread.
    func set(_ title: String, for sid: String) {
        lock.lock()
        guard titles[sid] != title, !title.isEmpty else { lock.unlock(); return }
        var next = titles; next[sid] = title
        dirty = true
        lock.unlock()
        DispatchQueue.main.async { self.titles = next }
        save()   // once per newly seen session, not per poll: title(for:) answers every time after
    }

    /// Record many at once, so a full scan publishes once rather than once per chat.
    func merge(_ found: [String: String]) {
        lock.lock()
        var next = titles
        var changed = false
        for (sid, t) in found where !t.isEmpty && next[sid] != t { next[sid] = t; changed = true }
        if changed { dirty = true }
        lock.unlock()
        guard changed else { return }
        DispatchQueue.main.async { self.titles = next }
        save()
    }

    private func load() {
        guard let d = try? Data(contentsOf: url),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: String] else { return }
        titles = o
    }

    func save() {
        lock.lock()
        guard dirty else { lock.unlock(); return }
        let snapshot = titles
        dirty = false
        lock.unlock()
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        guard let d = try? JSONSerialization.data(withJSONObject: snapshot, options: [.sortedKeys]) else { return }
        try? d.write(to: url)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

// MARK: - Naming, as pure functions so they can be tested without a filesystem

/// Does this look like a raw session id rather than something a person would recognise?
///
/// Claude Code's session ids are UUIDs. This is deliberately narrow: it must never mistake a real
/// conversation title for an id and rename it.
func looksLikeSessionID(_ s: String) -> Bool {
    let t = s.trimmingCharacters(in: .whitespaces)
    guard t.count == 36 else { return false }
    let parts = t.split(separator: "-", omittingEmptySubsequences: false)
    guard parts.map(\.count) == [8, 4, 4, 4, 12] else { return false }
    return parts.allSatisfy { $0.allSatisfy(\.isHexDigit) }
}

/// Tidy a harvested title into something worth showing, or nil when there is nothing to show.
///
/// The first user message doubles as a title when a chat has no proper one, and those arrive with
/// quoting, newlines and command wrappers attached.
func cleanChatTitle(_ raw: String?) -> String? {
    guard var t = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
    // Trim between removals: "> > quoted" leaves a space in front of the second marker, and a
    // bare hasPrefix loop stops there and ships the leftover.
    while t.hasPrefix(">") {
        t.removeFirst()
        t = t.trimmingCharacters(in: .whitespaces)
    }
    // Slash-command invocations arrive wrapped in tags; the command name is the useful part.
    if let r = t.range(of: "<command-name>"), let e = t.range(of: "</command-name>") {
        t = String(t[r.upperBound..<e.lowerBound])
    }
    t = t.replacingOccurrences(of: "\n", with: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !t.isEmpty, !looksLikeSessionID(t) else { return nil }
    // A first user message is only a title when it reads like one. Tool invocations and pasted
    // paths are neither recognisable nor safe to show: "Read `/private/tmp/claude-501/-Users-...`"
    // tells the reader nothing and puts a filesystem path, account name included, on screen.
    if t.contains("/Users/") || t.contains("/private/") || t.contains("/var/folders/") { return nil }
    if t.hasPrefix("Read ") || t.hasPrefix("Bash(") || t.hasPrefix("<") { return nil }
    if t.count > 80 { t = String(t.prefix(80)) + "\u{2026}" }
    return t
}

/// Was this label generated by us because the chat had no title, rather than being its real name?
///
/// It matters for merging: rows are combined when they share a title, because Claude Code splits
/// one conversation across several logs. Two DIFFERENT untitled chats from the same day share a
/// generated label without being the same conversation, so merging on it would add together work
/// that has nothing to do with each other.
func isGeneratedTitle(_ t: String) -> Bool { t.hasPrefix("Untitled chat") }

/// What to show for a chat with no title at all.
///
/// Never the session id. A UUID tells the reader nothing, takes the width of a real name, and puts
/// an opaque string where they expect to recognise their own work.
func untitledChatLabel(_ date: Date?, now: Date = Date()) -> String {
    guard let date else { return "Untitled chat" }
    let f = DateFormatter()
    f.dateFormat = Calendar.current.isDate(date, inSameDayAs: now) ? "h:mm a" : "MMM d"
    return "Untitled chat \u{00B7} " + f.string(from: date)
}
