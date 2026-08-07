import Foundation

// On-disk cache for the full-history scan.
//
// The scan used to read EVERY session log in full, on every Insights open, and JSON-decode every
// line that looked interesting. On a working machine that is over a gigabyte of logs across more
// than a thousand files, so opening Insights meant waiting several seconds while a core burned,
// every single time, for an answer that had not changed since the last time it was asked.
//
// Almost none of that work is new: yesterday's logs cannot change. This remembers what each file
// contributed, keyed on its modification date and size, so a re-scan touches only the files that
// actually moved. A file that merely GREW is read from where the last scan stopped.
//
// It is a compact binary rather than JSON on purpose. A quarter of a million usage records is a
// few megabytes packed like this and roughly ten times that as JSON, and this file is written and
// re-read constantly. It is derived data: a corrupt or missing cache costs one slow scan, never a
// wrong number, so every failure path simply rebuilds.

/// One usage row as it sits in the cache. Project and title live on the file, not the row.
struct CachedRecord {
    let ts: Double            // seconds since 1970
    let model: String
    let input, output, cache5m, cache1h, cacheRead: Int
}

/// Everything one session log contributed, plus the stamps that say whether it is still valid.
struct CachedFile {
    let mod: Double           // modification date at the time of parsing
    let size: UInt64          // file size at the time of parsing
    let offset: UInt64        // bytes consumed, always at a line boundary
    let project: String       // resolved from the log's own cwd, not the encoded folder name
    let title: String         // the conversation's title
    let records: [CachedRecord]
}

enum ScanCache {
    /// Bumped whenever the format OR the meaning of a stored field changes. A cache written by a
    /// different version is discarded rather than misread.
    ///
    /// - 2: the "no folder recorded" project label changed wording. It is stored per file, so a
    ///   version 1 cache would have kept serving the old label forever.
    static let version: UInt32 = 2
    private static let magic: UInt32 = 0x42445343   // "BDSC"

    static var url: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/burndown/scan-cache.bin")
    }

    // MARK: Encoding

    static func encode(_ files: [String: CachedFile]) -> Data {
        // Strings repeat heavily (a handful of models, a handful of projects, one title per file),
        // so they are pooled and referenced by index.
        var pool: [String: UInt32] = [:]
        var strings: [String] = []
        func idx(_ s: String) -> UInt32 {
            if let i = pool[s] { return i }
            let i = UInt32(strings.count); pool[s] = i; strings.append(s); return i
        }

        var body = Data()
        body.reserveCapacity(files.values.reduce(0) { $0 + $1.records.count * 32 + 64 })
        var fileCount: UInt32 = 0
        for (path, f) in files {
            fileCount += 1
            append(&body, idx(path))
            append(&body, f.mod)
            append(&body, f.size)
            append(&body, f.offset)
            append(&body, idx(f.project))
            append(&body, idx(f.title))
            append(&body, UInt32(f.records.count))
            for r in f.records {
                append(&body, r.ts)
                append(&body, idx(r.model))
                append(&body, Int32(clamping: r.input))
                append(&body, Int32(clamping: r.output))
                append(&body, Int32(clamping: r.cache5m))
                append(&body, Int32(clamping: r.cache1h))
                append(&body, Int32(clamping: r.cacheRead))
            }
        }

        // The string table is written first but built while encoding the body, so it is assembled
        // here and the two are joined.
        var out = Data()
        append(&out, magic)
        append(&out, version)
        append(&out, UInt32(strings.count))
        for s in strings {
            let b = Array(s.utf8)
            append(&out, UInt32(b.count))
            out.append(contentsOf: b)
        }
        append(&out, fileCount)
        out.append(body)
        return out
    }

    // MARK: Decoding

    static func decode(_ data: Data) -> [String: CachedFile]? {
        var p = 0
        func u32() -> UInt32? { read(data, &p) }
        func u64() -> UInt64? { read(data, &p) }
        func dbl() -> Double? { read(data, &p) }
        func i32() -> Int32? { read(data, &p) }

        guard let m: UInt32 = u32(), m == magic, let v: UInt32 = u32(), v == version,
              let strCount: UInt32 = u32() else { return nil }
        var strings: [String] = []
        strings.reserveCapacity(Int(strCount))
        for _ in 0..<strCount {
            guard let len: UInt32 = u32(), p + Int(len) <= data.count else { return nil }
            guard let s = String(data: data.subdata(in: p..<(p + Int(len))), encoding: .utf8) else { return nil }
            strings.append(s); p += Int(len)
        }
        func str(_ i: UInt32) -> String? { Int(i) < strings.count ? strings[Int(i)] : nil }

        guard let fileCount: UInt32 = u32() else { return nil }
        var out: [String: CachedFile] = [:]
        out.reserveCapacity(Int(fileCount))
        for _ in 0..<fileCount {
            guard let pathI: UInt32 = u32(), let path = str(pathI),
                  let mod: Double = dbl(), let size: UInt64 = u64(), let offset: UInt64 = u64(),
                  let projI: UInt32 = u32(), let proj = str(projI),
                  let titleI: UInt32 = u32(), let title = str(titleI),
                  let n: UInt32 = u32() else { return nil }
            var recs: [CachedRecord] = []
            recs.reserveCapacity(Int(n))
            for _ in 0..<n {
                guard let ts: Double = dbl(), let mi: UInt32 = u32(), let model = str(mi),
                      let a: Int32 = i32(), let b: Int32 = i32(), let c: Int32 = i32(),
                      let d: Int32 = i32(), let e: Int32 = i32() else { return nil }
                recs.append(CachedRecord(ts: ts, model: model, input: Int(a), output: Int(b),
                                         cache5m: Int(c), cache1h: Int(d), cacheRead: Int(e)))
            }
            out[path] = CachedFile(mod: mod, size: size, offset: offset,
                                   project: proj, title: title, records: recs)
        }
        return out
    }

    // MARK: Disk

    static func load() -> [String: CachedFile] {
        guard let d = try? Data(contentsOf: url) else { return [:] }
        return decode(d) ?? [:]      // unreadable or an older format: rebuild rather than guess
    }

    static func save(_ files: [String: CachedFile]) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        // Written to a sibling and moved into place, so a crash mid-write cannot leave a
        // half-written cache that the next launch has to detect and discard.
        let tmp = url.appendingPathExtension("tmp")
        guard (try? encode(files).write(to: tmp)) != nil else { return }
        _ = try? FileManager.default.replaceItemAt(url, withItemAt: tmp)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    // MARK: Fixed-width helpers

    private static func append<T>(_ d: inout Data, _ v: T) {
        var x = v
        withUnsafeBytes(of: &x) { d.append(contentsOf: $0) }
    }
    private static func read<T>(_ d: Data, _ p: inout Int) -> T? {
        let n = MemoryLayout<T>.size
        guard p + n <= d.count else { return nil }
        let v = d.subdata(in: p..<(p + n)).withUnsafeBytes { $0.loadUnaligned(as: T.self) }
        p += n
        return v
    }
}
