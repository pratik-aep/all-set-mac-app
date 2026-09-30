import AllSetCore
import AppKit
import SwiftUI

// MARK: Window snapping

struct WindowSnappingPage: View {
    let services: AppServices

    var body: some View {
        let store = services.workspaces
        let settings = store.settings
        VStack(spacing: 0) {
            AccessibilityBanner()
                .padding([.horizontal, .top], 20)
            Form {
                Section {
                    Toggle(isOn: binding(\.shortcutsEnabled)) {
                        Text("Keyboard shortcuts")
                        Text("Press one with any window in front. Press ⌃⌥← or ⌃⌥→ again to step through half, two-thirds and one-third.")
                    }
                    LabeledContent("Gap between windows") {
                        HStack {
                            Slider(value: binding(\.gap), in: 0...24, step: 2)
                                .frame(width: 200)
                            Text("\(Int(settings.gap)) pt")
                                .monospacedDigit()
                                .frame(width: 44, alignment: .trailing)
                        }
                    }
                }

                ForEach(WindowAction.Group.allCases) { group in
                    Section(group.title) {
                        ForEach(WindowAction.allCases.filter { $0.group == group }) { action in
                            HStack(spacing: 12) {
                                LayoutGlyph(action: action)
                                    .frame(width: 34, height: 22)
                                Text(action.title)
                                Spacer()
                                if services.ui.shortcutConflicts.contains(action.rawValue) {
                                    Label("Used by another app", systemImage: "exclamationmark.triangle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                                ShortcutRecorder(shortcut: shortcutBinding(action), onRecording: recording)
                            }
                        }
                    }
                    .disabled(!settings.shortcutsEnabled)
                }

                Section {
                    Toggle(isOn: binding(\.dragToSnap)) {
                        Text("Snap windows dragged to screen edges")
                        Text("Edges make halves, corners make quarters, the top maximizes and the bottom makes thirds, with a preview as you drag.")
                    }
                    .disabled(NativeTiling.isEnabled)
                    if NativeTiling.isEnabled {
                        LabeledContent {
                            Button("Open Desktop & Dock") { NativeTiling.openSettings() }
                        } label: {
                            Text("macOS is tiling windows itself")
                            Text("To use All Set's snapping instead (thirds, gaps and a preview), turn off \"Drag windows to screen edges to tile\" under Windows in Desktop & Dock.")
                        }
                    }
                } header: {
                    Text("Dragging")
                }

                Section {
                    Button("Reset Shortcuts to Defaults") {
                        store.settings.shortcuts = [:]
                    }
                }
            }
            .dsFormStyle()
        }
    }

    private func recording(_ isRecording: Bool) {
        services.windowManager?.setRecordingShortcut(isRecording)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<WorkspaceSettings, Value>) -> Binding<Value> {
        Binding(get: { services.workspaces.settings[keyPath: keyPath] },
                set: { services.workspaces.settings[keyPath: keyPath] = $0 })
    }

    private func shortcutBinding(_ action: WindowAction) -> Binding<Shortcut?> {
        Binding(get: { services.workspaces.settings.shortcut(for: action) },
                set: { services.workspaces.settings.shortcuts[action] = .some($0) })
    }
}

// MARK: Workspaces

struct WorkspacesPage: View {
    let services: AppServices
    @State private var isSaving = false

    var body: some View {
        let store = services.workspaces
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Workspaces").font(.largeTitle.bold())
                        Text("Save the windows you have open as a workspace, then bring the whole setup back with one click or shortcut.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        isSaving = true
                    } label: {
                        Label("Save Current Layout…", systemImage: "plus.rectangle.on.rectangle")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }

                AccessibilityBanner()

                if store.workspaces.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Arrange your apps the way you like them for a task, like coding or studying.", systemImage: "1.circle.fill")
                        Label("Click Save Current Layout and pick which apps belong.", systemImage: "2.circle.fill")
                        Label("Switch back any time: apps open, windows move into place and everything else hides.", systemImage: "3.circle.fill")
                    }
                    .font(.callout)
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 16).fill(.quaternary.opacity(0.5)))
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 18)], spacing: 18) {
                        ForEach(store.workspaces) { workspace in
                            WorkspaceCard(workspace: workspace, services: services)
                        }
                    }
                }
            }
            .padding(28)
        }
        .sheet(isPresented: $isSaving) {
            SaveWorkspaceSheet(services: services)
        }
    }
}

private struct WorkspaceCard: View {
    let workspace: Workspace
    let services: AppServices

