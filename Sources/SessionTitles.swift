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
    ///
    /// The published mirror, for SwiftUI. Written ONLY on the main thread and read only by views.
    ///
    /// The dictionary the rest of the app asks questions of is `store`, below. Keeping one
    /// dictionary for both jobs is what made this unsafe: the writers published a new value with a
    /// hop to main, outside the lock, while title(for:) read the same property under the lock from
    /// two background queues. A lock only excludes other lock holders, so the reassignment on main
    /// raced a background read of the same storage, which is undefined behaviour rather than a
    /// stale answer.
    @Published private(set) var titles: [String: String] = [:]
    /// The real index. Every read and every write happens under `lock`, on whatever thread.
    private var store: [String: String] = [:]
    /// Placeholder labels, held in memory with an expiry and NEVER written to disk.
    ///
    /// A chat is scanned the moment it starts spending tokens, which is usually BEFORE Claude Code
    /// has written its title. The placeholder that produced was then stored exactly like a real
    /// name, and `title(for:)` answers from the index without re-reading the file, so the chat was
    /// branded "Untitled chat, 2:03 PM" permanently: the title landed in the log seconds later and
    /// nothing ever looked again. On this Mac that had happened to 1,149 of 1,584 sessions.
    /// Placeholders now go stale on their own, so the next poll re-reads and picks up the real
    /// title, and only real titles are persisted.
    private var provisional: [String: (title: String, until: Date)] = [:]
    /// How long a placeholder is trusted before the file is worth re-reading. Long enough that the
    /// live path is not re-reading log heads every tick, short enough that a name appears promptly.
    private let provisionalTTL: TimeInterval = 45
    private let lock = NSLock()
    private var dirty = false

    private var url: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/burndown/session-titles.json")
    }

    init() { load(); dropPersistedPlaceholders() }

    /// The title for a session id, or nil when it has not been read yet (or is due a re-read).
    func title(for sid: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        if let real = store[sid] { return real }
        if let p = provisional[sid], p.until > Date() { return p.title }
        return nil
    }

    /// Publish the current index to SwiftUI. The snapshot is taken by the caller, under the lock.
    ///
    /// Only when it actually differs. Assigning an @Published dictionary fires objectWillChange
    /// whatever the value, and `merge` runs on every full scan, so an unchanged index redrew every
    /// surface that reads a title once per scan for nothing.
    private func publish(_ snapshot: [String: String]) {
        if Thread.isMainThread {
            if titles != snapshot { titles = snapshot }
        } else {
            DispatchQueue.main.async { if self.titles != snapshot { self.titles = snapshot } }
        }
    }

    /// Record a title. Called from the parse queue, so the publish is hopped to the main thread.
    ///
    /// A GENERATED placeholder is held provisionally instead of being written: see `provisional`.
    func set(_ title: String, for sid: String) {
        guard !title.isEmpty else { return }
        if isGeneratedTitle(title) {
            lock.lock()
            provisional[sid] = (title, Date().addingTimeInterval(provisionalTTL))
            // Published too, so a card on screen shows SOMETHING for a chat that has no name yet
            // rather than a gap; it is simply never saved, and it expires.
            var snapshot = store
            for (k, v) in provisional where v.until > Date() && snapshot[k] == nil { snapshot[k] = v.title }
            lock.unlock()
            publish(snapshot)
            return
        }
        lock.lock()
        guard store[sid] != title else { lock.unlock(); return }
        store[sid] = title
        provisional[sid] = nil          // a real name supersedes the placeholder
        dirty = true
        let snapshot = store
        lock.unlock()
        publish(snapshot)
        save()   // once per newly seen session, not per poll: title(for:) answers every time after
    }

    /// Record many at once, so a full scan publishes once rather than once per chat.
    func merge(_ found: [String: String]) {
        lock.lock()
        var changed = false
        let now = Date()
        for (sid, t) in found where !t.isEmpty {
            // Same rule as set(): placeholders are provisional, never persisted.
            if isGeneratedTitle(t) {
                if store[sid] == nil { provisional[sid] = (t, now.addingTimeInterval(provisionalTTL)) }
                continue
            }
            if store[sid] != t { store[sid] = t; provisional[sid] = nil; changed = true }
        }
        if changed { dirty = true }
        var snapshot = store
        for (k, v) in provisional where v.until > now && snapshot[k] == nil { snapshot[k] = v.title }
        lock.unlock()
        publish(snapshot)
        guard changed else { return }
        save()
    }

    /// Drop placeholders that leaked into an older index file.
    ///
    /// Before placeholders were made provisional they were saved like real names, so an existing
    /// install carries thousands of permanent "Untitled chat" entries that would otherwise never be
    /// re-read. Clearing them once on load lets every one of those chats pick up its real title.
    private func dropPersistedPlaceholders() {
        lock.lock()
        let before = store.count
        store = store.filter { !isGeneratedTitle($0.value) }
        if store.count != before { dirty = true }
        let snapshot = store
        lock.unlock()
        if before != snapshot.count { publish(snapshot); save() }
    }

    private func load() {
        guard let d = try? Data(contentsOf: url),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: String] else { return }
        lock.lock(); store = o; lock.unlock()
        publish(o)
    }

    func save() {
        lock.lock()
        guard dirty else { lock.unlock(); return }
        // Snapshotted from `store`, which already holds the entry that set the dirty flag. It used
        // to snapshot the PUBLISHED property, whose update is an async hop that has almost never
        // run by the time this executes, so it wrote the pre-update dictionary to disk and cleared
        // dirty anyway. The title that triggered the save was the one title the save left out, and
        // it only reached disk if some later chat happened to trigger another one.
        let snapshot = store
        dirty = false
        lock.unlock()
        guard let d = try? JSONSerialization.data(withJSONObject: snapshot, options: [.sortedKeys]) else { return }
        writePrivate(d, to: url)
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
    //
    // The two tags are searched for independently, so nothing guarantees they arrive in that
    // order: a message that merely TALKS about the tags, closing one first, produces a range whose
    // end precedes its start, and slicing a string with it is a crash, not an empty result. Any
    // message can contain any text, so this has to be checked rather than assumed.
    if let r = t.range(of: "<command-name>"), let e = t.range(of: "</command-name>"),
       r.upperBound <= e.lowerBound {
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

/// Is this log a SUBAGENT's rather than a conversation's?
///
/// Claude Code writes each subagent it spawns to
/// `…/projects/<project>/<parent-session-uuid>/subagents/agent-<id>.jsonl`. They are real token
/// spenders, so they belong in the numbers, but they are not chats: nobody typed their opening
/// message, so it is a task prompt or a file path, which the title cleaner correctly refuses. The
/// result was a row reading "Untitled chat, 2:03 PM" for work the reader never started by hand and
/// cannot place. On this Mac they are 1,455 of 1,584 tracked sessions.
func isSubagentLog(_ url: URL) -> Bool {
    url.lastPathComponent.hasPrefix("agent-")
        || url.deletingLastPathComponent().lastPathComponent == "subagents"
}

/// The parent conversation's session id and log file for a subagent log, if it looks like one.
func subagentParent(of url: URL) -> (sid: String, log: URL)? {
    let subagentsDir = url.deletingLastPathComponent()
    guard subagentsDir.lastPathComponent == "subagents" else { return nil }
    let parentDir = subagentsDir.deletingLastPathComponent()
    let sid = parentDir.lastPathComponent
    guard looksLikeSessionID(sid) else { return nil }
    return (sid, parentDir.deletingLastPathComponent().appendingPathComponent(sid + ".jsonl"))
}

/// What to call a subagent's work, given its parent conversation's name.
///
/// Named after the parent on purpose. Several agents of one chat then share a label and roll up into
/// a single row, which is how a person thinks about it ("the agents that chat ran"), instead of
/// three anonymous rows competing with the chat that spawned them.
func subagentLabel(parentTitle: String?) -> String {
    guard let t = parentTitle, !t.isEmpty, !isGeneratedTitle(t) else { return "Agent tasks" }
    return "Agent \u{00B7} " + t
}

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
