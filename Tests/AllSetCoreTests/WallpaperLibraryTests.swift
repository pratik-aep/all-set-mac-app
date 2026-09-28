import Foundation
import Testing
@testable import AllSetCore

@Suite struct WallpaperLibraryTests {
    private func video(_ id: String, _ title: String, category: Aerial.Category = .games, tags: [String] = [],
                       width: Int = 1920, duration: Double = 10, added: String = "2026-09-27T10:00:00") -> LibraryVideo {
        LibraryVideo(id: id, title: title, category: category, tags: tags, root: "r1", file: "\(id).mp4",
                     duration: duration, width: width, height: width * 9 / 16, addedAt: added)
    }

    @Test func catalogSurvivesBadEntriesAndUnknownValues() throws {
        let json = """
            {"version": 1, "roots": [{"id": "r1", "path": "/Volumes/Drive/Walls", "label": "Walls"}],
             "items": [
               {"id": "a", "title": "Neon Alley", "category": "cities", "root": "r1", "file": "1/a.mp4", "status": "quarantined"},
               {"id": "b", "root": "r1", "file": "2/b.mp4", "category": "someNewKind", "status": "someNewStatus"},
               {"title": "no id, no file"},
               {"id": "c", "title": "Broken", "category": "space", "root": "r1", "file": "3/c.mp4", "status": "unsupported"}
             ]}
            """
        let catalog = try JSONDecoder().decode(WallpaperLibraryCatalog.self, from: Data(json.utf8))
        #expect(catalog.items.map(\.id) == ["a", "b", "c"])
        #expect(catalog.items[1].category == .abstract)
        // Unknown status is treated as the most careful one.
        #expect(catalog.items[1].status == .quarantined)
        #expect(catalog.items[1].title == "Untitled video")
        // Catalogs from before stills existed are all videos.
        #expect(catalog.items[0].kind == .video)
        #expect(catalog.roots.first?.label == "Walls")
    }

    @Test func searchLooksAtTitleTagsAndCategory() {
        let alley = video("a", "Alley Shops - Winter Neon City", category: .cities, tags: ["landscape", "4k"])
        #expect(alley.matches("neon"))
        #expect(alley.matches("winter 4k"))
        #expect(alley.matches("Cities"))
        #expect(!alley.matches("underwater"))
        #expect(alley.matches(""))
    }

    @Test func sortsUseRealMetadataOnly() {
        let videos = [video("a", "Beta", width: 1920, duration: 30, added: "2026-09-01T00:00:00"),
                      video("b", "alpha", width: 3840, duration: 5, added: "2026-09-27T00:00:00"),
                      video("c", "Gamma", width: 2560, duration: 60, added: "2026-09-10T00:00:00")]
        #expect(LibrarySort.title.sorted(videos).map(\.id) == ["b", "a", "c"])
        #expect(LibrarySort.newest.sorted(videos).map(\.id) == ["b", "c", "a"])
        #expect(LibrarySort.longest.sorted(videos).map(\.id) == ["c", "a", "b"])
        #expect(LibrarySort.resolution.sorted(videos).map(\.id) == ["b", "c", "a"])
        #expect(videos[1].resolutionLabel == "4K")
    }

    @Test func librarySourceRoundTrips() throws {
        var config = WallpaperConfig()
        config.source = .library("0123456789abcdef")
        let again = try JSONDecoder().decode(WallpaperConfig.self, from: JSONEncoder().encode(config))
        #expect(again.source == .library("0123456789abcdef"))
    }

