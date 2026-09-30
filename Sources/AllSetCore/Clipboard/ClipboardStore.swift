import CoreGraphics
import Foundation
import Observation
import OSLog

/// One thing that was copied.
public struct ClipboardItem: Codable, Identifiable, Hashable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case text, link, image, files

        public var title: String {
            switch self {
            case .text: "Text"
            case .link: "Links"
            case .image: "Images"
            case .files: "Files"
            }
        }

        /// Words that find this kind of item in a search.
        var searchName: String {
            switch self {
            case .text: "text"
            case .link: "link url web"
            case .image: "image photo picture screenshot"
            case .files: "file files document"
            }
        }

        public var symbol: String {
            switch self {
            case .text: "text.alignleft"
            case .link: "link"
            case .image: "photo"
            case .files: "doc.on.doc"
            }
        }
    }

    public var id = UUID()
    public var kind: Kind
    /// The text, or the link's address.
    public var text: String?
    /// For images: a PNG in the clipboard's image folder.
    public var imageFile: String?
    public var imageSize: CGSize?
    public var fileURLs: [URL]?
    /// The app it was copied from.
    public var sourceBundleID: String?
    public var date = Date()
    public var isPinned = false

    public init(kind: Kind, text: String? = nil, imageFile: String? = nil, imageSize: CGSize? = nil,
                fileURLs: [URL]? = nil, sourceBundleID: String? = nil, date: Date = .now) {
        self.kind = kind
        self.text = text
        self.imageFile = imageFile
        self.imageSize = imageSize
        self.fileURLs = fileURLs
        self.sourceBundleID = sourceBundleID
        self.date = date
    }

    /// Text is a link when it's nothing but a web address.
    public static func text(_ string: String, sourceBundleID: String?) -> ClipboardItem {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let isLink = !trimmed.contains(where: \.isWhitespace)
            && (trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://"))
            && URL(string: trimmed)?.host != nil
        return ClipboardItem(kind: isLink ? .link : .text, text: isLink ? trimmed : string, sourceBundleID: sourceBundleID)
    }

    /// A single line to show in lists.
    public var preview: String {
        switch kind {
        case .text, .link:
            return (text ?? "").split(whereSeparator: \.isNewline).first.map(String.init)?
                .trimmingCharacters(in: .whitespaces) ?? ""
        case .image:
            return imageSize.map { "Image \(Int($0.width))×\(Int($0.height))" } ?? "Image"
        case .files:
            let names = (fileURLs ?? []).map(\.lastPathComponent)
            return names.count > 1 ? "\(names[0]) and \(names.count - 1) more" : names.first ?? "Files"
        }
    }

    /// Whether two items hold the same content, so copying something again
    /// moves it to the top instead of adding a duplicate.
    public func hasSameContent(as other: ClipboardItem) -> Bool {
        kind == other.kind && text == other.text && fileURLs == other.fileURLs
            && (kind != .image || imageFile == other.imageFile)
    }

    /// Every word of the query, in any order, ignoring case and accents.
    func matches(_ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        let haystack = [text, fileURLs?.map(\.lastPathComponent).joined(separator: " "), preview, kind.searchName]
            .compactMap { $0 }.joined(separator: " ")
        return SearchMatch.containsAll(query, in: haystack)
    }
}

public struct ClipboardSettings: Codable, Equatable, Sendable {
    public var isEnabled = true
    /// Unpinned items kept.
    public var historyLimit = 200
    /// After choosing an item, paste it into the app in front (needs Accessibility).
    public var pasteOnSelect = true
    public var pickerShortcut: Shortcut? = Shortcut(keyCode: 0x09, modifiers: [.control, .option], key: "V")
    /// Apps whose copies are never recorded.
    public var ignoredApps: [String] = ClipboardSettings.passwordManagers

    public static let passwordManagers = [
        "com.1password.1password", "com.agilebits.onepassword7", "com.bitwarden.desktop", "com.apple.keychainaccess",
        "com.apple.Passwords", "com.lastpass.LastPass", "com.dashlane.dashlanephonefinal", "in.sinew.Enpass-Desktop",
    ]

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case isEnabled, historyLimit, pasteOnSelect, pickerShortcut, ignoredApps
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = ClipboardSettings()
        isEnabled = (try? container.decodeIfPresent(Bool.self, forKey: .isEnabled)) ?? defaults.isEnabled
        historyLimit = (try? container.decodeIfPresent(Int.self, forKey: .historyLimit)) ?? defaults.historyLimit
        pasteOnSelect = (try? container.decodeIfPresent(Bool.self, forKey: .pasteOnSelect)) ?? defaults.pasteOnSelect
        pickerShortcut = container.contains(.pickerShortcut)
            ? (try? container.decode(Shortcut?.self, forKey: .pickerShortcut)) ?? nil
            : defaults.pickerShortcut
        ignoredApps = (try? container.decodeIfPresent([String].self, forKey: .ignoredApps)) ?? defaults.ignoredApps
    }

    // Written by hand so a removed shortcut is saved as null. Left out, it
    // would read back as missing and the default would return.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(historyLimit, forKey: .historyLimit)
        try container.encode(pasteOnSelect, forKey: .pasteOnSelect)
        try container.encode(pickerShortcut, forKey: .pickerShortcut)
        try container.encode(ignoredApps, forKey: .ignoredApps)
    }
}

