import Foundation
import Observation
import OSLog

/// Photo search through Openverse (openverse.org), free and without a key.
///
/// Openverse's whole index is mostly museum and encyclopedia pictures (maps,
/// flags, specimens), so searches go to its stock photo collections: the
/// WordPress Photo Directory (full-size, CC0) and Rawpixel (strong on
/// aesthetic, neon and illustrated looks). Flickr fills in when those find
/// little. Stickers, clip art and small images are dropped.
///
/// Anonymous use allows about 20 searches a minute and 200 a day, so typing
/// is debounced, requests are paced to stay under the limit, and every page
/// of results is cached for a day (and kept a month, for when the network or
/// the limit says no). Aesthetics ("coquette") become concrete searches and
/// typos are fixed, both through `AestheticSearch`.
@Observable @MainActor
public final class PhotoSearch {
    public private(set) var query = ""
    public private(set) var results: [WebPhoto] = []
    public private(set) var isSearching = false
    public private(set) var hasMore = false
    public private(set) var errorMessage: String?
    /// How the words were understood, to show under the search box:
    /// "pink bow, pearls, pink roses" or "Showing results for mountains".
    public private(set) var interpretation: String?

    /// Only big images, good enough for a wallpaper.
    public var highResolution = true { didSet { if oldValue != highResolution { restart() } } }
    /// Only landscape images, the shape of a screen.
    public var wideOnly = false { didSet { if oldValue != wideOnly { restart() } } }

    public static let suggestions = AestheticSearch.suggestions + [
        "Landscape", "Mountains", "Ocean", "Night sky", "Neon city", "Aesthetic", "Minimal", "Forest",
        "Flowers", "Rain", "Sunset", "Snow", "Desert", "Architecture", "Abstract", "Coffee",
    ]

    /// Curated collections, searched first.
    static let curatedSources = "wordpress,rawpixel"
    /// Wider, noisier, used when the curated search comes back thin.
    static let fallbackSources = "flickr"
    static let pageSize = 30

    @ObservationIgnored private var page = 1
    /// The concrete searches behind `query`; pages take turns through them.
    @ObservationIgnored private var searches: [String] = []
    @ObservationIgnored private var pacer = SearchPacer()
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var memoryCache: [String: CachedPage] = [:]
    @ObservationIgnored private let cacheDirectory: URL
    @ObservationIgnored private let log = Logger(subsystem: "com.pratik.allset", category: "search")

    private struct CachedPage: Codable {
        var photos: [WebPhoto]
        var pageCount: Int
        var date: Date
    }

    public init(cacheDirectory: URL? = nil) {
        self.cacheDirectory = cacheDirectory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AllSet/Search", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.cacheDirectory, withIntermediateDirectories: true)
    }

