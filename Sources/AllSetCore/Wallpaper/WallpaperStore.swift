import Foundation
import Observation
import OSLog
import UniformTypeIdentifiers

/// What the live wallpaper shows.
public enum WallpaperSource: Codable, Hashable, Sendable {
    /// Generative art, animated.
    case art(ArtPiece)
    /// A photo, with slow movement.
    case photo(ImageSource)
    /// A looping video, by file name in the wallpaper videos folder.
    case video(String)
    /// A video in a wallpaper library outside All Set, by its id
    /// (`LibraryVideo.id`); it plays from where it lives.
    case library(String)
}

/// How a photo wallpaper moves.
public enum WallpaperMotion: String, Codable, CaseIterable, Identifiable, Sendable {
    case still
    case drift
    case breathe

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .still: "Still"
        case .drift: "Drift"
        case .breathe: "Breathe"
        }
    }
}

public struct WallpaperConfig: Codable, Equatable, Sendable {
    public var isEnabled = false
    public var source: WallpaperSource = .art(ArtPiece(style: .aurora, palette: .aurora))
    /// Frames per second for art.
    public var frameRate = 30
    /// Animation speed for art.
    public var speed = 1.0
    /// Draw art at full resolution. Off draws at half and scales up, which
    /// looks the same for soft styles and costs a quarter of the work.
    public var sharpArt = false
    public var motion: WallpaperMotion = .drift
    /// 0...0.6: darkens the wallpaper so icons and widgets stand out.
    public var dim = 0.0
    public var pauseOnBattery = false
    /// Stop animating while windows cover the whole desktop.
    public var pauseWhenCovered = true
    /// Also set a matching still as the system wallpaper, which Mission Control,
    /// Spaces and the lock screen show.
    public var matchSystemWallpaper = true
    /// System wallpapers from before All Set changed them, by screen name, so
    /// turning the live wallpaper off can put them back.
    public var originalWallpapers: [String: URL] = [:]

    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = WallpaperConfig()
        isEnabled = (try? container.decodeIfPresent(Bool.self, forKey: .isEnabled)) ?? defaults.isEnabled
        source = (try? container.decodeIfPresent(WallpaperSource.self, forKey: .source)) ?? defaults.source
        frameRate = (try? container.decodeIfPresent(Int.self, forKey: .frameRate)) ?? defaults.frameRate
        speed = (try? container.decodeIfPresent(Double.self, forKey: .speed)) ?? defaults.speed
        sharpArt = (try? container.decodeIfPresent(Bool.self, forKey: .sharpArt)) ?? defaults.sharpArt
        motion = (try? container.decodeIfPresent(WallpaperMotion.self, forKey: .motion)) ?? defaults.motion
        dim = (try? container.decodeIfPresent(Double.self, forKey: .dim)) ?? defaults.dim
        pauseOnBattery = (try? container.decodeIfPresent(Bool.self, forKey: .pauseOnBattery)) ?? defaults.pauseOnBattery
        pauseWhenCovered = (try? container.decodeIfPresent(Bool.self, forKey: .pauseWhenCovered)) ?? defaults.pauseWhenCovered
        matchSystemWallpaper = (try? container.decodeIfPresent(Bool.self, forKey: .matchSystemWallpaper)) ?? defaults.matchSystemWallpaper
        originalWallpapers = (try? container.decodeIfPresent([String: URL].self, forKey: .originalWallpapers)) ?? [:]
    }
}

/// The live wallpaper's settings and imported videos.
@Observable @MainActor
public final class WallpaperStore {
    public var config: WallpaperConfig { didSet { if config != oldValue { save() } } }
    /// Imported video file names, newest first.
    public private(set) var videos: [String] = []
    /// Videos in libraries outside All Set (`Library/catalog.json`, written by
    /// `scripts/wallpaper_library.py`), in catalog order.
    public private(set) var library: [LibraryVideo] = []
    /// Library folders by id, and whether each can be reached right now (a
    /// drive may be unplugged).
    public private(set) var libraryRoots: [String: WallpaperLibraryCatalog.Root] = [:]
    public private(set) var reachableRoots: Set<String> = []
    @ObservationIgnored private var libraryIndex: [String: Int] = [:]
    /// Ids whose converted copy is on disk, checked once when the catalog loads.
    @ObservationIgnored private var libraryCopies: Set<String> = []

    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored public let directory: URL
    @ObservationIgnored private let log = Logger(subsystem: "com.pratik.allset", category: "wallpaper")

    public init(directory: URL? = nil) {
        let root = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AllSet/Wallpaper", isDirectory: true)
        self.directory = root
        fileURL = root.appendingPathComponent("wallpaper.json")
        try? FileManager.default.createDirectory(at: root.appendingPathComponent("Videos"), withIntermediateDirectories: true)
        config = StoreFile.load(WallpaperConfig.self, from: fileURL) ?? WallpaperConfig()
        reloadVideos()
        reloadLibrary()
        // A video deleted outside All Set can't play; fall back to art.
        if case .video(let name) = config.source, !FileManager.default.fileExists(atPath: videoURL(name).path) {
            config.isEnabled = false
            config.source = WallpaperConfig().source
        }
    }

