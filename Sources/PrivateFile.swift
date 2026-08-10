import Foundation

// Writing a file that is private from the moment it exists.
//
// The pattern everywhere in this app was: write the file, then chmod it to 0600. That leaves a
// window, however brief, in which a file holding an OAuth token, or the titles of every
// conversation on the machine, is readable by every process running as any user on the system.
// The window is small and the race is unlikely, but SECURITY.md promises "mode 600 inside a mode
// 700 directory" without qualification, and a promise about a file's permissions should hold for
// the whole life of the file rather than for all of it but the first instant.
//
// FileManager.createFile applies its attributes as the file is created, so there is no window at
// all. An existing file is truncated and rewritten, and its permissions are corrected on the way
// past in case an older version of this app left it readable.

/// Write `data` to `url` with mode 0600, private from the instant the file exists.
/// Returns false if the write failed, so callers that care can say so.
@discardableResult
func writePrivate(_ data: Data, to url: URL) -> Bool {
    let fm = FileManager.default
    try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                            attributes: [.posixPermissions: 0o700])
    let ok = fm.createFile(atPath: url.path, contents: data, attributes: [.posixPermissions: 0o600])
    // A file that already existed keeps whatever mode it had, including a permissive one written by
    // an older build, so it is corrected rather than assumed.
    if ok { try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path) }
    return ok
}
