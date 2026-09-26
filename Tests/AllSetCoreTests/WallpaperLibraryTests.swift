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
        let catalog = WallpaperLibraryCatalog(
            roots: [.init(id: "r1", path: drive.path, label: "Drive")],
            items: [LibraryVideo(id: "a", title: "A", category: .games, root: "r1", file: "1/a.mp4"),
                    LibraryVideo(id: "b", title: "B", category: .games, root: "r1", file: "2/b.mp4", playback: "transcoded/b.mp4"),
                    LibraryVideo(id: "c", title: "C", category: .games, root: "r1", file: "missing.mp4"),
                    LibraryVideo(id: "d", title: "D", category: .games, root: "r1", file: "1/a.mp4", status: .unsupported)])
        try JSONEncoder().encode(catalog).write(to: store.libraryDirectory.appendingPathComponent("catalog.json"))
        store.reloadLibrary()
        for _ in 0..<100 where store.library.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        // Unsupported entries never reach the gallery.
        #expect(store.library.map(\.id) == ["a", "b", "c"])
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
    }
}
