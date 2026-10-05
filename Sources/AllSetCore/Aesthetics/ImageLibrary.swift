import AppKit
import ImageIO
import Observation
import OSLog
import UniformTypeIdentifiers

/// Where a photo widget's image comes from.
public enum ImageSource: Codable, Hashable, Sendable {
    /// Generated art from the built-in library.
    case art(ArtPiece)
    /// A photo from the online library (Unsplash photos served by Picsum).
    case web(WebPhoto)
    /// A picture the user imported, stored in All Set's own folder by file name.
    case file(String)
    /// Original artwork shipped with the app; available without a download.
    case bundled(String)
}

/// An online photo: from Picsum (Unsplash photos, free to use) when `provider`
/// is nil, or from an Openverse search (Creative Commons photos).
public struct WebPhoto: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var author: String
    public var width: Int
    public var height: Int
    /// "openverse" for search results; nil for Picsum.
    public var provider: String?
    public var imageURLString: String?
    public var thumbnailURLString: String?
    /// e.g. "CC BY-SA 2.0", shown as attribution.
    public var license: String?
    public var title: String?
    /// Where an Openverse photo lives: "wordpress", "rawpixel", "flickr"...
    public var origin: String?

    public init(id: String, author: String, width: Int, height: Int, provider: String? = nil,
                imageURLString: String? = nil, thumbnailURLString: String? = nil, license: String? = nil,
                title: String? = nil, origin: String? = nil) {
        self.id = id
        self.author = author
        self.width = width
        self.height = height
        self.provider = provider
        self.imageURLString = imageURLString
        self.thumbnailURLString = thumbnailURLString
        self.license = license
        self.title = title
        self.origin = origin
    }

    /// A small version for grids. Taken straight from the photo's own site
    /// where it offers sizes, which spares Openverse's daily thumbnail limit.
    public func thumbnailURL(side: Int = 240) -> URL {
        if let direct = Self.resized(imageURLString, origin: origin, small: true) { return direct }
        return thumbnailURLString.flatMap(URL.init(string:)) ?? Self.picsum(id, side, side)
    }

    /// Openverse's own thumbnail, for when the site's small version fails.
    public var fallbackThumbnailURL: URL? {
        thumbnailURLString.flatMap(URL.init(string:))
    }

    /// Picsum scales on its server; other sources give a large version, which
    /// is scaled down after downloading.
    public var displayURL: URL {
        if let large = Self.resized(imageURLString, origin: origin, small: false) { return large }
        if let url = imageURLString.flatMap(URL.init(string:)) { return url }
        let width = 2400
        let height = max(Int(Double(width) * Double(self.height) / Double(max(self.width, 1))), 1)
        return Self.picsum(id, width, height)
    }

    /// Picsum's URL for a photo; the id is escaped, since it comes from a server.
    private static func picsum(_ id: String, _ width: Int, _ height: Int) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "picsum.photos"
        components.path = "/id/\(id)/\(width)/\(height)"
        return components.url ?? URL(fileURLWithPath: "/")
    }

    /// Other sizes of the same picture, where the site names them predictably.
    static func resized(_ urlString: String?, origin: String?, small: Bool) -> URL? {
        guard let urlString, let origin else { return nil }
        switch origin {
        case "wordpress":
            // "…-2048x1365.jpg": WordPress keeps a 768-wide copy of every photo.
            guard small, let match = urlString.firstMatch(of: /-(\d+)x(\d+)\.(jpe?g|png|webp)$/),
                  let width = Double(match.1), let height = Double(match.2), width > 0 else { return nil }
            let smallHeight = Int((768 * height / width).rounded())
            return URL(string: urlString.replacingCharacters(in: match.range, with: "-768x\(smallHeight).\(match.3)"))
        case "rawpixel":
            // "…/editor_1024/…" also comes as image_600 and image_1300.
            guard urlString.contains("/editor_1024/") else { return nil }
            return URL(string: urlString.replacingOccurrences(of: "/editor_1024/", with: small ? "/image_600/" : "/image_1300/"))
        case "flickr":
            // Flickr's size letters: n is 320 px, b is 1024.
            guard small, let match = urlString.firstMatch(of: /_[a-z]\.jpg$/) else { return nil }
            return URL(string: urlString.replacingCharacters(in: match.range, with: "_n.jpg"))
        default:
            return nil
        }
    }

    /// "Photo by X" plus the license where there is one; a Wallhaven
    /// wallpaper by its size, since the uploader rarely made it.
    public var credit: String {
        if provider == "wallhaven" { return width > 0 ? "\(width) × \(height) · Wallhaven" : "Wallhaven" }
        return [author, license].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// Where the picture came from, to credit it or find its creator.
    public var pageURL: URL? {
        switch provider {
        case "wallhaven": Wallhaven.pageURL(id: id)
        case "openverse": URL(string: "https://openverse.org/image/\(id)")
        default: nil
        }
    }

    var cacheName: String { "\(provider ?? "picsum")-\(id).jpg" }
}

