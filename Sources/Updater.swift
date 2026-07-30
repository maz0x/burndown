import Foundation
import CryptoKit

// Self-contained updater: checks GitHub Releases, downloads the release zip, verifies it against
// the published SHA-256, and swaps the app bundle in place. No Sparkle, no extra dependency.
//
// Why in-app install is safe here: the zip is fetched by URLSession, which does NOT set
// com.apple.quarantine, so the replacement bundle launches without the Gatekeeper prompt a
// browser download would trigger. The bundle PATH is preserved, so macOS permission grants
// (Accessibility for the docked widget) and the LaunchAgent keep working.
//
// The pure parts (release parsing, version compare, checksum extraction) live in
// `UpdateLogic` so they can be tested headlessly, with no network and no filesystem.

// MARK: - Pure logic (headless-testable)

/// One published release, as far as the updater cares.
struct UpdateRelease: Equatable {
    var version: String        // "1.1" (the leading v is stripped)
    var zipURL: String
    var checksumURL: String?
    var notes: String
}

enum UpdateLogic {
    /// Compare dotted version strings numerically: 1.10 is newer than 1.9, 1.0 is not newer than 1.0.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            s.split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 }
        }
        let a = parts(candidate), b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// Parse the GitHub "latest release" payload. Requires a .zip asset; the .sha256 sidecar is
    /// optional (its absence means the download cannot be verified, which the caller must refuse).
    static func parseRelease(_ object: Any?) -> UpdateRelease? {
        guard let o = object as? [String: Any],
              let tag = o["tag_name"] as? String,
              let assets = o["assets"] as? [[String: Any]] else { return nil }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        // The tag is server-supplied and later becomes a temp file name and a literal inside the
        // generated installer script, so refuse anything that is not a plain version string.
        let safe = version.allSatisfy { $0.isASCII && ($0.isNumber || $0 == "." || $0 == "-" || $0.isLetter) }
        guard !version.isEmpty, safe else { return nil }
        func url(suffix: String) -> String? {
            for a in assets {
                if let name = a["name"] as? String, name.hasSuffix(suffix),
                   let u = a["browser_download_url"] as? String { return u }
            }
            return nil
        }
        guard let zip = url(suffix: ".zip") else { return nil }
        return UpdateRelease(version: version, zipURL: zip, checksumURL: url(suffix: ".sha256"),
                             notes: (o["body"] as? String) ?? "")
    }

    /// Pick the best release from the full `/releases` list. GitHub's `/releases/latest` hides
    /// drafts AND pre-releases, so a project whose newest builds are all flagged pre-release looks
    /// like it has no releases at all. This fallback keeps updates flowing: newest stable if there
    /// is one, otherwise the newest pre-release when the user opted into those.
    static func parseReleaseList(_ object: Any?, allowPrerelease: Bool) -> UpdateRelease? {
        guard let arr = object as? [[String: Any]] else { return nil }
        func usable(_ o: [String: Any]) -> Bool {
            if (o["draft"] as? Bool) == true { return false }
            if (o["prerelease"] as? Bool) == true { return allowPrerelease }
            return true
        }
        // The API returns newest first, but sort by version so an out-of-order publish is safe.
        return arr.filter(usable).compactMap { parseRelease($0) }
            .max { isNewer($1.version, than: $0.version) }
    }

    /// Pull the hex digest out of a `shasum -a 256` line ("<64 hex>  path/to/file.zip").
    static func parseChecksum(_ text: String) -> String? {
        for line in text.split(separator: "\n") {
            let token = line.split(separator: " ").first.map(String.init) ?? ""
            let hex = token.lowercased()
            if hex.count == 64, hex.allSatisfy({ $0.isHexDigit }) { return hex }
        }
        return nil
    }

    /// Is this bundle running out of a source checkout? Then never self-install over it: the
    /// developer's tree would be replaced by a release build.
    static func isDevelopmentCheckout(bundlePath: String, fileExists: (String) -> Bool) -> Bool {
        let parent = (bundlePath as NSString).deletingLastPathComponent
        return fileExists(parent + "/Sources") && fileExists(parent + "/build.sh")
    }
}

// MARK: - The updater