    public func set(_ source: WallpaperSource) {
        config.source = source
        config.isEnabled = true
    }

    public func videoURL(_ name: String) -> URL {
        directory.appendingPathComponent("Videos").appendingPathComponent(name)
    }

    // MARK: Library

    /// Where the catalog, thumbnails and the few converted copies live.
    public var libraryDirectory: URL { directory.appendingPathComponent("Library", isDirectory: true) }

    /// Reads the catalog off the main thread (a big library is a big file).
    public func reloadLibrary() {
        let file = libraryDirectory.appendingPathComponent("catalog.json")
        Task {
            let catalog = await Task.detached(priority: .utility) { () -> WallpaperLibraryCatalog? in
                guard let data = try? Data(contentsOf: file) else { return nil }
                return try? JSONDecoder().decode(WallpaperLibraryCatalog.self, from: data)
            }.value
            let items = (catalog?.items ?? []).filter { $0.status != .unsupported }
            let directory = libraryDirectory
            libraryCopies = Set(items.filter { video in
                video.playback.map { FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path) } ?? false
            }.map(\.id))
            #if DEBUG
            if hasDebugLibrary { return }
            #endif
            library = items
            libraryIndex = Dictionary(items.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
            libraryRoots = Dictionary((catalog?.roots ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            refreshLibraryReachability()
        }
    }

    /// Checks which library folders can be reached, for when a drive comes or goes.
    public func refreshLibraryReachability() {
        let reachable = Set(libraryRoots.values.filter { FileManager.default.fileExists(atPath: $0.path) }.map(\.id))
        if reachable != reachableRoots { reachableRoots = reachable }
    }

    #if DEBUG
    @ObservationIgnored private var hasDebugLibrary = false

    /// Replaces the library in memory (never on disk), for scale probes.
    public func debugReplaceLibrary(_ videos: [LibraryVideo]) {
        hasDebugLibrary = true
        library = videos
        libraryIndex = Dictionary(videos.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
    }
    #endif

    public func libraryVideo(_ id: String) -> LibraryVideo? {
        libraryIndex[id].map { library[$0] }
    }

    /// The file to play: the converted copy when there is one, otherwise the
    /// original where it lives. Nil when its drive isn't connected.
    public func libraryURL(_ id: String) -> URL? {
        guard let video = libraryVideo(id) else { return nil }
        if let playback = video.playback {
            let copy = libraryDirectory.appendingPathComponent(playback)
            if FileManager.default.fileExists(atPath: copy.path) { return copy }
        }
        guard let root = libraryRoots[video.root], reachableRoots.contains(video.root) else { return nil }
        let url = URL(fileURLWithPath: root.path).appendingPathComponent(video.file)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Whether it can play now, without touching the disk: its converted copy
    /// is known to exist, or its drive is connected. For drawing many cards
    /// (a file check per card on a USB drive stalls scrolling).
    public func canPlay(_ video: LibraryVideo) -> Bool {
        (video.playback != nil && libraryCopies.contains(video.id)) || reachableRoots.contains(video.root)
    }

    public func libraryThumbnailURL(_ video: LibraryVideo) -> URL? {
        video.thumbnail.map { libraryDirectory.appendingPathComponent($0) }
    }

    /// Copies videos in, so the wallpaper keeps working if the originals move.
    @discardableResult
    public func importVideos(from urls: [URL]) -> [String] {
        let imported = urls.filter(Self.isVideo).compactMap { url -> String? in
            let name = UUID().uuidString + "." + url.pathExtension.lowercased()
            do {
                try FileManager.default.copyItem(at: url, to: videoURL(name))
                return name
            } catch {
                log.error("Couldn't import \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
        reloadVideos()
        return imported
    }

    public func deleteVideo(_ name: String) {
        try? FileManager.default.removeItem(at: videoURL(name))
        if config.source == .video(name) {
            config.isEnabled = false
            config.source = WallpaperConfig().source
        }
        reloadVideos()
    }

    public nonisolated static func isVideo(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .movie) ?? false
    }

    /// The folder videos live in, for downloads to land in.
    public var videosFolder: URL { directory.appendingPathComponent("Videos") }

    /// Picks up files that arrived in the videos folder, like downloaded aerials.
    public func reloadVideos() {
        let folder = directory.appendingPathComponent("Videos")
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.creationDateKey])) ?? []
        videos = urls.filter(Self.isVideo)
            .sorted {
                ((try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast)
                    > ((try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast)
            }
            .map(\.lastPathComponent)
    }

    private func save() {
        do {
            try JSONEncoder().encode(config).write(to: fileURL, options: .atomic)
        } catch {
            log.error("Couldn't save wallpaper settings: \(error.localizedDescription, privacy: .public)")
        }
    }
}