    /// Starts a search after a short pause in typing. Clearing the text clears results.
    public func search(_ text: String, immediately: Bool = false) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // "Neon  City" and "neon city" are the same search.
        guard SearchMatch.normalize(trimmed) != SearchMatch.normalize(query) || (results.isEmpty && !isSearching) else { return }
        task?.cancel()
        query = trimmed
        page = 1
        results = []
        errorMessage = nil
        hasMore = false
        isSearching = false
        searches = AestheticSearch.searches(for: trimmed)
        interpretation = AestheticSearch.explanation(for: trimmed)
        guard trimmed.count >= 2, !searches.isEmpty else { return }
        task = Task { [weak self] in
            if !immediately {
                try? await Task.sleep(for: .milliseconds(450))
                guard !Task.isCancelled else { return }
            }
            await self?.load(page: 1)
        }
    }

    public func loadMore() {
        guard hasMore, !isSearching, !query.isEmpty else { return }
        page += 1
        let next = page
        task = Task { [weak self] in await self?.load(page: next) }
    }

    private func restart() {
        let current = query
        query = ""
        search(current, immediately: true)
    }

    private func load(page: Int) async {
        guard let request = AestheticSearch.request(forPage: page, of: searches) else { return }
        let key = cacheKey(request.query, page: request.page)
        if let cached = cachedPage(key, maxAge: 86_400) {
            apply(cached, page: page)
            return
        }
        isSearching = true
        defer { isSearching = false }
        do {
            var decoded = try await fetch(request.query, page: request.page, sources: Self.curatedSources)
            // Thin results: top up from Flickr, curated photos first.
            if request.page == 1, decoded.photos.count < 12 {
                if let wider = try? await fetch(request.query, page: 1, sources: Self.fallbackSources) {
                    let seen = Set(decoded.photos.map(\.id))
                    decoded.photos += wider.photos.filter { !seen.contains($0.id) }
                    decoded.pageCount = max(decoded.pageCount, 1)
                }
            }
            // Next to nothing, maybe from a typo: try the nearest real words.
            if page == 1, decoded.photos.count < 6, searches.count == 1,
               let corrected = AestheticSearch.correctedSpelling(of: request.query),
               let fixed = try? await fetch(corrected, page: 1, sources: Self.curatedSources),
               fixed.photos.count > decoded.photos.count {
                decoded = fixed
                searches = [corrected]
                interpretation = "Showing results for \u{201C}\(corrected)\u{201D}"
            }
            guard !Task.isCancelled else { return }
            decoded.photos = Self.ranked(decoded.photos)
            let entry = CachedPage(photos: decoded.photos, pageCount: decoded.pageCount, date: .now)
            store(entry, key: key)
            apply(entry, page: page)
        } catch {
            guard !Task.isCancelled else { return }
            // Offline or over the limit: an older copy beats an error.
            if let stale = cachedPage(key, maxAge: 30 * 86_400) {
                apply(stale, page: page)
                return
            }
            if case SearchError.rateLimited = error {
                errorMessage = "Openverse allows about 20 searches a minute. Try again in a moment."
            } else {
                log.error("Search failed: \(error.localizedDescription, privacy: .public)")
                errorMessage = "Search failed: \(error.localizedDescription)"
            }
        }
    }

    private enum SearchError: Error {
        case rateLimited
    }

    /// One request, paced to stay under the limit; a 429 with a short
    /// Retry-After is waited out and tried once more.
    private func fetch(_ text: String, page: Int, sources: String, retrying: Bool = true) async throws -> (photos: [WebPhoto], pageCount: Int) {
        let wait = pacer.delay(at: .now)
        if wait > 0 { try await Task.sleep(for: .seconds(wait)) }
        let (data, response) = try await URLSession.shared.data(from: url(text, page: page, sources: sources))
        if let http = response as? HTTPURLResponse, http.statusCode == 429 {
            let retryAfter = (http.value(forHTTPHeaderField: "Retry-After")).flatMap(Double.init) ?? 60
            guard retrying, retryAfter <= 15 else { throw SearchError.rateLimited }
            try await Task.sleep(for: .seconds(retryAfter))
            return try await fetch(text, page: page, sources: sources, retrying: false)
        }
        return try Self.decode(data)
    }

    private func apply(_ entry: CachedPage, page: Int) {
        let fresh = entry.photos.filter { photo in !results.contains { $0.id == photo.id } }
        results = page == 1 ? entry.photos : results + fresh
        // Aesthetic searches go on while any of their searches has pages left.
        let round = (page - 1) / max(searches.count, 1) + 1
        hasMore = (round < entry.pageCount || page < searches.count) && !(entry.photos.isEmpty && searches.count == 1)
    }

    /// Big photos first, keeping Openverse's order otherwise.
    nonisolated static func ranked(_ photos: [WebPhoto]) -> [WebPhoto] {
        let sharp = photos.filter { max($0.width, $0.height) >= 1600 || $0.width == 0 }
        let soft = photos.filter { !(max($0.width, $0.height) >= 1600 || $0.width == 0) }
        return sharp + soft
    }

    func url(_ text: String, page: Int, sources: String) -> URL {
        var components = URLComponents(string: "https://api.openverse.org/v1/images/")!
        var items = [
            URLQueryItem(name: "q", value: text),
            URLQueryItem(name: "source", value: sources),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "page_size", value: String(Self.pageSize)),
            URLQueryItem(name: "mature", value: "false"),
        ]
        // Flickr's big pool needs the size filter; the curated ones are all large.
        if highResolution, sources == Self.fallbackSources { items.append(URLQueryItem(name: "size", value: "large")) }
        if wideOnly { items.append(URLQueryItem(name: "aspect_ratio", value: "wide")) }
        components.queryItems = items
        return components.url!
    }

    // MARK: Cache

    private func cacheKey(_ text: String, page: Int) -> String {
        // "v3": keyed by the search actually sent, after aesthetics are expanded.
        "v3|\(SearchMatch.normalize(text))|\(highResolution)|\(wideOnly)|\(page)"
    }

    private func cachedPage(_ key: String, maxAge: TimeInterval) -> CachedPage? {
        let entry = memoryCache[key] ?? (try? Data(contentsOf: cacheFile(key))).flatMap { try? JSONDecoder().decode(CachedPage.self, from: $0) }
        guard let entry else { return nil }
        memoryCache[key] = entry
        return entry.date.timeIntervalSinceNow > -maxAge ? entry : nil
    }

    private func store(_ entry: CachedPage, key: String) {
        memoryCache[key] = entry
        if let data = try? JSONEncoder().encode(entry) {
            try? data.write(to: cacheFile(key), options: .atomic)
        }
    }

    private func cacheFile(_ key: String) -> URL {
        // FNV-1a keeps file names short and safe for any query text.
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100_0000_01b3
        }
        return cacheDirectory.appendingPathComponent(String(format: "%016llx.json", hash))
    }

    // MARK: Decoding

    nonisolated static func decode(_ data: Data) throws -> (photos: [WebPhoto], pageCount: Int) {
        struct Response: Decodable {
            struct Result: Decodable {
                var id: String
                var title: String?
                var creator: String?
                var license: String?
                var license_version: String?
                var width: Int?
                var height: Int?
                var url: String?
                var thumbnail: String?
                var source: String?
                var filetype: String?
            }
            var page_count: Int?
            var results: [Result]
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        var seen = Set<String>()
        let photos = response.results.compactMap { result -> WebPhoto? in
            guard let url = result.url, isWallpaperWorthy(title: result.title, filetype: result.filetype,
                                                          width: result.width, height: result.height),
                  // The same shot is often listed twice under slightly different titles.
                  seen.insert("\(result.width ?? 0)x\(result.height ?? 0)|\(result.creator ?? "")|\((result.title ?? "").prefix(12))").inserted
            else { return nil }
            let license = result.license.map { name in
                name == "cc0" || name == "pdm"
                    ? name.uppercased()
                    : (["CC", name.uppercased(), result.license_version].compactMap { $0 }.joined(separator: " "))
            }
            return WebPhoto(id: result.id, author: result.creator ?? "Unknown", width: result.width ?? 0, height: result.height ?? 0,
                            provider: "openverse", imageURLString: url, thumbnailURLString: result.thumbnail,
                            license: license, title: result.title, origin: result.source)
        }
        return (photos, response.page_count ?? 1)
    }

    /// Words that mark cut-outs, stickers and design assets rather than photos.
    nonisolated static let junkWords: Set<String> = ["png", "sticker", "stickers", "clipart", "transparent", "mockup", "psd", "vector",
                                         "icon", "icons", "template", "logo", "badge", "emoji", "isolated"]
    nonisolated static let junkPhrases = ["clip art", "cut out", "design element", "remixed"]

    /// Big enough for a widget or wallpaper, and a photo or illustration rather than an asset.
    nonisolated static func isWallpaperWorthy(title: String?, filetype: String?, width: Int?, height: Int?) -> Bool {
        if let type = filetype?.lowercased(), ["png", "svg", "gif"].contains(type) { return false }
        if let width, let height, max(width, height) < 1000 { return false }
        let text = (title ?? "").lowercased()
        let words = Set(text.split { !$0.isLetter }.map(String.init))
        return words.isDisjoint(with: junkWords) && !junkPhrases.contains { text.contains($0) }
    }
}
