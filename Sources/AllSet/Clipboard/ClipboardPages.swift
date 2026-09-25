import AllSetCore
import AppKit
import SwiftUI

/// Clipboard history in full: search, filters, pins and settings.
struct ClipboardPage: View {
    let services: AppServices

    @State private var query = ""
    @State private var kind: ClipboardItem.Kind?
    @State private var confirmingClear = false
    @State private var status: String?

    var body: some View {
        let store = services.clipboard
        let results = store.search(query, kind: kind)
        HSplitView {
            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Search your clipboard", text: $query)
                            .textFieldStyle(.plain)
                            .font(.system(size: 15))
                        if !query.isEmpty {
                            Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 10).fill(.primary.opacity(0.07)))

                    HStack(spacing: 6) {
                        filterChip("All", symbol: "square.grid.2x2", value: nil)
                        ForEach(ClipboardItem.Kind.allCases, id: \.self) { kind in
                            filterChip(kind.title, symbol: kind.symbol, value: kind)
                        }
                        Spacer()
                    }
                }
                .padding(16)

                if results.isEmpty {
                    ContentUnavailableView(store.items.isEmpty ? "Nothing copied yet" : "No matches",
                                           systemImage: "doc.on.clipboard",
                                           description: Text(store.items.isEmpty
                                                             ? "Copy some text, a link, an image or files and they'll appear here."
                                                             : "Try another search or filter."))
                } else {
                    List(results) { item in
                        ClipboardRow(item: item, services: services)
                            .contextMenu { actions(for: item) }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { store.remove(item.id) } label: { Label("Delete", systemImage: "trash") }
                                Button { store.togglePin(item.id) } label: { Label(item.isPinned ? "Unpin" : "Pin", systemImage: "pin") }
                                    .tint(.orange)
                            }
                            .onTapGesture(count: 2) {
                                services.clipboardMonitor.copy(item)
                                show("Copied")
                            }
                    }
                    .listStyle(.inset)
                }
                if let status {
                    Text(status)
                        .font(.callout.weight(.medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(.bar))
                        .padding(.bottom, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .frame(minWidth: 380)

            Form {
                ClipboardSettingsSections(services: services, confirmingClear: $confirmingClear)
            }
            .formStyle(.grouped)
            .frame(minWidth: 300, idealWidth: 340, maxWidth: 420)
        }
        .motion(Motion.standard, value: status)
        .confirmationDialog("Clear clipboard history?", isPresented: $confirmingClear) {
            Button("Clear History", role: .destructive) { store.clear() }
        } message: {
            Text("Pinned items stay.")
        }
    }

    @ViewBuilder
    private func actions(for item: ClipboardItem) -> some View {
        Button("Copy") {
            services.clipboardMonitor.copy(item)
            show("Copied")
        }
        if item.kind == .image {
            Button("Copy Text in Image") {
                Task {
                    let found = await services.clipboardMonitor.copyText(from: item)
                    show(found ? "Copied the text in the image" : "No text found in the image")
                }
            }
        }
        if item.kind == .link, let url = item.text.flatMap(URL.init(string:)) {
            Button("Open Link") { NSWorkspace.shared.open(url) }
        }
        if item.kind == .files, let urls = item.fileURLs {
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(urls) }
            Button("Add to Shelf") { services.shelf.add(urls) }
        }
        Divider()
        Button(item.isPinned ? "Unpin" : "Pin") { services.clipboard.togglePin(item.id) }
        Button("Delete", role: .destructive) { services.clipboard.remove(item.id) }
    }

    private func filterChip(_ title: String, symbol: String, value: ClipboardItem.Kind?) -> some View {
        Button {
            kind = value
        } label: {
            Label(title, systemImage: symbol)
                .font(.callout.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(kind == value ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.06)))
        }
        .buttonStyle(.plain)
    }

    private func show(_ message: String) {
        status = message
        Task {
            try? await Task.sleep(for: .seconds(2))
            if status == message { status = nil }
        }
    }
}

private struct ClipboardSettingsSections: View {
    let services: AppServices
    @Binding var confirmingClear: Bool

