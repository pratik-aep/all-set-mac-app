import CryptoKit
import Foundation

/// Export and restore of everything All Set keeps for a person: the files in
/// its data folder and its settings.
///
/// An archive is a folder:
///
///     manifest.json    format, date, app version, and every file's size and SHA-256
///     settings.plist   the app's preferences
///     data/…           the files, at the paths they have in the data folder
///
/// Left out unless asked for: clipboard history (it can hold anything that was
/// ever copied) and the rendered wallpaper library (large, and re-importable).
/// Never included: API keys and tokens, which stay in the Keychain.
///
/// Restoring is in two steps so no store is ever running on files that change
/// under it. `stage` checks the whole archive and copies it into the data
/// folder as a pending restore; `applyStaged`, called at launch before any
/// store reads a file, checks it again and swaps it in. What was there before
/// is moved to `.before-restore-<time>` in the same folder, not deleted, and a
/// swap that fails part-way is undone. Anything the archive doesn't carry
/// (clipboard history, the wallpaper library, when they were left out) stays
/// as it was.
public enum DataArchive {
    public static let format = 1

    public struct Options: Equatable, Sendable {
        public var includesClipboard = false
        public var includesWallpaperLibrary = false

        public init(includesClipboard: Bool = false, includesWallpaperLibrary: Bool = false) {
            self.includesClipboard = includesClipboard
            self.includesWallpaperLibrary = includesWallpaperLibrary
        }
    }

    public struct Manifest: Codable, Equatable, Sendable {
        public struct File: Codable, Equatable, Sendable {
            public var path: String
            public var size: Int
            public var sha256: String
        }

        public var format: Int
        public var created: Date
        public var appVersion: String
        public var includesClipboard: Bool
        public var includesWallpaperLibrary: Bool
        public var files: [File]

        public var totalBytes: Int { files.reduce(0) { $0 + $1.size } }
    }

    public enum Failure: Error, Equatable, CustomStringConvertible {
        case notAnArchive(String)
        case newerFormat(Int)
        case damaged([String])
        case destinationExists
        case couldNot(String)

        public var description: String {
            switch self {
            case .notAnArchive(let why): "This isn't an All Set backup: \(why)"
            case .newerFormat(let format): "This backup was made by a newer All Set (format \(format)). Update All Set to restore it."
            case .damaged(let problems):
                "This backup is damaged and wasn't restored: " + problems.prefix(3).joined(separator: "; ")
                    + (problems.count > 3 ? "; and \(problems.count - 3) more" : "")
            case .destinationExists: "Something is already there. Choose another name or place."
            case .couldNot(let why): why
            }
        }
    }

    /// The result of a restore applied at launch.
    public struct Applied {
        public var manifest: Manifest
        /// The preferences to put back, if the archive carried them.
        public var settings: [String: Any]?
        /// Where the data that was replaced now is.
        public var previous: URL
    }

    static let pendingName = ".pending-restore"
    static let previousPrefix = ".before-restore-"
    /// Preferences that describe this Mac's state right now, not the person's
    /// choices: restoring them elsewhere, or later, would be wrong.
    public static let machineStateKeys: Set<String> = ["screenshot.systemShortcutOffByAllSet", "wallpaper.still.source", "wallpaper.still.path"]

    // MARK: Export