@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()
    static let repo = "maz0x/burndown"

    enum State: Equatable {
        case idle
        case checking
        case upToDate(String)          // current version
        case available(UpdateRelease)
        case downloading(Double)       // 0…1
        case verifying
        case readyToRelaunch
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    /// Set once a check has found something newer, so the menu can surface it.
    @Published private(set) var pendingVersion: String?

    private var lastCheck: Date?
    private let d = UserDefaults.standard

    var isDevBuild: Bool {
        UpdateLogic.isDevelopmentCheckout(bundlePath: Bundle.main.bundlePath) {
            FileManager.default.fileExists(atPath: $0)
        }
    }

    /// Human-readable one-liner for the Settings card.
    var statusLine: String {
        switch state {
        case .idle:                 return lastCheckLine
        case .checking:             return "Checking\u{2026}"
        case .upToDate(let v):      return "You're on the latest (\(v))."
        case .available(let r):     return "Version \(r.version) is available."
        case .downloading(let p):   return "Downloading\u{2026} \(Int(p * 100))%"
        case .verifying:            return "Verifying the download\u{2026}"
        case .readyToRelaunch:      return "Update ready. Burndown will restart."
        case .failed(let m):        return m
        }
    }

    private var lastCheckLine: String {
        guard let t = lastCheck ?? (d.object(forKey: "lastUpdateCheck") as? Double).map({ Date(timeIntervalSince1970: $0) })
        else { return "Not checked yet." }
        let s = max(0, Date().timeIntervalSince(t))
        let ago = s < 90 ? "just now" : s < 3600 ? "\(Int(s / 60))m ago" : s < 86400 ? "\(Int(s / 3600))h ago" : "\(Int(s / 86400))d ago"
        return "Checked \(ago)."
    }

    // MARK: Check

    /// Ask GitHub for the latest release. `background` suppresses the "up to date" chatter so a
    /// silent daily check never disturbs whatever the card was showing.
    func check(background: Bool = false, completion: (() -> Void)? = nil) {
        if !background { state = .checking }
        guard let url = URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest") else {
            state = .failed("Could not check for updates."); return
        }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("Burndown/\(kAppVersion)", forHTTPHeaderField: "User-Agent")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: req) { [weak self] data, resp, _ in
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            let parsed = data.flatMap { try? JSONSerialization.jsonObject(with: $0) }
                .flatMap { UpdateLogic.parseRelease($0) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.lastCheck = Date()
                self.d.set(Date().timeIntervalSince1970, forKey: "lastUpdateCheck")
                defer { completion?() }
                guard code == 200, let rel = parsed else {
                    // Nothing at /releases/latest can also mean every release is flagged
                    // pre-release. Try the full list before reporting anything.
                    if code == 404 { self.checkReleaseList(background: background); return }
                    if !background { self.state = .failed("Could not reach GitHub. Try again later.") }
                    return
                }
                if UpdateLogic.isNewer(rel.version, than: kAppVersion) {
                    self.pendingVersion = rel.version
                    self.state = .available(rel)
                } else {
                    self.pendingVersion = nil
                    if !background { self.state = .upToDate(kAppVersion) }
                }
            }
        }.resume()
    }

    /// Fallback: read the whole release list (used when /releases/latest is empty).
    private func checkReleaseList(background: Bool) {
        guard let url = URL(string: "https://api.github.com/repos/\(Self.repo)/releases?per_page=20") else { return }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("Burndown/\(kAppVersion)", forHTTPHeaderField: "User-Agent")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: req) { [weak self] data, resp, _ in
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            let rel = data.flatMap { try? JSONSerialization.jsonObject(with: $0) }
                .flatMap { UpdateLogic.parseReleaseList($0, allowPrerelease: true) }
            DispatchQueue.main.async {
                guard let self else { return }
                guard code == 200, let rel else {
                    if !background { self.state = .failed("No published releases yet.") }
                    return
                }
                if UpdateLogic.isNewer(rel.version, than: kAppVersion) {
                    self.pendingVersion = rel.version
                    self.state = .available(rel)
                } else {
                    self.pendingVersion = nil
                    if !background { self.state = .upToDate(kAppVersion) }
                }
            }
        }.resume()
    }

    /// Daily background check, if the user left automatic checking on.
    func checkInBackgroundIfDue(enabled: Bool) {
        guard enabled, !isDevBuild else { return }
        let last = (d.object(forKey: "lastUpdateCheck") as? Double).map { Date(timeIntervalSince1970: $0) }
        if let last, Date().timeIntervalSince(last) < 24 * 3600 { return }
        check(background: true)
    }

    // MARK: Download + install

    func downloadAndInstall() {
        guard case .available(let rel) = state else { return }
        guard !isDevBuild else {
            state = .failed("This is a development build. Update with git pull and ./build.sh.")
            return
        }
        guard let zipURL = URL(string: rel.zipURL) else { state = .failed("Bad download link."); return }
        guard let sumStr = rel.checksumURL, let sumURL = URL(string: sumStr) else {
            state = .failed("This release has no checksum, so it cannot be verified. Download it manually.")
            return
        }
        state = .downloading(0)

        // 1. Fetch the published checksum, 2. download the zip, 3. verify, 4. swap.
        URLSession.shared.dataTask(with: sumURL) { [weak self] data, _, _ in
            let expected = data.flatMap { String(data: $0, encoding: .utf8) }.flatMap(UpdateLogic.parseChecksum)
            DispatchQueue.main.async {
                guard let self else { return }
                guard let expected else { self.state = .failed("Could not read the release checksum."); return }
                self.download(zipURL, expecting: expected, version: rel.version)
            }
        }.resume()
    }

    private var progressObservation: NSKeyValueObservation?

    private func download(_ url: URL, expecting sha: String, version: String) {
        let task = URLSession.shared.downloadTask(with: url) { [weak self] tmp, resp, err in
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            // The temp file dies when this closure returns, so copy it out synchronously here.
            var staged: URL?
            if let tmp, code == 200 {
                let dest = FileManager.default.temporaryDirectory
                    .appendingPathComponent("burndown-update-\(version).zip")
                try? FileManager.default.removeItem(at: dest)
                if (try? FileManager.default.moveItem(at: tmp, to: dest)) != nil { staged = dest }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.progressObservation = nil
                guard let staged else {
                    self.state = .failed(err != nil ? "Download failed. Check your connection."
                                                    : "Download failed (HTTP \(code)).")
                    return
                }
                self.verifyAndSwap(zip: staged, expecting: sha, version: version)
            }
        }
        progressObservation = task.progress.observe(\.fractionCompleted) { [weak self] p, _ in
            DispatchQueue.main.async {
                guard let self, case .downloading = self.state else { return }
                self.state = .downloading(p.fractionCompleted)
            }
        }
        task.resume()
    }

    private func verifyAndSwap(zip: URL, expecting sha: String, version: String) {
        state = .verifying
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            func fail(_ m: String) { DispatchQueue.main.async { self?.state = .failed(m) } }

            // Checksum
            guard let data = try? Data(contentsOf: zip) else { return fail("Could not read the download.") }
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard digest == sha.lowercased() else {
                try? FileManager.default.removeItem(at: zip)
                return fail("The download did not match its checksum and was discarded.")
            }

            // Unpack
            let work = FileManager.default.temporaryDirectory.appendingPathComponent("burndown-update-\(version)")
            try? FileManager.default.removeItem(at: work)
            try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            guard run("/usr/bin/ditto", ["-x", "-k", zip.path, work.path]) else { return fail("Could not unpack the update.") }
            let newApp = work.appendingPathComponent("Burndown.app")
            guard FileManager.default.fileExists(atPath: newApp.path) else { return fail("The update did not contain Burndown.app.") }

            // The signature must at least be intact (ad-hoc today, Developer ID later).
            guard run("/usr/bin/codesign", ["-v", newApp.path]) else { return fail("The update's signature did not verify.") }

            DispatchQueue.main.async { self?.swap(newApp: newApp, version: version) }
        }
    }

    /// Replace the running bundle and relaunch, via a detached helper that waits for us to exit.
    private func swap(newApp: URL, version: String) {
        let dest = Bundle.main.bundleURL
        guard FileManager.default.isWritableFile(atPath: dest.deletingLastPathComponent().path) else {
            state = .failed("Cannot write to \(dest.deletingLastPathComponent().path). Move Burndown to Applications and try again.")
            return
        }
        let script = FileManager.default.temporaryDirectory.appendingPathComponent("burndown-install-\(version).sh")
        let body = """
        #!/bin/bash
        # Installer helper written by Burndown \(kAppVersion). Waits for the app to quit, swaps the
        # bundle in place (preserving its path so permissions survive), and relaunches it.
        set -u
        for _ in $(seq 1 100); do kill -0 \(getpid()) 2>/dev/null || break; sleep 0.2; done
        sleep 0.5
        rm -rf "\(dest.path).old"
        mv "\(dest.path)" "\(dest.path).old" 2>/dev/null
        /usr/bin/ditto "\(newApp.path)" "\(dest.path)"
        if [ -x "\(dest.path)/Contents/MacOS/Burndown" ]; then
            /usr/bin/xattr -cr "\(dest.path)" 2>/dev/null
            rm -rf "\(dest.path).old"
        else
            mv "\(dest.path).old" "\(dest.path)" 2>/dev/null   # rollback: keep the working app
        fi
        rm -rf "\(newApp.deletingLastPathComponent().path)"
        /usr/bin/open "\(dest.path)"
        rm -f "$0"
        """
        do {
            try body.write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        } catch { state = .failed("Could not stage the installer."); return }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [script.path]
        do { try p.run() } catch { state = .failed("Could not start the installer."); return }

        state = .readyToRelaunch
        // Give the card a beat to show the final state, then get out of the helper's way.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { NSApplication.shared.terminate(nil) }
    }
}

/// Run a tool, true on exit status 0. Used only with constant, non-user-supplied arguments.
@discardableResult
private func run(_ path: String, _ args: [String]) -> Bool {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    p.standardOutput = Pipe(); p.standardError = Pipe()
    do { try p.run() } catch { return false }
    p.waitUntilExit()
    return p.terminationStatus == 0
}

#if canImport(AppKit)
import AppKit
#endif
