import Foundation
import Testing
@testable import AllSetCore

@Suite struct StoreFileTests {
    private func temporaryFile(_ contents: String?) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("storefile-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("notes.json")
        if let contents { try Data(contents.utf8).write(to: file) }
        return file
    }

    @Test func missingFilesAreQuietlyEmpty() throws {
        let file = try temporaryFile(nil)
        #expect(StoreFile.load([QuickNote].self, from: file) == nil)
        let siblings = try FileManager.default.contentsOfDirectory(atPath: file.deletingLastPathComponent().path)
        #expect(siblings.isEmpty)
    }

    @Test func unreadableFilesAreKeptAside() throws {
        let file = try temporaryFile("{ this is not json")
        #expect(StoreFile.load([QuickNote].self, from: file) == nil)
        let siblings = try FileManager.default.contentsOfDirectory(atPath: file.deletingLastPathComponent().path)
        #expect(siblings.contains { $0.hasPrefix("notes.unreadable-") && $0.hasSuffix(".json") })
    }

    @Test @MainActor func aCorruptNotesFileSurvivesTheNextSave() throws {
        let file = try temporaryFile(#"[{"text": 42}]"#)
        let store = NotesStore(fileURL: file)
        #expect(store.notes.isEmpty)
        store.add("new note")
        store.save()
        let siblings = try FileManager.default.contentsOfDirectory(atPath: file.deletingLastPathComponent().path)
        let kept = try #require(siblings.first { $0.contains("unreadable") })
        let original = try String(contentsOf: file.deletingLastPathComponent().appendingPathComponent(kept), encoding: .utf8)
        #expect(original == #"[{"text": 42}]"#)
    }

    @Test @MainActor func widgetSavesReportFailures() throws {
        // A folder where the file should be: the write can't succeed.
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("widgets-\(UUID().uuidString)", isDirectory: true)
        let file = folder.appendingPathComponent("widgets.json")
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: true)
        let store = WidgetStore(fileURL: file)
        store.add(WidgetInstance(kind: .clock))
        store.saveNow()
        #expect(store.saveError != nil)
    }
}

@Suite struct PhotoURLTests {
    @Test func oddIdsNeverCrash() {
        let photo = WebPhoto(id: "a b/c?d#e", author: "Someone", width: 4000, height: 3000)
        #expect(photo.displayURL.host() == "picsum.photos")
        #expect(photo.thumbnailURL(side: 200).absoluteString.contains("picsum.photos"))
    }
}