    /// Writes an archive of `root` and `settings` to `destination`, which must
    /// not exist yet. Nothing in `root` is changed.
    @discardableResult
    public static func export(from root: URL, settings: [String: Any], to destination: URL, options: Options = Options(),
                              appVersion: String, now: Date = .now) throws -> Manifest {
        let manager = FileManager.default
        guard !manager.fileExists(atPath: destination.path) else { throw Failure.destinationExists }
        let working = destination.deletingLastPathComponent().appendingPathComponent(".\(destination.lastPathComponent)-\(UUID().uuidString)")
        do {
            try manager.createDirectory(at: working.appendingPathComponent("data"), withIntermediateDirectories: true)
            var files: [Manifest.File] = []
            for path in exportedPaths(in: root, options: options) {
                let source = root.appendingPathComponent(path)
                let copy = working.appendingPathComponent("data").appendingPathComponent(path)
                try manager.createDirectory(at: copy.deletingLastPathComponent(), withIntermediateDirectories: true)
                try manager.copyItem(at: source, to: copy)
                files.append(.init(path: path, size: try size(of: copy), sha256: try sha256(of: copy)))
            }
            let kept = settings.filter { !machineStateKeys.contains($0.key) && PropertyListSerialization.propertyList($0.value, isValidFor: .binary) }
            try PropertyListSerialization.data(fromPropertyList: kept, format: .binary, options: 0)
                .write(to: working.appendingPathComponent("settings.plist"))
            // To the second, as it's stored: the manifest handed back is the one on disk.
            let created = Date(timeIntervalSince1970: now.timeIntervalSince1970.rounded(.down))
            let manifest = Manifest(format: format, created: created, appVersion: appVersion, includesClipboard: options.includesClipboard,
                                    includesWallpaperLibrary: options.includesWallpaperLibrary, files: files)
            try encoder.encode(manifest).write(to: working.appendingPathComponent("manifest.json"))
            try manager.moveItem(at: working, to: destination)
            return manifest
        } catch {
            try? manager.removeItem(at: working)
            throw (error as? Failure) ?? Failure.couldNot("The backup couldn't be written: \(error.localizedDescription)")
        }
    }

