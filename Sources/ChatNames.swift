import Foundation

/// Persistent user aliases for harvested chat titles (spec area 5). Stored at
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
        try? d.write(to: url)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    /// The name to show: the user's alias if set, else the harvested original.
    func display(_ original: String) -> String { aliases[original] ?? original }

    func setAlias(_ alias: String, for original: String) {
        let a = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        if a.isEmpty || a == original { aliases.removeValue(forKey: original) } else { aliases[original] = a }
        save()
    }
    func reset(_ original: String) { aliases.removeValue(forKey: original); save() }
}