/// The photos behind photo widgets: the online library, the user's imports,
/// and a cache so pictures load instantly (and offline) after the first time.
@Observable @MainActor
public final class ImageLibrary {
    public private(set) var webPhotos: [WebPhoto] = []
    public private(set) var isLoadingWebPhotos = false
    public private(set) var hasMoreWebPhotos = true
    public private(set) var webPhotosError: String?
    /// File names of imported pictures, newest first.
    public private(set) var userImages: [String] = []

    @ObservationIgnored private var nextPage = 1
    /// Whole photos (a wallpaper, a big widget), limited by decoded bytes:
    /// one screen-sized photo is 20–40 MB, so a count alone isn't a limit.
    @ObservationIgnored private var memoryCache = CostCache<ImageSource, NSImage>(costLimit: 160 << 20, countLimit: 40)
    /// Smaller copies for small places (a widget, a print), by longest side.
    @ObservationIgnored private var smallCache = CostCache<SizedSource, NSImage>(costLimit: 96 << 20, countLimit: 120)
    @ObservationIgnored private var smallLoading: [SizedSource: Task<NSImage?, Never>] = [:]

    private struct SizedSource: Hashable {
        let source: ImageSource
        let pixels: Int
    }

    /// Sizes are rounded up to one of these, so similar sizes share a copy.
    nonisolated static let buckets = [256, 512, 768, 1024, 1536, 2048]

    nonisolated static func pixelBucket(_ pixels: Int) -> Int {
        buckets.first { $0 >= pixels } ?? 0
    }
    /// Downloads in progress, so several widgets showing one photo share one.
    @ObservationIgnored private var loading: [ImageSource: Task<NSImage?, Never>] = [:]
    @ObservationIgnored private let userDirectory: URL
    @ObservationIgnored private let cacheDirectory: URL
    @ObservationIgnored private let log = Logger(subsystem: "com.pratik.allset", category: "images")

    public init(userDirectory: URL? = nil, cacheDirectory: URL? = nil) {
        let fileManager = FileManager.default
        self.userDirectory = userDirectory ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AllSet/Images", isDirectory: true)
        self.cacheDirectory = cacheDirectory ?? fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AllSet/Photos", isDirectory: true)
        let screenSpace = NSScreen.main?.colorSpace?.cgColorSpace
        Self.displaySpace.withLock { $0 = screenSpace }
        try? fileManager.createDirectory(at: self.userDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: self.cacheDirectory, withIntermediateDirectories: true)
        reloadUserImages()
    }

    // MARK: Online library