    var body: some View {
        let store = services.clipboard
        Section {
            Toggle(isOn: binding(\.isEnabled)) {
                Text("Keep clipboard history")
                Text("Stored only on this Mac.")
            }
            Picker("Remember", selection: binding(\.historyLimit)) {
                ForEach([50, 100, 200, 500, 1000], id: \.self) { count in
                    Text("\(count) items").tag(count)
                }
            }
            Toggle(isOn: binding(\.pasteOnSelect)) {
                Text("Paste when chosen")
                Text(Accessibility.isTrusted ? "Choosing an item pastes it into the app in front." : "Needs Accessibility access, like window snapping.")
            }
            LabeledContent("Open picker") {
                ShortcutRecorder(shortcut: binding(\.pickerShortcut),
                                 onRecording: { services.windowManager?.setRecordingShortcut($0) })
            }
            if services.ui.shortcutConflicts.contains("clipboard") {
                Label("Another app uses this shortcut", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }
        } header: {
            Text("Clipboard")
        }

        Section {
            ForEach(store.settings.ignoredApps, id: \.self) { bundleID in
                HStack {
                    AppIcon(bundleIdentifier: bundleID, size: 18)
                    Text(AppIconCache.name(for: bundleID) ?? bundleID)
                        .foregroundStyle(AppIconCache.name(for: bundleID) == nil ? .secondary : .primary)
                    Spacer()
                    Button {
                        store.settings.ignoredApps.removeAll { $0 == bundleID }
                    } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            Menu("Add Running App") {
                ForEach(runningApps, id: \.self) { bundleID in
                    Button(AppIconCache.name(for: bundleID) ?? bundleID) {
                        store.settings.ignoredApps.append(bundleID)
                    }
                }
            }
        } header: {
            Text("Never record from")
        } footer: {
            Text("Password managers are ignored out of the box, and so is anything apps mark as private.")
        }

        Section {
            Button("Clear History…", role: .destructive) { confirmingClear = true }
                .disabled(store.items.allSatisfy(\.isPinned))
        }
    }

    private var runningApps: [String] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap(\.bundleIdentifier)
            .filter { !services.clipboard.settings.ignoredApps.contains($0) }
            .sorted()
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<ClipboardSettings, Value>) -> Binding<Value> {
        Binding(get: { services.clipboard.settings[keyPath: keyPath] },
                set: { services.clipboard.settings[keyPath: keyPath] = $0 })
    }
}

/// The shelf, larger: everything parked, with room to drop more.
struct ShelfPage: View {
    let services: AppServices
    @State private var isTargeted = false
    @State private var pdfStatus: String?

    var body: some View {
        let shelf = services.shelf
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Shelf").font(.largeTitle.bold())
                        Text("Drop files on the notch (or here) to keep them handy, then drag them into any app or folder. Files stay where they are; the shelf just remembers them. Drop pictures or PDFs and Make PDF turns them into one PDF.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let pdfStatus {
                        Text(pdfStatus).foregroundStyle(.secondary)
                    }
                    if !shelf.items.isEmpty {
                        if ShelfActions.canMakePDF(shelf) {
                            Button {
                                Task { pdfStatus = await ShelfActions.makePDF(shelf) }
                            } label: {
                                Label("Make PDF", systemImage: "doc.richtext")
                            }
                            .help("Combine the pictures and PDFs here into one PDF, saved to Downloads")
                        }
                        Button {
                            ShelfActions.airDrop(shelf.items.map(\.url))
                        } label: {
                            Label("AirDrop All", systemImage: "square.and.arrow.up")
                        }
                        Button("Clear", role: .destructive) { shelf.clear() }
                    }
                }

                if shelf.items.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "tray.and.arrow.down.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("Drop files here").font(.headline)
                    }
                    .frame(maxWidth: .infinity, minHeight: 260)
                    .background(RoundedRectangle(cornerRadius: 16).strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                        .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary.opacity(0.4)))
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 12)], spacing: 12) {
                        ForEach(shelf.items) { item in
                            ShelfTile(item: item, shelf: shelf, iconSize: 64)
                        }
                    }
                }
            }
            .padding(28)
        }
        .onDrop(of: ShelfDrop.types, isTargeted: $isTargeted) { providers in
            ShelfDrop.accept(providers, into: shelf)
        }
    }
}
