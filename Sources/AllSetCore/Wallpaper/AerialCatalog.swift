import AVFoundation
import Foundation
import Observation
import OSLog

/// One of Apple's aerial videos: the drone and space footage behind the
/// Apple TV and macOS screen savers.
public struct Aerial: Codable, Hashable, Identifiable, Sendable {
    public enum Category: String, Codable, CaseIterable, Identifiable, Sendable {
        case landscapes, cities, underwater, space

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .landscapes: "Landscapes"
            case .cities: "Cities"
            case .underwater: "Underwater"
            case .space: "Space"
            }
        }

        public var symbol: String {
            switch self {
            case .landscapes: "mountain.2.fill"
            case .cities: "building.2.fill"
            case .underwater: "fish.fill"
            case .space: "globe.americas.fill"
            }
        }
    }

    public enum Quality: String, Codable, CaseIterable, Identifiable, Sendable {
        case hd, uhd

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .hd: "HD, about 160 MB each"
            case .uhd: "4K, about 320 MB each"
            }
        }
    }

    public var id: String
    public var name: String
    public var category: Category
    public var hdURL: URL
    public var uhdURL: URL

    public func url(_ quality: Quality) -> URL {
        quality == .hd ? hdURL : uhdURL
    }

    /// The file it's saved as among the wallpaper videos.
    public func fileName(_ quality: Quality) -> String {
        "aerial-\(id)-\(quality.rawValue).mov"
    }
}

/// Apple's list of aerials, loaded from Apple's server, with previews and downloads.
@Observable @MainActor
public final class AerialCatalog {
    public private(set) var aerials: [Aerial] = []
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?
    /// Downloads in progress: fraction done, by aerial ID.
    public private(set) var downloads: [String: Double] = [:]

    /// Apple's manifest: a tar holding entries.json.
    static let manifestURL = URL(string: "https://sylvan.apple.com/Aerials/resources-16.tar")!

    @ObservationIgnored private let cacheDirectory: URL
    @ObservationIgnored private var tasks: [String: URLSessionDownloadTask] = [:]
    @ObservationIgnored private let log = Logger(subsystem: "com.pratik.allset", category: "aerials")

    public init(cacheDirectory: URL? = nil) {
        self.cacheDirectory = cacheDirectory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AllSet/Aerials", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.cacheDirectory, withIntermediateDirectories: true)
    }

    private var manifestFile: URL { cacheDirectory.appendingPathComponent("entries.json") }

    /// Loads the list: from the cache when it's under a week old, else from Apple.
    public func load() async {
        guard aerials.isEmpty, !isLoading else { return }
        let age = (try? manifestFile.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            .map { -$0.timeIntervalSinceNow } ?? .infinity
        if age < 7 * 86_400, let data = try? Data(contentsOf: manifestFile), let list = try? Self.decode(data), !list.isEmpty {
            aerials = list
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let (tar, response) = try await URLSession.shared.data(from: Self.manifestURL)
            guard (response as? HTTPURLResponse)?.statusCode == 200, let entries = Self.file(named: "entries.json", inTar: tar) else {
                throw URLError(.badServerResponse)
            }
            aerials = try Self.decode(entries)
            try? entries.write(to: manifestFile, options: .atomic)
        } catch {
            // An old list beats none.
            if let data = try? Data(contentsOf: manifestFile), let list = try? Self.decode(data) {
                aerials = list
            } else {
                errorMessage = "Apple's aerial list couldn't be loaded. Check your connection and try again."
                log.error("Aerial list failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    public func retry() async {
        errorMessage = nil
        await load()
    }

    // MARK: Previews

    /// A still from the video, cached; only the bytes around that moment are downloaded.
    public func preview(for aerial: Aerial) async -> CGImage? {
        let file = cacheDirectory.appendingPathComponent("\(aerial.id).jpg")
        if let source = CGImageSourceCreateWithURL(file as CFURL, nil),
           let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            return image
        }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: aerial.hdURL))
        generator.maximumSize = CGSize(width: 640, height: 640)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 4, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 4, preferredTimescale: 600)
        guard let (image, _) = try? await generator.image(at: CMTime(seconds: 12, preferredTimescale: 600)) else { return nil }
        if let destination = CGImageDestinationCreateWithURL(file as CFURL, "public.jpeg" as CFString, 1, nil) {
            CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
            CGImageDestinationFinalize(destination)
        }
        return image
    }