    public func loadMoreWebPhotos() {
        guard !isLoadingWebPhotos, hasMoreWebPhotos else { return }
        isLoadingWebPhotos = true
        webPhotosError = nil
        let page = nextPage
        Task {
            defer { isLoadingWebPhotos = false }
            do {
                let url = URL(string: "https://picsum.photos/v2/list?page=\(page)&limit=60")!
                let (data, _) = try await URLSession.shared.data(from: url)
                let photos = try Self.decodePhotoList(data)
                hasMoreWebPhotos = !photos.isEmpty
                webPhotos += photos.filter { photo in !webPhotos.contains { $0.id == photo.id } }
                nextPage = page + 1
            } catch {
                webPhotosError = error.localizedDescription
            }
        }
    }

    nonisolated static func decodePhotoList(_ data: Data) throws -> [WebPhoto] {
        struct Entry: Decodable {
            var id: String
            var author: String
            var width: Int
            var height: Int
        }
        return try JSONDecoder().decode([Entry].self, from: data).map {
            WebPhoto(id: $0.id, author: $0.author, width: $0.width, height: $0.height)
        }
    }

    // MARK: Imported pictures

    /// Copies pictures (or every picture in dropped folders) into All Set's
    /// folder, scaled down so a big camera file doesn't sit around at full size.
    @discardableResult
    public func importImages(from urls: [URL]) -> [String] {
        var files: [URL] = []
        for url in urls {
            var isDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            if isDirectory.boolValue {
                let contents = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
                files += contents.filter(Self.isImage).sorted { $0.lastPathComponent < $1.lastPathComponent }.prefix(100)
            } else if Self.isImage(url) {
                files.append(url)
            }
        }
        let imported = files.compactMap { url -> String? in
            let name = UUID().uuidString + ".jpg"
            guard Self.writeScaledJPEG(from: url, to: userDirectory.appendingPathComponent(name), maxPixels: 3200) else {
                log.error("Couldn't import \(url.lastPathComponent, privacy: .public)")
                return nil
            }
            return name
        }
        reloadUserImages()
        return imported
    }

    public func deleteUserImage(_ name: String) {
        try? FileManager.default.removeItem(at: userDirectory.appendingPathComponent(name))
        memoryCache.removeValue(forKey: .file(name))
        smallCache.removeAll { $0.source == .file(name) }
        reloadUserImages()
    }

    private func reloadUserImages() {
        let urls = (try? FileManager.default.contentsOfDirectory(at: userDirectory, includingPropertiesForKeys: [.creationDateKey])) ?? []
        userImages = urls
            .filter(Self.isImage)
            .sorted {
                let first = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let second = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return first > second
            }
            .map(\.lastPathComponent)
    }

    public func userImageURL(_ name: String) -> URL {
        userDirectory.appendingPathComponent(name)
    }

    #if DEBUG
    /// What the caches hold, for probes: images and decoded megabytes.
    public var debugCacheReport: String {
        let full = memoryCache.totalCost
        let small = smallCache.totalCost
        return String(format: "photos %d (%.0f MB), small copies %d (%.0f MB)", memoryCache.count, Double(full) / 1_048_576,
                      smallCache.count, Double(small) / 1_048_576)
    }
    #endif

    /// A small copy of a picture file anywhere (a wallpaper library's
    /// thumbnails), decoded off the main thread and kept in the same
    /// byte-limited cache as photos, so it's released the same way.
    public func thumbnail(at url: URL, maxPixels: Int) async -> NSImage? {
        let key = Self.thumbnailKey(url, maxPixels)
        if let cached = smallCache.value(forKey: key) { return cached }
        if let running = smallLoading[key] { return await running.value }
        let pixels = key.pixels
        let task = Task<NSImage?, Never> {
            await Task.detached(priority: .userInitiated) { Self.thumbnail(of: url, maxPixels: pixels) }.value
        }
        smallLoading[key] = task
        let image = await task.value
        smallLoading[key] = nil
        if let image { smallCache.insert(image, forKey: key, cost: image.decodedByteCount) }
        return image
    }