    @MainActor @Test func resolvesPlaybackCopyOriginalOrNothing() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("wallpaper-\(UUID())")
        let drive = home.appendingPathComponent("Drive")
        defer { try? FileManager.default.removeItem(at: home) }
        let store = WallpaperStore(directory: home.appendingPathComponent("AllSet"))
        try FileManager.default.createDirectory(at: drive.appendingPathComponent("1"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: store.libraryDirectory.appendingPathComponent("transcoded"), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: drive.appendingPathComponent("1/a.mp4"))
        try Data("y".utf8).write(to: store.libraryDirectory.appendingPathComponent("transcoded/b.mp4"))
        try FileManager.default.createDirectory(at: store.libraryDirectory.appendingPathComponent("stills"), withIntermediateDirectories: true)
        try Data("z".utf8).write(to: store.libraryDirectory.appendingPathComponent("stills/e.jpg"))
        let catalog = WallpaperLibraryCatalog(
            roots: [.init(id: "r1", path: drive.path, label: "Drive")],
            items: [LibraryVideo(id: "a", title: "A", category: .games, root: "r1", file: "1/a.mp4"),
                    LibraryVideo(id: "b", title: "B", category: .games, root: "r1", file: "2/b.mp4", playback: "transcoded/b.mp4"),
                    LibraryVideo(id: "c", title: "C", category: .games, root: "r1", file: "missing.mp4"),
                    LibraryVideo(id: "d", title: "D", category: .games, root: "r1", file: "1/a.mp4", status: .unsupported),
                    LibraryVideo(id: "e", title: "E", kind: .image, category: .abstract, root: "r1", file: "3/scene.pkg",
                                 playback: "stills/e.jpg"),
                    LibraryVideo(id: "f", title: "F", kind: .image, category: .abstract, root: "r1", file: "1/a.mp4",
                                 playback: "stills/missing.jpg")])
        try JSONEncoder().encode(catalog).write(to: store.libraryDirectory.appendingPathComponent("catalog.json"))
        store.reloadLibrary()
        for _ in 0..<100 where store.library.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        // Unsupported entries never reach the gallery.
        #expect(store.library.map(\.id) == ["a", "b", "c", "e", "f"])
        // A still resolves to its picture, never to the scene package it came from.
        #expect(store.libraryURL("e")?.lastPathComponent == "e.jpg")
        #expect(store.libraryURL("f") == nil)
        #expect(store.libraryURL("a")?.path == drive.appendingPathComponent("1/a.mp4").path)
        // The converted copy wins over the original.
        #expect(store.libraryURL("b")?.lastPathComponent == "b.mp4")
        #expect(store.libraryURL("b")?.path.contains("transcoded") == true)
        #expect(store.libraryURL("c") == nil)
        // Unplugging the drive: nothing resolves from it (the local copy still does).
        try FileManager.default.removeItem(at: drive)
        store.refreshLibraryReachability()
        #expect(store.libraryURL("a") == nil)
        #expect(store.libraryURL("b") != nil)
        // Stills live on this Mac: still playable with the drive gone.
        #expect(store.libraryURL("e") != nil)
        #expect(store.canPlay(store.libraryVideo("e")!))
        #expect(!store.canPlay(store.libraryVideo("a")!))
    }

    /// The user's delete button: gone from the app, gone from disk, and it
    /// never comes back — without silently losing data the importer wrote
    /// for every *other* wallpaper (the risk in editing the catalog by hand).
    @MainActor @Test func deletingALibraryVideoIsPermanentAndLeavesOthersIntact() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("wallpaper-\(UUID())")
        defer { try? FileManager.default.removeItem(at: home) }
        let store = WallpaperStore(directory: home.appendingPathComponent("AllSet"))
        for folder in ["live", "stills", "thumbnails"] {
            try FileManager.default.createDirectory(at: store.libraryDirectory.appendingPathComponent(folder),
                                                    withIntermediateDirectories: true)
        }
        try Data("loop".utf8).write(to: store.libraryDirectory.appendingPathComponent("live/a.mp4"))
        try Data("still".utf8).write(to: store.libraryDirectory.appendingPathComponent("stills/a.jpg"))
        try Data("thumb-a".utf8).write(to: store.libraryDirectory.appendingPathComponent("thumbnails/a.jpg"))
        try Data("thumb-b".utf8).write(to: store.libraryDirectory.appendingPathComponent("thumbnails/b.jpg"))
        // Fields the importer writes that the app's model doesn't know about
        // (a stand-in for sha256, sceneNotes, movement…): must survive.
        let catalog: [String: Any] = [
            "version": 1, "roots": [["id": "r1", "path": "/Volumes/Drive", "label": "Drive"]],
            "items": [
                ["id": "a", "title": "Delete Me", "category": "games", "root": "r1", "file": "1/a.mp4",
                 "playback": "live/a.mp4", "still": "stills/a.jpg", "thumbnail": "thumbnails/a.jpg", "sha256": "deadbeef"],
                ["id": "b", "title": "Keep Me", "category": "games", "root": "r1", "file": "2/b.mp4",
                 "thumbnail": "thumbnails/b.jpg", "sha256": "cafef00d", "sceneNotes": ["unsupported": ["particle object": 3]]],
            ],
        ]
        let catalogURL = store.libraryDirectory.appendingPathComponent("catalog.json")
        try JSONSerialization.data(withJSONObject: catalog).write(to: catalogURL)
        store.reloadLibrary()
        for _ in 0..<100 where store.library.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        #expect(store.library.map(\.id).sorted() == ["a", "b"])

