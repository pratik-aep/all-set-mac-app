import Foundation
import OSLog

/// A theme being tried on the desktop, written down before the desktop changes so
/// that quitting or a crash mid-trial can put the real desktop back.
public struct PendingPreview: Codable, Equatable, Sendable {
    public var setID: String
    public var before: DesktopSnapshot
    public var startedAt: Date

    public init(setID: String, before: DesktopSnapshot, startedAt: Date = .now) {
        self.setID = setID
        self.before = before
        self.startedAt = startedAt
    }
}

/// The desktop from before the last whole-desktop change (a theme, a wallpaper,
/// turning a theme off), kept on disk so it can be brought back after the Undo
/// offer has gone, or after a relaunch.
public struct PreviousDesktop: Codable, Equatable, Sendable {
    /// What happened, in words: "Seven went on", "New wallpaper".
    public var change: String
    public var before: DesktopSnapshot
    public var date: Date

    public init(change: String, before: DesktopSnapshot, date: Date = .now) {
        self.change = change
        self.before = before
        self.date = date
    }
}

/// Durable records of desktop changes. Writes are atomic and read back before
/// they count, so nothing destructive starts on a record that didn't stick.
@MainActor
public final class DesktopJournal {
    private let previewURL: URL
    private let previousURL: URL
    private let log = Logger(subsystem: "com.pratik.allset", category: "desktop")

    public nonisolated static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AllSet", isDirectory: true)
    }

    public init(directory: URL = DesktopJournal.defaultDirectory) {
        previewURL = directory.appendingPathComponent("desktop-preview.json")
        previousURL = directory.appendingPathComponent("previous-desktop.json")
    }

    // MARK: Preview

    /// Records a preview about to start. False if it couldn't be written and read
    /// back: the caller must not change the desktop then.
    @discardableResult
    public func beginPreview(_ preview: PendingPreview) -> Bool {
        write(preview, to: previewURL)
    }

    /// The preview has ended (kept or gone back): nothing to recover.
    public func endPreview() {
        try? FileManager.default.removeItem(at: previewURL)
    }

    /// A preview that never ended: the app quit or crashed during it.
    public var pendingPreview: PendingPreview? {
        StoreFile.load(PendingPreview.self, from: previewURL)
    }

    // MARK: Previous desktop

    @discardableResult
    public func remember(_ previous: PreviousDesktop) -> Bool {
        write(previous, to: previousURL)
    }

    public var previous: PreviousDesktop? {
        StoreFile.load(PreviousDesktop.self, from: previousURL)
    }

    // MARK: Writing

    private func write<Value: Codable & Equatable>(_ value: Value, to url: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            // Default date coding, matching `StoreFile.load`, which reads these back.
            try JSONEncoder().encode(value).write(to: url, options: .atomic)
            guard try JSONDecoder().decode(Value.self, from: Data(contentsOf: url)) == value else {
                log.error("\(url.lastPathComponent, privacy: .public) didn't read back the same")
                return false
            }
            return true
        } catch {
            log.error("Couldn't write \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