    // MARK: Downloads

    public func isDownloading(_ aerial: Aerial) -> Bool { downloads[aerial.id] != nil }

    /// Downloads the video into `folder`, returning its file name there.
    public func download(_ aerial: Aerial, quality: Aerial.Quality, into folder: URL) async throws -> String {
        let name = aerial.fileName(quality)
        let destination = folder.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: destination.path) { return name }
        guard tasks[aerial.id] == nil else { throw CancellationError() }
        downloads[aerial.id] = 0
        defer {
            downloads[aerial.id] = nil
            tasks[aerial.id] = nil
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let task = URLSession.shared.downloadTask(with: aerial.url(quality)) { temporary, response, error in
                // The temporary file is gone once this returns, so move it now.
                if let error {
                    continuation.resume(throwing: error)
                } else if let temporary, (response as? HTTPURLResponse)?.statusCode == 200 {
                    do {
                        try? FileManager.default.removeItem(at: destination)
                        try FileManager.default.moveItem(at: temporary, to: destination)
                        continuation.resume()
                    } catch {
                        continuation.resume(throwing: error)
                    }
                } else {
                    continuation.resume(throwing: URLError(.badServerResponse))
                }
            }
            tasks[aerial.id] = task
            task.resume()
            let id = aerial.id
            Task { [weak self] in
                while task.state == .running {
                    self?.downloads[id] = task.progress.fractionCompleted
                    try? await Task.sleep(for: .milliseconds(250))
                }
            }
        }
        return name
    }

    public func cancelDownload(_ aerial: Aerial) {
        tasks[aerial.id]?.cancel()
    }

    // MARK: Reading Apple's files

    nonisolated static func decode(_ data: Data) throws -> [Aerial] {
        struct Manifest: Decodable {
            struct Asset: Decodable {
                var id: String
                var accessibilityLabel: String?
                var categories: [String]?
                var urlHD: String?
                var url4K: String?

                enum CodingKeys: String, CodingKey {
                    case id, accessibilityLabel, categories
                    case urlHD = "url-1080-SDR"
                    case url4K = "url-4K-SDR"
                }
            }
            struct Group: Decodable {
                var id: String
                var localizedNameKey: String
            }
            var assets: [Asset]
            var categories: [Group]?
        }
        let manifest = try JSONDecoder().decode(Manifest.self, from: data)
        let categories = Dictionary((manifest.categories ?? []).map { ($0.id, $0.localizedNameKey) }, uniquingKeysWith: { first, _ in first })
        return manifest.assets.compactMap { asset in
            guard let hd = asset.urlHD.flatMap(URL.init(string:)) else { return nil }
            let key = asset.categories?.first.flatMap { categories[$0] }?.lowercased() ?? ""
            let category: Aerial.Category = key.contains("space") ? .space
                : key.contains("cit") ? .cities
                : key.contains("underwater") ? .underwater
                : .landscapes
            return Aerial(id: asset.id, name: asset.accessibilityLabel ?? "Aerial", category: category,
                          hdURL: hd, uhdURL: asset.url4K.flatMap(URL.init(string:)) ?? hd)
        }
    }

    /// A file's contents from an uncompressed tar archive.
    nonisolated static func file(named name: String, inTar tar: Data) -> Data? {
        let bytes = [UInt8](tar)
        var offset = 0
        while offset + 512 <= bytes.count {
            let header = bytes[offset..<offset + 512]
            // Two empty blocks end the archive.
            if header.allSatisfy({ $0 == 0 }) { return nil }
            func text(_ range: Range<Int>) -> String {
                let field = bytes[(offset + range.lowerBound)..<(offset + range.upperBound)]
                return String(decoding: field.prefix { $0 != 0 }, as: UTF8.self)
            }
            let prefix = text(345..<500)
            let entryName = (prefix.isEmpty ? "" : prefix + "/") + text(0..<100)
            let size = Int(text(124..<136).trimmingCharacters(in: .whitespaces), radix: 8) ?? 0
            let dataStart = offset + 512
            if (entryName as NSString).lastPathComponent == name, dataStart + size <= bytes.count {
                return Data(bytes[dataStart..<dataStart + size])
            }
            offset = dataStart + (size + 511) / 512 * 512
        }
        return nil
    }
}