        store.deleteLibraryVideo("a")

        #expect(store.libraryVideo("a") == nil)
        #expect(store.library.map(\.id) == ["b"])
        for path in ["live/a.mp4", "stills/a.jpg", "thumbnails/a.jpg"] {
            #expect(!FileManager.default.fileExists(atPath: store.libraryDirectory.appendingPathComponent(path).path))
        }
        // Untouched: not this wallpaper's file, and not referenced by it.
        #expect(FileManager.default.fileExists(atPath: store.libraryDirectory.appendingPathComponent("thumbnails/b.jpg").path))

        let removed = try JSONSerialization.jsonObject(with: Data(contentsOf: store.libraryDirectory.appendingPathComponent("removed.json")))
        #expect((removed as? [String: Any])?["a"] != nil)

        // The rewritten catalog.json still has "b"'s importer-only fields —
        // proof this went through raw JSON, not a lossy decode/re-encode.
        let after = try JSONSerialization.jsonObject(with: Data(contentsOf: catalogURL)) as? [String: Any]
        let items = after?["items"] as? [[String: Any]]
        #expect(items?.count == 1)
        #expect(items?.first?["id"] as? String == "b")
        #expect(items?.first?["sha256"] as? String == "cafef00d")
        #expect(items?.first?["sceneNotes"] != nil)

        // A re-import of the same folder must not bring "a" back: this is
        // what makes the delete permanent, not just a session-local hide.
        #expect((removed as? [String: Any])?.keys.contains("a") == true)
    }

    /// `library` fills in asynchronously; a real regression this session
    /// (`WallpaperView` rendering before the catalog loaded, giving up on a
    /// fetch permanently instead of retrying once real data arrived) was
    /// only found by testing against the actual running app, not a mock.
    /// This is the property that fix depends on: it must start false and
    /// flip true once, not before.
    @MainActor @Test func hasLoadedLibraryStartsFalseAndFlipsOnceLoaded() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("wallpaper-\(UUID())")
        defer { try? FileManager.default.removeItem(at: home) }
        let store = WallpaperStore(directory: home)
        // The async load's Task can't have run yet: init() hasn't awaited
        // anything, so nothing has yielded back to the run loop for it to
        // start on. This is exactly the window WallpaperView can render in.
        #expect(!store.hasLoadedLibrary)
        for _ in 0..<200 where !store.hasLoadedLibrary { try await Task.sleep(for: .milliseconds(10)) }
        #expect(store.hasLoadedLibrary)
    }

    /// The promise behind `--self-contained`: once every wallpaper has a copy
    /// here, deleting the folder they came from changes nothing.
    @MainActor @Test func copiedLibraryOutlivesTheFolderItCameFrom() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("wallpaper-\(UUID())")
        let drive = home.appendingPathComponent("Pendrive")
        defer { try? FileManager.default.removeItem(at: home) }
        let store = WallpaperStore(directory: home.appendingPathComponent("AllSet"))
        try FileManager.default.createDirectory(at: drive, withIntermediateDirectories: true)
        try Data("source".utf8).write(to: drive.appendingPathComponent("clip.mp4"))
        for folder in ["originals", "live"] {
            try FileManager.default.createDirectory(at: store.libraryDirectory.appendingPathComponent(folder),
                                                    withIntermediateDirectories: true)
        }
        try Data("copy".utf8).write(to: store.libraryDirectory.appendingPathComponent("originals/a.mp4"))
        try Data("loop".utf8).write(to: store.libraryDirectory.appendingPathComponent("live/b.mp4"))
        let catalog = WallpaperLibraryCatalog(
            roots: [.init(id: "r1", path: drive.path, label: "Pendrive")],
            items: [LibraryVideo(id: "a", title: "Copied", category: .games, root: "r1", file: "clip.mp4",
                                 playback: "originals/a.mp4"),
                    LibraryVideo(id: "b", title: "Scene loop", category: .abstract, root: "r1", file: "scene.pkg",
                                 playback: "live/b.mp4")])
        try JSONEncoder().encode(catalog).write(to: store.libraryDirectory.appendingPathComponent("catalog.json"))
        store.reloadLibrary()
        for _ in 0..<100 where store.library.isEmpty { try await Task.sleep(for: .milliseconds(20)) }

        // The pendrive is wiped and unplugged.
        try FileManager.default.removeItem(at: drive)
        store.refreshLibraryReachability()
        #expect(!store.reachableRoots.contains("r1"))
        for id in ["a", "b"] {
            let video = try #require(store.libraryVideo(id))
            #expect(store.canPlay(video))
            #expect(store.libraryURL(id) != nil)
            // It plays from this Mac, never from the folder that's gone.
            #expect(store.libraryURL(id)?.path.hasPrefix(store.libraryDirectory.path) == true)
        }
    }
}