    /// The thumbnail if it's already in memory, to draw at once.
    public func cachedThumbnail(at url: URL, maxPixels: Int) -> NSImage? {
        smallCache.value(forKey: Self.thumbnailKey(url, maxPixels))
    }

    private static func thumbnailKey(_ url: URL, _ maxPixels: Int) -> SizedSource {
        // "@" keeps these apart from imported pictures, which are named plainly.
        SizedSource(source: .file("@" + url.path), pixels: max(pixelBucket(maxPixels), buckets[0]))
    }

    /// Lets go of cached pictures down to `fraction` of each cache's limit:
    /// 0 empties them. Pictures on screen stay on screen (their views hold
    /// them); only a later look may decode again.
    public func trimCaches(to fraction: Double) {
        memoryCache.trim(toCost: Int(Double(memoryCache.costLimit) * fraction))
        smallCache.trim(toCost: Int(Double(smallCache.costLimit) * fraction))
    }

    // MARK: Loading

    /// The image if it's already in memory, for drawing it at once without a fade.
    public func cachedImage(for source: ImageSource, maxPixels: Int? = nil) -> NSImage? {
        guard let maxPixels, Self.pixelBucket(maxPixels) > 0 else { return memoryCache.value(forKey: source) }
        let wanted = Self.pixelBucket(maxPixels)
        // The size asked for or a larger copy, then the whole photo, then a
        // smaller copy to show until the right one loads.
        for bucket in Self.buckets where bucket >= wanted {
            if let image = smallCache.value(forKey: SizedSource(source: source, pixels: bucket)) { return image }
        }
        if let whole = memoryCache.value(forKey: source) { return whole }
        for bucket in Self.buckets.reversed() where bucket < wanted {
            if let image = smallCache.value(forKey: SizedSource(source: source, pixels: bucket)) { return image }
        }
        return nil
    }

    /// A copy no bigger than `maxPixels` on its longest side, for showing a
    /// photo small: decoding a full-size photo for a widget holds tens of
    /// megabytes to draw a few hundred pixels.
    public func image(for source: ImageSource, maxPixels: Int) async -> NSImage? {
        let bucket = Self.pixelBucket(maxPixels)
        guard bucket > 0 else { return await image(for: source) }
        let key = SizedSource(source: source, pixels: bucket)
        if let cached = smallCache.value(forKey: key) { return cached }
        if let running = smallLoading[key] { return await running.value }
        let task = Task<NSImage?, Never> {
            guard await self.image(for: source) != nil, let file = fileURL(for: source) else { return nil }
            // The full image stays out of memory; only the small copy is kept.
            memoryCache.removeValue(forKey: source)
            return await Task.detached(priority: .userInitiated) { Self.thumbnail(of: file, maxPixels: bucket) }.value
        }
        smallLoading[key] = task
        let small = await task.value
        smallLoading[key] = nil
        if let small {
            smallCache.insert(small, forKey: key, cost: small.decodedByteCount)
        }
        return small
    }

    private nonisolated static func thumbnail(of file: URL, maxPixels: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let decoded = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let image = displayReady(decoded)
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }

    /// The screen's color space, set on launch; photos are decoded into it.
    private nonisolated static let displaySpace = OSAllocatedUnfairLock<CGColorSpace?>(initialState: nil)

