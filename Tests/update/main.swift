import Foundation

// Tests for the pure update logic (version compare, release parsing, checksum extraction,
// dev-checkout detection). No network, no filesystem: everything is injected.

var failures = 0
func check(_ cond: Bool, _ what: String) {
    if cond { print("  ok   \(what)") } else { print("  FAIL \(what)"); failures += 1 }
}

// MARK: isNewer

check(UpdateLogic.isNewer("1.1", than: "1.0"), "1.1 is newer than 1.0")
check(!UpdateLogic.isNewer("1.0", than: "1.0"), "same version is not newer")
check(!UpdateLogic.isNewer("0.9", than: "1.0"), "older version is not newer")
check(UpdateLogic.isNewer("1.10", than: "1.9"), "1.10 beats 1.9 numerically, not alphabetically")
check(UpdateLogic.isNewer("2.0", than: "1.99"), "major version wins")
check(UpdateLogic.isNewer("1.0.1", than: "1.0"), "patch release is newer than its base")
check(!UpdateLogic.isNewer("1.0", than: "1.0.1"), "base is not newer than its patch")
check(UpdateLogic.isNewer("1.2", than: "1.1.9"), "1.2 beats 1.1.9")
check(!UpdateLogic.isNewer("", than: "1.0"), "empty version is never newer")

// MARK: parseRelease

let good: [String: Any] = [
    "tag_name": "v1.1",
    "body": "notes here",
    "assets": [
        ["name": "Burndown-1.1.zip", "browser_download_url": "https://example.test/Burndown-1.1.zip"],
        ["name": "Burndown-1.1.zip.sha256", "browser_download_url": "https://example.test/Burndown-1.1.zip.sha256"],
    ],
]
let rel = UpdateLogic.parseRelease(good)
check(rel?.version == "1.1", "tag v1.1 parses to version 1.1 (leading v stripped)")
check(rel?.zipURL == "https://example.test/Burndown-1.1.zip", "zip asset found")
check(rel?.checksumURL == "https://example.test/Burndown-1.1.zip.sha256", "checksum asset found")
check(rel?.notes == "notes here", "release notes carried")

// A release with no zip is unusable.
check(UpdateLogic.parseRelease(["tag_name": "v1.1", "assets": []]) == nil, "no zip asset means no update")
// Missing checksum parses but must be flagged (the installer refuses it).
let noSum = UpdateLogic.parseRelease([
    "tag_name": "1.2",
    "assets": [["name": "Burndown-1.2.zip", "browser_download_url": "https://example.test/z.zip"]],
])
check(noSum?.version == "1.2", "tag without a leading v still parses")
check(noSum?.checksumURL == nil, "missing checksum is reported as nil, not invented")
check(UpdateLogic.parseRelease(nil) == nil, "nil payload is handled")
check(UpdateLogic.parseRelease("not json") == nil, "unexpected payload shape is handled")
check(UpdateLogic.parseRelease(["assets": []]) == nil, "missing tag means no update")

// MARK: parseReleaseList (the pre-release fallback)

let list: [[String: Any]] = [
    ["tag_name": "v2.0-beta", "prerelease": true, "draft": false,
     "assets": [["name": "Burndown-2.0.zip", "browser_download_url": "https://example.test/b.zip"]]],
    ["tag_name": "v1.5", "prerelease": false, "draft": false,
     "assets": [["name": "Burndown-1.5.zip", "browser_download_url": "https://example.test/s.zip"]]],
    ["tag_name": "v9.9", "draft": true,
     "assets": [["name": "Burndown-9.9.zip", "browser_download_url": "https://example.test/d.zip"]]],
]
check(UpdateLogic.parseReleaseList(list, allowPrerelease: false)?.version == "1.5",
      "stable-only picks the newest stable, skipping pre-release and draft")
check(UpdateLogic.parseReleaseList(list, allowPrerelease: true)?.version == "2.0-beta",
      "opting into pre-releases picks the newer beta")
check(UpdateLogic.parseReleaseList(list, allowPrerelease: true)?.version != "9.9",
      "drafts are never offered")
let onlyBeta: [[String: Any]] = [["tag_name": "v3.0", "prerelease": true,
    "assets": [["name": "Burndown-3.0.zip", "browser_download_url": "https://example.test/x.zip"]]]]
check(UpdateLogic.parseReleaseList(onlyBeta, allowPrerelease: false) == nil,
      "a beta-only project offers nothing to stable users")
check(UpdateLogic.parseReleaseList(onlyBeta, allowPrerelease: true)?.version == "3.0",
      "a beta-only project still updates users who accept betas")
check(UpdateLogic.parseReleaseList([], allowPrerelease: true) == nil, "an empty release list yields nil")
check(UpdateLogic.parseReleaseList("nope", allowPrerelease: true) == nil, "a non-list payload yields nil")

// MARK: parseChecksum

let shaLine = "f1598c8cd3d0630695055dce95bf3ec7e711d086ee1e80d73f657c4f7faf0081  dist/Burndown-1.0.zip\n"
check(UpdateLogic.parseChecksum(shaLine) == "f1598c8cd3d0630695055dce95bf3ec7e711d086ee1e80d73f657c4f7faf0081",
      "shasum line yields the digest")
check(UpdateLogic.parseChecksum("nonsense") == nil, "a non-checksum file yields nil")
check(UpdateLogic.parseChecksum("") == nil, "empty checksum file yields nil")
check(UpdateLogic.parseChecksum("abc  file.zip") == nil, "a too-short hex token is rejected")
let upper = "F1598C8CD3D0630695055DCE95BF3EC7E711D086EE1E80D73F657C4F7FAF0081  x.zip"
check(UpdateLogic.parseChecksum(upper) == upper.split(separator: " ")[0].lowercased(),
      "uppercase digests normalize to lowercase")

// MARK: dev-checkout detection

let devTree: Set<String> = ["/repo/Sources", "/repo/build.sh"]
check(UpdateLogic.isDevelopmentCheckout(bundlePath: "/repo/Burndown.app") { devTree.contains($0) },
      "a bundle beside Sources/ and build.sh is a dev checkout")
check(!UpdateLogic.isDevelopmentCheckout(bundlePath: "/Applications/Burndown.app") { devTree.contains($0) },
      "an installed app is not a dev checkout")
check(!UpdateLogic.isDevelopmentCheckout(bundlePath: "/repo/Burndown.app") { $0 == "/repo/Sources" },
      "Sources/ alone (no build.sh) is not enough to call it a dev checkout")

print(failures == 0 ? "ALL UPDATE TESTS PASSED" : "\(failures) UPDATE TEST(S) FAILED")
exit(failures == 0 ? 0 : 1)
