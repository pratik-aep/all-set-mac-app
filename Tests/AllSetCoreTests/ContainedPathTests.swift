import Foundation
import Testing
@testable import AllSetCore

@Suite @MainActor struct ContainedPathTests {
    private func scratch() throws -> URL {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("AllSetTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return home
    }

    @Test func onlyPathsInsideTheFolderResolve() throws {
        let home = try scratch()
        defer { try? FileManager.default.removeItem(at: home) }
        let root = home.appendingPathComponent("Library")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("live"), withIntermediateDirectories: true)
        #expect(ContainedPath.resolve("live/a.mp4", in: root) != nil)
        #expect(ContainedPath.resolve("../outside.txt", in: root) == nil)
        #expect(ContainedPath.resolve("live/../../outside.txt", in: root) == nil)
        #expect(ContainedPath.resolve("/etc/hosts", in: root) == nil)
        #expect(ContainedPath.resolve("", in: root) == nil)
        #expect(ContainedPath.resolve("~/x", in: root) == nil)
        // The folder itself isn't "inside" it.
        #expect(!ContainedPath.contains(root, in: root))
    }

    @Test func aSiblingWhoseNameStartsTheSameIsOutside() throws {
        let home = try scratch()
        defer { try? FileManager.default.removeItem(at: home) }
        let dropped = home.appendingPathComponent("Dropped")
        #expect(!ContainedPath.contains(home.appendingPathComponent("Dropped-Other/file.txt"), in: dropped))
        #expect(ContainedPath.contains(home.appendingPathComponent("Dropped/file.txt"), in: dropped))
    }

    @Test func aSymlinkOutOfTheFolderIsOutside() throws {
        let home = try scratch()
        defer { try? FileManager.default.removeItem(at: home) }
        let root = home.appendingPathComponent("Library")
        let outside = home.appendingPathComponent("Elsewhere")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link"), withDestinationURL: outside)
        #expect(ContainedPath.resolve("link/file.txt", in: root) == nil)
    }

    // MARK: Review R4: the shelf

    @Test func removingAShelfItemNeverDeletesAFileOutsideItsOwnFolder() throws {
        let home = try scratch()
        defer { try? FileManager.default.removeItem(at: home) }
        let shelf = ShelfStore(directory: home)
        let sibling = home.appendingPathComponent("Dropped-Other/file.txt")
        try FileManager.default.createDirectory(at: sibling.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not the shelf's".utf8).write(to: sibling)
        shelf.add([sibling])
        let id = try #require(shelf.items.first?.id)
        shelf.remove(id)
        #expect(FileManager.default.fileExists(atPath: sibling.path))

        // A file the shelf saved itself still goes when it leaves.
        let own = shelf.droppedFilesDirectory.appendingPathComponent("picture.png")
        try Data("saved by the shelf".utf8).write(to: own)
        shelf.add([own])
        shelf.remove(try #require(shelf.items.first?.id))
        #expect(!FileManager.default.fileExists(atPath: own.path))
    }

    // MARK: Review R5: library entries that escape the library

    @Test func aLibraryEntryWhosePathEscapesIsNeverLoadedOrDeleted() async throws {
        let home = try scratch()
        defer { try? FileManager.default.removeItem(at: home) }
        let store = WallpaperStore(directory: home.appendingPathComponent("Wallpaper"))
        let library = store.libraryDirectory
        try FileManager.default.createDirectory(at: library.appendingPathComponent("live"), withIntermediateDirectories: true)
        let outside = library.deletingLastPathComponent().appendingPathComponent("outside.txt")
        try Data("not the library's".utf8).write(to: outside)
        try Data("ok".utf8).write(to: library.appendingPathComponent("live/good.mp4"))
        let catalog: [String: Any] = ["version": 1, "roots": [], "items": [
            ["id": "evil", "title": "Escapes", "category": "games", "root": "r", "file": "f", "playback": "../outside.txt"],
            ["id": "good", "title": "Fine", "category": "games", "root": "r", "file": "g", "playback": "live/good.mp4"],
        ]]
        try JSONSerialization.data(withJSONObject: catalog).write(to: library.appendingPathComponent("catalog.json"))
        store.reloadLibrary()
        for _ in 0..<100 where !store.hasLoadedLibrary { try await Task.sleep(for: .milliseconds(20)) }

        #expect(store.libraryVideo("evil") == nil)
        #expect(store.libraryVideo("good") != nil)
        #expect(store.deleteLibraryVideo("evil") == nil)
        #expect(FileManager.default.fileExists(atPath: outside.path))
    }
}

/// Recheck S3: resolving a path asked libc to allocate the result just to see
/// whether the path existed, and never freed it: about 2 KB lost per check.
/// Off the main actor: a second of path checks there starves tests that sample
/// on it.
@Suite struct ContainedPathLeakTests {
    @Test func checkingContainmentDoesNotLeak() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AllSetContained-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let inside = root.appendingPathComponent("a/b.txt")
        func heapInUse() -> Int {
            var stats = malloc_statistics_t()
            malloc_zone_statistics(nil, &stats)
            return stats.size_in_use
        }
        // In rounds, taking the quietest, so other tests allocating at the same
        // time don't fail it; the leak grew every round by about 4 MB.
        var quietest = Int.max
        for _ in 0..<3 {
            let before = heapInUse()
            // Drained each time: Foundation's temporaries would otherwise pile up and look like a leak.
            for _ in 0..<2_000 { autoreleasepool { _ = ContainedPath.contains(inside, in: root) } }
            quietest = min(quietest, heapInUse() - before)
        }
        #expect(quietest < 1 << 20)
    }
}