    /// Redrawn once in the screen's colors and the pixel layout Core Animation
    /// keeps (32-bit BGRA, premultiplied), so drawing it later is a plain copy
    /// instead of a color conversion every time a widget redraws.
    public nonisolated static func displayReady(_ image: CGImage) -> CGImage {
        let space = displaySpace.withLock { $0 } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return image }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage() ?? image
    }

    /// The image for a photo or file source, from memory, disk or the network.
    /// Nil for art, which is drawn rather than loaded.
    public func image(for source: ImageSource) async -> NSImage? {
        if let cached = memoryCache.value(forKey: source) { return cached }
        if let running = loading[source] { return await running.value }
        let task = Task { await load(source) }
        loading[source] = task
        let image = await task.value
        loading[source] = nil
        if let image {
            memoryCache.insert(image, forKey: source, cost: image.decodedByteCount)
        }
        return image
    }

    /// Reads, re-encodes and decodes off the main thread; only wrapping the
    /// finished picture happens here.
    private func load(_ source: ImageSource) async -> NSImage? {
        let image: NSImage?
        switch source {
        case .art:
            return nil
        case .file(let name):
            image = await Self.decoded(userDirectory.appendingPathComponent(name))
        case .bundled(let name):
            guard let url = Self.bundledURL(name) else { return nil }
            image = await Self.decoded(url)
        case .web(let photo):
            let file = cacheDirectory.appendingPathComponent(photo.cacheName)
            if let cached = await Self.decoded(file) {
                image = cached
            } else {
                do {
                    let (data, response) = try await URLSession.shared.data(from: photo.displayURL)
                    // An error page isn't a photo: never cache one as if it were.
                    guard (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true,
                          CGImageSourceCreateWithData(data as CFData, nil).map({ CGImageSourceGetCount($0) > 0 }) == true else {
                        log.error("Photo \(photo.id, privacy: .public) didn't come back as an image")
                        return nil
                    }
                    // Originals can be huge; keep a screen-sized copy.
                    let saved = await Task.detached(priority: .userInitiated) {
                        if Self.writeScaledJPEG(from: data, to: file, maxPixels: 3200) { return true }
                        do {
                            try data.write(to: file, options: .atomic)
                            return true
                        } catch {
                            return false
                        }
                    }.value
                    if !saved { log.error("Couldn't cache photo \(photo.id, privacy: .public)") }
                    image = await Self.decoded(file)
                } catch {
                    log.error("Photo \(photo.id, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                    image = nil
                }
            }
        }
        return image
    }

    /// The picture at `url`, fully decoded and upright on a background thread,
    /// so drawing it later doesn't decode on the main thread.
    private static func decoded(_ url: URL) async -> NSImage? {
        let image = await Task.detached(priority: .userInitiated) { () -> CGImage? in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }
            let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
            let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: max(width, height, 1),
                kCGImageSourceShouldCacheImmediately: true,
            ]
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).map(displayReady)
        }.value
        return image.map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
    }

    private nonisolated static func isImage(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image)
    }

    /// The file for an image source, once it's been imported or downloaded.
    public func fileURL(for source: ImageSource) -> URL? {
        switch source {
        case .art: nil
        case .file(let name): userDirectory.appendingPathComponent(name)
        case .bundled(let name): Self.bundledURL(name)
        case .web(let photo): cacheDirectory.appendingPathComponent(photo.cacheName)
        }
    }

    private static func bundledURL(_ name: String) -> URL? {
        // App bundles put art in Resources; SwiftPM tools use the resource bundle.
        if Bundle.main.bundleURL.pathExtension == "app" {
            return Bundle.main.url(forResource: name, withExtension: nil, subdirectory: "ThemeArt")
        }
        return Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "ThemeArt")
    }

    private nonisolated static func writeScaledJPEG(from data: Data, to destination: URL, maxPixels: Int) -> Bool {
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
        return writeScaledJPEG(imageSource, to: destination, maxPixels: maxPixels)
    }

    private nonisolated static func writeScaledJPEG(from source: URL, to destination: URL, maxPixels: Int) -> Bool {
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil) else { return false }
        return writeScaledJPEG(imageSource, to: destination, maxPixels: maxPixels)
    }

    private nonisolated static func writeScaledJPEG(_ imageSource: CGImageSource, to destination: URL, maxPixels: Int) -> Bool {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary),
              let output = CGImageDestinationCreateWithURL(destination as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            return false
        }
        CGImageDestinationAddImage(output, image, [kCGImageDestinationLossyCompressionQuality: 0.88] as CFDictionary)
        return CGImageDestinationFinalize(output)
    }
}
