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