    /// Relative paths of the files an export of `root` holds, sorted. Hidden
    /// top-level items (a pending or earlier restore) are never part of one.
    static func exportedPaths(in root: URL, options: Options) -> [String] {
        let base = root.resolvingSymlinksInPath().path
        guard let walker = FileManager.default.enumerator(at: URL(fileURLWithPath: base), includingPropertiesForKeys: [.isRegularFileKey]) else {
            return []
        }
        var paths: [String] = []
        for case let url as URL in walker {
            let path = String(url.resolvingSymlinksInPath().path.dropFirst(base.count + 1))
            let parts = path.split(separator: "/").map(String.init)
            guard let first = parts.first else { continue }
            let skipped = first.hasPrefix(".")
                || (!options.includesClipboard && first == "Clipboard")
                || (!options.includesWallpaperLibrary && parts.starts(with: ["Wallpaper", "Library"]))
            if skipped {
                walker.skipDescendants()
            } else if (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true, parts.last != ".DS_Store" {
                paths.append(path)
            }
        }
        return paths.sorted()
    }

    // MARK: Verify

    /// Reads an archive's manifest and checks every file against it. Throws
    /// unless the archive is whole.
    @discardableResult
    public static func verify(_ archive: URL) throws -> Manifest {
        guard let data = try? Data(contentsOf: archive.appendingPathComponent("manifest.json")) else {
            throw Failure.notAnArchive("it has no manifest")
        }
        guard let manifest = try? decoder.decode(Manifest.self, from: data) else {
            throw Failure.notAnArchive("its manifest can't be read")
        }
        guard manifest.format <= format else { throw Failure.newerFormat(manifest.format) }
        let dataFolder = archive.appendingPathComponent("data")
        var problems: [String] = []
        for file in manifest.files {
            // A path that would land outside the data folder is never followed.
            guard let url = ContainedPath.resolve(file.path, in: dataFolder) else {
                problems.append("\(file.path) points outside the backup")
                continue
            }
            guard FileManager.default.fileExists(atPath: url.path) else {
                problems.append("\(file.path) is missing")
                continue
            }
            if (try? size(of: url)) != file.size || (try? sha256(of: url)) != file.sha256 {
                problems.append("\(file.path) has changed")
            }
        }
        guard problems.isEmpty else { throw Failure.damaged(problems) }
        return manifest
    }

    // MARK: Restore

    /// Checks `archive` and copies it into `root` as a restore to apply at the
    /// next launch. Replaces one already waiting. Nothing else in `root` changes.
    @discardableResult
    public static func stage(_ archive: URL, in root: URL) throws -> Manifest {
        let manifest = try verify(archive)
        let manager = FileManager.default
        let pending = root.appendingPathComponent(pendingName)
        let working = root.appendingPathComponent("\(pendingName)-\(UUID().uuidString)")
        do {
            try manager.createDirectory(at: root, withIntermediateDirectories: true)
            try manager.copyItem(at: archive, to: working)
            try verify(working)
            try? manager.removeItem(at: pending)
            try manager.moveItem(at: working, to: pending)
            return manifest
        } catch {
            try? manager.removeItem(at: working)
            throw (error as? Failure) ?? Failure.couldNot("The backup couldn't be made ready: \(error.localizedDescription)")
        }
    }

    public static func hasStagedRestore(in root: URL) -> Bool {
        FileManager.default.fileExists(atPath: root.appendingPathComponent(pendingName).path)
    }

    /// Applies a staged restore, if there is one. Call before anything reads
    /// the data folder. Returns nil when nothing was waiting. On any failure the
    /// data folder is as it was, the pending restore is discarded, and the
    /// error says why.
    public static func applyStaged(in root: URL, now: Date = .now) throws -> Applied? {
        let manager = FileManager.default
        let pending = root.appendingPathComponent(pendingName)
        guard manager.fileExists(atPath: pending.path) else { return nil }
        defer { try? manager.removeItem(at: pending) }
        let manifest = try verify(pending)

        let stamp = ISO8601DateFormatter.string(from: now, timeZone: .gmt, formatOptions: [.withFullDate, .withTime, .withTimeZone])
            .replacingOccurrences(of: ":", with: "")
        let previous = root.appendingPathComponent(previousPrefix + stamp)
        var swapped: [(unit: String, hadOld: Bool)] = []
        do {
            try manager.createDirectory(at: previous, withIntermediateDirectories: true)
            for unit in units(of: manifest) {
                let live = root.appendingPathComponent(unit)
                let incoming = pending.appendingPathComponent("data").appendingPathComponent(unit)
                let aside = previous.appendingPathComponent(unit)
                let hadOld = manager.fileExists(atPath: live.path)
                try manager.createDirectory(at: aside.deletingLastPathComponent(), withIntermediateDirectories: true)
                if hadOld { try manager.moveItem(at: live, to: aside) }
                swapped.append((unit, hadOld))
                try manager.createDirectory(at: live.deletingLastPathComponent(), withIntermediateDirectories: true)
                try manager.moveItem(at: incoming, to: live)
            }
        } catch {
            // Undo, newest first: what came in goes, what was moved aside comes back.
            for (unit, hadOld) in swapped.reversed() {
                let live = root.appendingPathComponent(unit)
                try? manager.removeItem(at: live)
                if hadOld { try? manager.moveItem(at: previous.appendingPathComponent(unit), to: live) }
            }
            try? manager.removeItem(at: previous)
            throw Failure.couldNot("The restore couldn't be applied, so nothing was changed: \(error.localizedDescription)")
        }
        prunePrevious(in: root, keeping: 2)
        let settings = (try? Data(contentsOf: pending.appendingPathComponent("settings.plist")))
            .flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any] }
        return Applied(manifest: manifest, settings: settings, previous: previous)
    }

    /// What a restore swaps as a whole: each top-level item of the data folder
    /// the archive has files in, except inside `Wallpaper`, where the settings,
    /// the person's own videos and the library are separate, so restoring an
    /// archive without the library leaves the library alone.
    static func units(of manifest: Manifest) -> [String] {
        var units = Set<String>()
        for file in manifest.files {
            let parts = file.path.split(separator: "/").map(String.init)
            guard let first = parts.first else { continue }
            units.insert(first == "Wallpaper" && parts.count > 1 ? "Wallpaper/\(parts[1])" : first)
        }
        return units.sorted()
    }

    /// Earlier "before restore" folders, newest first.
    public static func previousData(in root: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix(previousPrefix) }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    private static func prunePrevious(in root: URL, keeping count: Int) {
        for old in previousData(in: root).dropFirst(count) {
            try? FileManager.default.removeItem(at: old)
        }
    }

    // MARK: Helpers

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func size(of url: URL) throws -> Int {
        try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
    }

    private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