    var body: some View {
        let store = services.workspaces
        let applying = services.ui.applyingWorkspace == workspace.id
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                WorkspaceIcon(symbol: workspace.symbol)
                VStack(alignment: .leading, spacing: 2) {
                    TextField("Name", text: Binding(get: { workspace.name },
                                                    set: { name in store.update(workspace.id) { $0.name = name } }))
                        .textFieldStyle(.plain)
                        .font(.headline)
                    Text("\(workspace.apps.count) apps · \(workspace.apps.reduce(0) { $0 + $1.windows.count }) windows")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    Button("Update to Current Layout") {
                        let apps = services.workspaceController.captureCurrentLayout()
                            .filter { app in workspace.apps.contains { $0.bundleID == app.bundleID } }
                        if !apps.isEmpty { store.update(workspace.id) { $0.apps = apps } }
                    }
                    Toggle("Hide Other Apps", isOn: Binding(get: { workspace.hideOthers },
                                                          set: { hide in store.update(workspace.id) { $0.hideOthers = hide } }))
                    Menu("Icon") {
                        ForEach(Workspace.symbols, id: \.self) { symbol in
                            Button {
                                store.update(workspace.id) { $0.symbol = symbol }
                            } label: {
                                Label(symbol, systemImage: symbol)
                            }
                        }
                    }
                    Divider()
                    Button("Delete", role: .destructive) {
                        store.workspaces.removeAll { $0.id == workspace.id }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            LayoutMiniMap(apps: workspace.apps)

            HStack {
                ShortcutRecorder(shortcut: Binding(get: { workspace.shortcut },
                                                   set: { shortcut in store.update(workspace.id) { $0.shortcut = shortcut } }),
                                 onRecording: { services.windowManager?.setRecordingShortcut($0) })
                if services.ui.shortcutConflicts.contains(workspace.id.uuidString) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .help("Another app uses this shortcut")
                }
                Spacer()
                Button {
                    Task { await services.workspaceController.apply(workspace) }
                } label: {
                    if applying {
                        ProgressView().controlSize(.small).frame(width: 60)
                    } else {
                        Label("Switch", systemImage: "arrow.right.circle.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(services.ui.applyingWorkspace != nil)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.quaternary.opacity(0.5)))
    }
}

private struct SaveWorkspaceSheet: View {
    let services: AppServices
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var symbol = Workspace.symbols[0]
    @State private var apps: [WorkspaceApp] = []
    @State private var included = Set<String>()
    @State private var hideOthers = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Save Workspace").font(.title2.bold())
            if !Accessibility.isTrusted {
                AccessibilityBanner()
            }

            HStack(spacing: 12) {
                WorkspaceIcon(symbol: symbol)
                TextField("Name, e.g. Coding", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 12), spacing: 6) {
                ForEach(Workspace.symbols, id: \.self) { option in
                    Image(systemName: option)
                        .frame(width: 28, height: 28)
                        .background(RoundedRectangle(cornerRadius: 7).fill(option == symbol ? Color.accentColor.opacity(0.3) : .clear))
                        .contentShape(Rectangle())
                        .onTapGesture { symbol = option }
                }
            }

            Text("Apps in this workspace").font(.headline)
            if apps.isEmpty {
                Text(Accessibility.isTrusted ? "No app windows are open. Arrange some windows, then try again." : "Allow access above to see your open windows.")
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(apps) { app in
                            Toggle(isOn: Binding(get: { included.contains(app.bundleID) },
                                                 set: { on in if on { included.insert(app.bundleID) } else { included.remove(app.bundleID) } })) {
                                HStack(spacing: 10) {
                                    AppIcon(bundleIdentifier: app.bundleID, size: 22)
                                    Text(app.name)
                                    Spacer()
                                    Text(app.windows.count == 1 ? "1 window" : "\(app.windows.count) windows")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .toggleStyle(.checkbox)
                        }
                    }
                }
                .frame(maxHeight: 170)
                LayoutMiniMap(apps: apps.filter { included.contains($0.bundleID) })
                    .frame(maxHeight: 150)
            }

            Toggle("Hide other apps when switching to it", isOn: $hideOthers)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    var workspace = Workspace(name: name.trimmingCharacters(in: .whitespaces), symbol: symbol,
                                              apps: apps.filter { included.contains($0.bundleID) })
                    workspace.hideOthers = hideOthers
                    services.workspaces.workspaces.append(workspace)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || included.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 540)
        .onAppear {
            apps = services.workspaceController.captureCurrentLayout()
            included = Set(apps.map(\.bundleID))
        }
    }
}

// MARK: Pieces

/// Explains and requests Accessibility access; hidden once it's granted.
struct AccessibilityBanner: View {
    @State private var isTrusted = Accessibility.isTrusted

    var body: some View {
        VStack {
            if !isTrusted {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Allow All Set to move windows").font(.headline)
                        Text("macOS asks before an app can move other apps' windows. Turn on All Set in Privacy & Security › Accessibility. This page updates as soon as you do.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        HStack {
                            Button("Allow Access…") {
                                Accessibility.requestAccess()
                                Accessibility.openSettings()
                            }
                            .buttonStyle(.borderedProminent)
                            Button("Open Settings") { Accessibility.openSettings() }
                        }
                        .padding(.top, 2)
                    }
                    Spacer(minLength: 0)
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.orange.opacity(0.12)))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.orange.opacity(0.3)))
            }
        }
        .task {
            // macOS doesn't announce the change, so check while visible.
            while !Task.isCancelled {
                let trusted = Accessibility.isTrusted
                if trusted != isTrusted { withMotion(Motion.standard) { isTrusted = trusted } }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

private struct WorkspaceIcon: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 40, height: 40)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.45, green: 0.36, blue: 0.98), Color(red: 0.96, green: 0.36, blue: 0.6)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing)))
    }
}