/// A request handler installed per test, so `StubURLProtocol` never has to
/// guess which test it's answering for.
private final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (status: Int, body: Data?))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        let (status, body) = handler(request)
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if let body { client?.urlProtocol(self, didLoad: body) }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// `.serialized`: every test here points the shared `StubURLProtocol.handler`
/// at its own behaviour, which a concurrently-running sibling would stomp on.
@Suite(.serialized) struct LibraryServerFetchTests {
    /// A store with one catalog entry that has no local copy and no
    /// reachable source root, plus a server configured to answer over a
    /// stubbed session — everything the fetch path actually needs, nothing
    /// it doesn't.
    @MainActor private func missingLibraryVideo(relative: String = "live/f1.mp4") async throws -> (store: WallpaperStore, id: String) {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("wallpaper-\(UUID())")
        let store = WallpaperStore(directory: home)
        let id = "f1"
        let catalog: [String: Any] = [
            "version": 1, "roots": [],
            "items": [["id": id, "title": "Fetchable", "category": "games", "root": "gone", "file": "1/f1.mp4",
                      "playback": relative]],
        ]
        try FileManager.default.createDirectory(at: store.libraryDirectory, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: catalog).write(to: store.libraryDirectory.appendingPathComponent("catalog.json"))
        store.reloadLibrary()
        for _ in 0..<100 where store.library.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        store.config.libraryServerURL = "http://stub.invalid"
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        store.fetchSession = URLSession(configuration: configuration)
        return (store, id)
    }

    @MainActor @Test func alreadyLocalNeverTouchesTheNetwork() async throws {
        let (store, id) = try await missingLibraryVideo()
        // No handler installed: any network attempt fails loudly, not silently.
        StubURLProtocol.handler = nil
        let relative = "live/f1.mp4"
        try FileManager.default.createDirectory(at: store.libraryDirectory.appendingPathComponent("live"), withIntermediateDirectories: true)
        try Data("already here".utf8).write(to: store.libraryDirectory.appendingPathComponent(relative))
        let url = try await store.fetchLibraryVideo(id)
        #expect(url.path == store.libraryDirectory.appendingPathComponent(relative).path)
    }

    @MainActor @Test func fetchesAndCachesInTheSameRelativePath() async throws {
        let (store, id) = try await missingLibraryVideo()
        let bytes = Data("stub-video-bytes".utf8)
        StubURLProtocol.handler = { request in
            #expect(request.url?.absoluteString == "http://stub.invalid/live/f1.mp4")
            return (200, bytes)
        }
        let video = try #require(store.libraryVideo(id))
        #expect(!store.canPlay(video))

        let url = try await store.fetchLibraryVideo(id)

        #expect(url.path == store.libraryDirectory.appendingPathComponent("live/f1.mp4").path)
        #expect(try Data(contentsOf: url) == bytes)
        #expect(store.canPlay(video))
        // Ordinary resolution finds it now too, with no server involved.
        #expect(store.libraryURL(id) == url)
    }

    @MainActor @Test func unreachableServerThrowsAndLeavesNoPartialFile() async throws {
        let (store, id) = try await missingLibraryVideo()
        StubURLProtocol.handler = { _ in (500, nil) }

        await #expect(throws: (any Error).self) {
            try await store.fetchLibraryVideo(id)
        }

        let destination = store.libraryDirectory.appendingPathComponent("live/f1.mp4")
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        let video = try #require(store.libraryVideo(id))
        #expect(!store.canPlay(video))
    }
}
