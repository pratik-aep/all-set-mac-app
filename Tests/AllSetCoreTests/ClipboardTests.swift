import CoreGraphics
import Foundation
import Testing
@testable import AllSetCore

@Suite @MainActor struct ClipboardStoreTests {
    private func temporaryStore() -> (ClipboardStore, URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("AllSetClipboard-\(UUID().uuidString)")
        return (ClipboardStore(directory: folder), folder)
    }

    @Test func recognizesLinks() {
        #expect(ClipboardItem.text("https://apple.com/mac", sourceBundleID: nil).kind == .link)
        #expect(ClipboardItem.text("  https://apple.com  \n", sourceBundleID: nil).text == "https://apple.com")
        #expect(ClipboardItem.text("see https://apple.com", sourceBundleID: nil).kind == .text)
        #expect(ClipboardItem.text("ftp://files", sourceBundleID: nil).kind == .text)
        #expect(ClipboardItem.text("Hello\nworld", sourceBundleID: nil).preview == "Hello")
    }

    @Test func copyingAgainMovesToTheTop() {
        let (store, folder) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: folder) }
        store.add(.text("first", sourceBundleID: nil))
        store.add(.text("second", sourceBundleID: nil))
        store.add(.text("first", sourceBundleID: "com.apple.Notes"))
        #expect(store.items.map(\.text) == ["first", "second"])
        #expect(store.items.first?.sourceBundleID == "com.apple.Notes")
    }

    @Test func pinnedItemsSurviveTheLimitAndClearing() {
        let (store, folder) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: folder) }
        store.settings.historyLimit = 3
        store.add(.text("keep me", sourceBundleID: nil))
        let pinned = store.items[0].id
        store.togglePin(pinned)
        for index in 1...5 { store.add(.text("item \(index)", sourceBundleID: nil)) }
        #expect(store.items.count == 4)
        #expect(store.items.contains { $0.id == pinned })
        #expect(store.search("").first?.id == pinned)

        store.clear()
        #expect(store.items.map(\.id) == [pinned])
    }

    @Test func searchesTextAndFileNamesAndFiltersByKind() {
        let (store, folder) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: folder) }
        store.add(.text("Meeting notes for Friday", sourceBundleID: nil))
        store.add(.text("https://example.com/report", sourceBundleID: nil))
        store.add(ClipboardItem(kind: .files, fileURLs: [URL(fileURLWithPath: "/Users/me/Budget 2026.xlsx")]))
        #expect(store.search("friday").count == 1)
        #expect(store.search("budget").first?.kind == .files)
        #expect(store.search("", kind: .link).count == 1)
        #expect(store.search("nothing like this").isEmpty)
    }

    @Test func historyAndSettingsPersist() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("AllSetClipboard-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ClipboardStore(directory: folder)
        store.add(.text("saved", sourceBundleID: nil))
        store.settings.pickerShortcut = nil
        store.settings.historyLimit = 50
        store.save()

        let reloaded = ClipboardStore(directory: folder)
        #expect(reloaded.items.map(\.text) == ["saved"])
        #expect(reloaded.settings.pickerShortcut == nil)
        #expect(reloaded.settings.historyLimit == 50)
    }

    @Test func settingsFromOlderVersionsGetDefaults() throws {
        let settings = try JSONDecoder().decode(ClipboardSettings.self, from: Data(#"{"historyLimit":100}"#.utf8))
        #expect(settings.historyLimit == 100)
        #expect(settings.pickerShortcut?.display == "⌃⌥V")
        #expect(settings.ignoredApps.contains("com.1password.1password"))
    }
}

@Suite @MainActor struct ShelfStoreTests {
    @Test func remembersFilesAndForgetsDeletedOnes() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("AllSetShelf-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let kept = folder.appendingPathComponent("kept.txt")
        let deleted = folder.appendingPathComponent("deleted.txt")
        try Data("a".utf8).write(to: kept)
        try Data("b".utf8).write(to: deleted)

        let shelf = ShelfStore(directory: folder.appendingPathComponent("Shelf"))
        shelf.add([kept, deleted])
        shelf.add([kept])
        #expect(shelf.items.count == 2)

        try FileManager.default.removeItem(at: deleted)
        let reloaded = ShelfStore(directory: folder.appendingPathComponent("Shelf"))
        #expect(reloaded.items.map(\.url) == [kept])

        reloaded.remove(reloaded.items[0].id)
        #expect(reloaded.items.isEmpty)
        #expect(FileManager.default.fileExists(atPath: kept.path))
    }
}

@Suite struct ClipboardPrivacyTests {
    /// A copy made in a password manager just before switching away is still
    /// left out: any app in front since the last look counts.
    @Test func anyAppInFrontSinceTheLastLookCounts() {
        let settings = ClipboardSettings()
        #expect(settings.ignores(anyOf: ["com.apple.Safari", "com.1password.1password"]))
        #expect(!settings.ignores(anyOf: ["com.apple.Safari", "com.apple.dt.Xcode"]))
        #expect(!settings.ignores(anyOf: []))
    }

    @Test func clearOnQuitIsOffUnlessChosen() throws {
        let old = try JSONDecoder().decode(ClipboardSettings.self, from: Data(#"{"isEnabled": true}"#.utf8))
        #expect(!old.clearOnQuit)
        var settings = ClipboardSettings()
        settings.clearOnQuit = true
        #expect(try JSONDecoder().decode(ClipboardSettings.self, from: JSONEncoder().encode(settings)).clearOnQuit)
    }
}