/// A little screen showing where each window of a workspace goes.
struct LayoutMiniMap: View {
    let apps: [WorkspaceApp]

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.12, green: 0.1, blue: 0.3), Color(red: 0.3, green: 0.15, blue: 0.4)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                ForEach(items.reversed()) { item in
                    let frame = item.frame
                    let rect = CGRect(x: frame.minX * size.width, y: (1 - frame.maxY) * size.height,
                                      width: frame.width * size.width, height: frame.height * size.height)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(.white.opacity(0.16))
                        .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(.white.opacity(0.4), lineWidth: 1))
                        .overlay(AppIcon(bundleIdentifier: item.bundleID, size: max(min(22, rect.height * 0.5, rect.width * 0.5), 8)))
                        .frame(width: max(rect.width, 4), height: max(rect.height, 4))
                        .offset(x: rect.minX, y: rect.minY)
                }
            }
        }
        .aspectRatio(16 / 10, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private struct Item: Identifiable {
        let id: Int
        let bundleID: String
        let frame: CGRect
    }

    /// Front-most first, as saved.
    private var items: [Item] {
        apps.flatMap { app in app.windows.map { (app.bundleID, $0.frame) } }
            .enumerated()
            .map { Item(id: $0.offset, bundleID: $0.element.0, frame: $0.element.1) }
    }
}

/// A miniature screen with the area an action fills highlighted.
struct LayoutGlyph: View {
    let action: WindowAction

    var body: some View {
        Canvas { context, size in
            let screen = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
            context.stroke(RoundedRectangle(cornerRadius: 3).path(in: screen), with: .color(.secondary), lineWidth: 1)
            let inner = screen.insetBy(dx: 2.5, dy: 2.5)
            // Lay out on a pretend 1000×600 screen, then scale into the glyph.
            let visible = CGRect(x: 0, y: 0, width: 1000, height: 600)
            let window = CGRect(x: 300, y: 150, width: 400, height: 300)
            guard let target = WindowLayout.frame(for: action, window: window, visible: visible, cycle: false) else { return }
            let rect = CGRect(x: inner.minX + target.minX / 1000 * inner.width,
                              y: inner.minY + (1 - target.maxY / 600) * inner.height,
                              width: target.width / 1000 * inner.width,
                              height: target.height / 600 * inner.height)
            context.fill(RoundedRectangle(cornerRadius: 1.5).path(in: rect), with: .color(.accentColor))
        }
        .overlay {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 10, weight: .bold)).foregroundStyle(Color.accentColor)
            }
        }
    }

    private var symbol: String? {
        switch action {
        case .restore: "arrow.uturn.backward"
        case .nextDisplay: "arrow.right"
        case .previousDisplay: "arrow.left"
        default: nil
        }
    }
}

/// Click, then press a key combination. Esc cancels; Delete clears.
struct ShortcutRecorder: View {
    @Binding var shortcut: Shortcut?
    var onRecording: (Bool) -> Void = { _ in }

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 4) {
            Button {
                isRecording ? stop() : start()
            } label: {
                Text(isRecording ? "Type shortcut…" : shortcut?.display ?? "Record Shortcut")
                    .font(.system(size: 12, weight: .medium))
                    .monospaced(shortcut != nil && !isRecording)
                    .frame(minWidth: 96)
            }
            .buttonStyle(.bordered)
            .tint(isRecording ? .accentColor : nil)
            if shortcut != nil, !isRecording {
                Button {
                    shortcut = nil
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove shortcut")
            }
        }
        .onDisappear { if isRecording { stop() } }
    }

    private func start() {
        isRecording = true
        onRecording(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated {
                handle(event)
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
        onRecording(false)
    }

    private func handle(_ event: NSEvent) {
        let flags = event.modifierFlags
        var modifiers: KeyModifiers = []
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.command) { modifiers.insert(.command) }

        switch event.keyCode {
        case 53: // Esc
            stop()
            return
        case 51 where modifiers.isEmpty: // Delete
            shortcut = nil
            stop()
            return
        default:
            break
        }
        // Shortcuts need ⌃, ⌥ or ⌘, or they'd swallow ordinary typing.
        guard !modifiers.subtracting(.shift).isEmpty else {
            NSSound.beep()
            return
        }
        shortcut = Shortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers, key: Self.name(of: event))
        stop()
    }

    private static func name(of event: NSEvent) -> String {
        let special: [UInt16: String] = [
            123: "←", 124: "→", 125: "↓", 126: "↑", 36: "↩", 76: "⌤", 51: "⌫", 117: "⌦", 48: "⇥", 49: "Space",
            115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10",
            103: "F11", 111: "F12",
        ]
        if let name = special[event.keyCode] { return name }
        return (event.charactersIgnoringModifiers ?? "?").uppercased()
    }
}