/// Clipboard history, newest first, saved to Application Support with images
/// alongside.
@Observable @MainActor
public final class ClipboardStore {
    public private(set) var items: [ClipboardItem] = []
    public var settings: ClipboardSettings {
        didSet {
            guard settings != oldValue else { return }
            if settings.historyLimit != oldValue.historyLimit { trim() }
            save()
        }
    }

    @ObservationIgnored public let imageDirectory: URL
    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private var pendingSave: Task<Void, Never>?
    @ObservationIgnored private let log = Logger(subsystem: "com.pratik.allset", category: "clipboard")

    private struct Saved: Codable, Sendable {
        var settings: ClipboardSettings
        var items: [ClipboardItem]
    }

    public init(directory: URL? = nil) {
        let root = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AllSet/Clipboard", isDirectory: true)
        imageDirectory = root.appendingPathComponent("Images", isDirectory: true)
        fileURL = root.appendingPathComponent("history.json")
        try? FileManager.default.createDirectory(at: imageDirectory, withIntermediateDirectories: true)
        let saved = StoreFile.load(Saved.self, from: fileURL)
        settings = saved?.settings ?? ClipboardSettings()
        items = saved?.items ?? []
    }

    /// Adds a copy to the top, or moves an identical earlier copy there.
    public func add(_ item: ClipboardItem) {
        if let index = items.firstIndex(where: { $0.hasSameContent(as: item) }) {
            var existing = items.remove(at: index)
            existing.date = item.date
            existing.sourceBundleID = item.sourceBundleID ?? existing.sourceBundleID
            items.insert(existing, at: position(for: existing.date))
            // The new copy's image file duplicates the kept one.
            if let file = item.imageFile, file != existing.imageFile { deleteImage(file) }
        } else {
            items.insert(item, at: position(for: item.date))
        }
        trim()
        scheduleSave()
    }

    /// Newest first. A picture finishes saving a moment after it was copied,
    /// so it may land below something copied since.
    private func position(for date: Date) -> Int {
        items.firstIndex { $0.date <= date } ?? items.count
    }

    public func togglePin(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isPinned.toggle()
        scheduleSave()
    }

    public func remove(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items.remove(at: index)
        if let file = item.imageFile { deleteImage(file) }
        scheduleSave()
    }

    /// Clears everything except pinned items.
    public func clear() {
        for item in items where !item.isPinned {
            if let file = item.imageFile { deleteImage(file) }
        }
        items.removeAll { !$0.isPinned }
        scheduleSave()
    }

    /// Pinned items first, then the rest, newest first.
    public func search(_ query: String, kind: ClipboardItem.Kind? = nil) -> [ClipboardItem] {
        let matches = items.filter { (kind == nil || $0.kind == kind) && $0.matches(query) }
        return matches.filter(\.isPinned) + matches.filter { !$0.isPinned }
    }

    public func imageURL(_ item: ClipboardItem) -> URL? {
        item.imageFile.map { imageDirectory.appendingPathComponent($0) }
    }

    private func trim() {
        var unpinned = 0
        var kept: [ClipboardItem] = []
        for item in items {
            if item.isPinned {
                kept.append(item)
            } else if unpinned < settings.historyLimit {
                unpinned += 1
                kept.append(item)
            } else if let file = item.imageFile {
                deleteImage(file)
            }
        }
        items = kept
    }

    private func deleteImage(_ name: String) {
        try? FileManager.default.removeItem(at: imageDirectory.appendingPathComponent(name))
    }

    /// Every copy saves the history, which can run to megabytes of text:
    /// encoding and writing it happen on a background queue, off the main
    /// thread, so copying never stutters the notch or widgets.
    private func scheduleSave() {
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self else { return }
            let saved = Saved(settings: settings, items: items)
            let url = fileURL, log = log
            Self.writer.async { Self.write(saved, to: url, log: log) }
        }
    }

    /// Writes now, and returns once it's on disk (after any background write
    /// still queued, so an older one can't land on top), e.g. before quitting.
    public func save() {
        pendingSave?.cancel()
        let saved = Saved(settings: settings, items: items)
        let url = fileURL, log = log
        Self.writer.sync { Self.write(saved, to: url, log: log) }
    }

    /// One queue, so writes land in the order they were made.
    private nonisolated static let writer = DispatchQueue(label: "com.pratik.allset.clipboard.save", qos: .utility)

    private nonisolated static func write(_ saved: Saved, to url: URL, log: Logger) {
        do {
            try JSONEncoder().encode(saved).write(to: url, options: .atomic)
        } catch {
            log.error("Couldn't save clipboard history: \(error.localizedDescription, privacy: .public)")
        }
    }
}
