import AllSetCore
import AppKit
import SwiftUI

/// Every page of the main window.
enum AppPage: Hashable {
    // Dynamic Island
    case island
    case activities
    // Widgets
    /// Whole-desktop looks.
    case themes
    /// One theme set's page.
    case themeSet(String)
    /// The widget gallery, for one category or (nil) all of them.
    case gallery(WidgetCategory?)
    case art
    /// Customizing a widget that's on the desktop.
    case widget(UUID)
    case widgetAppearance
    // Wallpaper
    case wallpaper
    case wallpaperOptions
    // Workspace
    case snapping
    case workspaces
    // Tools
    case clipboard
    case shelf
    case mixer
    case knocks
    case notes
    case screenshot
    // System
    case monitor
    case general
    case about
}

/// The one window of the app, opened from the Dock, the menu bar, the notch
/// and the widgets.
@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    static let shared = MainWindowController()

    private var window: NSWindow?

    /// Closing lets the whole window go. Kept, a closed window's pages stay
    /// alive unseen: no `onDisappear` runs, so a page that asked for live
    /// system readings kept the monitor sampling every two seconds for the
    /// rest of the session, and every picture it had shown stayed in memory.
    /// The page on show is kept in `UIState`, so reopening lands on it again.
    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow, closing === window else { return }
        closing.delegate = nil
        closing.contentViewController = nil
        window = nil
        // Theme previews and the pictures pages showed were only for this
        // window; desktop widgets keep the recent ones they use.
        services?.releaseCachedPictures(keeping: 0.25)
    }

    private weak var services: AppServices?

    func show(services: AppServices) {
        self.services = services
        if window == nil {
            let controller = NSHostingController(rootView: MainView(services: services, ui: services.ui))
            // The window's size limits are set here, not derived from the
            // SwiftUI content on every layout pass: pages whose size depends on
            // the window's width (adaptive grids) could make that loop until
            // AppKit gave up and ended the app.
            controller.sizingOptions = []
            let window = NSWindow(contentViewController: controller)
            window.title = "All Set"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.isReleasedWhenClosed = false
            window.contentMinSize = NSSize(width: 900, height: 600)
            window.setContentSize(NSSize(width: 1120, height: 760))
            window.center()
            window.setFrameAutosaveName("AllSetMain")
            window.delegate = self
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

struct MainView: View {
    let services: AppServices
    @Bindable var ui: UIState

    var body: some View {
        NavigationSplitView {
            List(selection: $ui.page) {
                Section("Dynamic Island") {
                    Label("Dynamic Island", systemImage: "capsule.fill").tag(AppPage.island)
                    Label("Live Activities", systemImage: "waveform").tag(AppPage.activities)
                }
                Section("Widgets") {
                    Label("Themes", systemImage: "wand.and.stars").tag(AppPage.themes)
                    Label("Gallery", systemImage: "square.grid.2x2.fill").tag(AppPage.gallery(nil))
                    ForEach(WidgetCategory.allCases) { category in
                        Label(category.title, systemImage: category.symbol)
                            .padding(.leading, 12)
                            .tag(AppPage.gallery(category))
                    }
                    Label("Art", systemImage: "paintpalette.fill")
                        .badge(ArtPiece.all.count)
                        .tag(AppPage.art)
                    Label("Look & Layout", systemImage: "paintbrush.fill").tag(AppPage.widgetAppearance)
                }
                Section("Wallpaper") {
                    Label("Live Wallpaper", systemImage: "photo.artframe").tag(AppPage.wallpaper)
                    Label("Wallpaper Options", systemImage: "slider.horizontal.3").tag(AppPage.wallpaperOptions)
                }
                Section("Workspace") {
                    Label("Window Snapping", systemImage: "rectangle.split.2x1.fill").tag(AppPage.snapping)
                    Label("Workspaces", systemImage: "square.stack.3d.down.right.fill").tag(AppPage.workspaces)
                }
                Section("Tools") {
                    Label("Clipboard", systemImage: "doc.on.clipboard.fill")
                        .badge(services.clipboard.items.count)
                        .tag(AppPage.clipboard)
                    Label("Shelf", systemImage: "tray.full.fill")
                        .badge(services.shelf.items.count)
                        .tag(AppPage.shelf)
                    Label("Sound Mixer", systemImage: "slider.vertical.3").tag(AppPage.mixer)
                    Label("TapTap", systemImage: "hand.tap.fill").tag(AppPage.knocks)
                    Label("AI Screenshot", systemImage: "camera.viewfinder").tag(AppPage.screenshot)
                    Label("Notes", systemImage: "note.text")
                        .badge(services.notes.notes.filter { !$0.isDone }.count)
                        .tag(AppPage.notes)
                }
                Section("On Your Desktop") {
                    if services.widgets.widgets.isEmpty {
                        Text("No widgets yet").foregroundStyle(.secondary)
                    }
                    ForEach(services.widgets.widgets) { instance in
                        HStack(spacing: 6) {
                            Label {
                                Text(instance.kind.title) + Text("  \(instance.size.title)").foregroundStyle(.secondary)
                            } icon: {
                                Image(systemName: instance.kind.symbol)
                            }
                            Spacer(minLength: 4)
                            Button {
                                removeWidget(instance.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                            .help("Remove from the desktop")
                            .accessibilityLabel("Remove \(instance.kind.title) from the desktop")
                        }
                        .tag(AppPage.widget(instance.id))
                    }
                }
                Section("System") {
                    Label("Monitor", systemImage: "gauge.with.dots.needle.50percent").tag(AppPage.monitor)
                    Label("General", systemImage: "gearshape.fill").tag(AppPage.general)
                    Label("About", systemImage: "info.circle.fill").tag(AppPage.about)
                }
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 280)
        } detail: {
            detail(ui.page ?? .island)
                .frame(minWidth: 660, minHeight: 540)
                .safeAreaInset(edge: .top, spacing: 0) {
                    if let error = services.widgets.saveError {
                        Label("Your widget layout couldn't be saved: \(error)", systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.orange.opacity(0.18))
                            .accessibilityAddTraits(.isStaticText)
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if let removed = ui.removedWidget {
                        RemovedWidgetBar(removed: removed, services: services)
                    }
                }
                .navigationTitle(title(for: ui.page ?? .island))
                .background(AppBackground())
        }
        // The main window is always dark: the content (art, wallpapers,
        // themes) leads, and a dark canvas is what lets it. Desktop widgets
        // and the notch keep their own appearance.
        .preferredColorScheme(.dark)
        .toolbar {
            ToolbarItemGroup {
                Toggle(isOn: Binding(get: { services.settings.showWidgets },
                                     set: { services.settings.showWidgets = $0 })) {
                    Label("Show Widgets", systemImage: services.settings.showWidgets ? "eye" : "eye.slash")
                }
                .help("Show widgets on the desktop")
                Button {
                    ui.isArrangingWidgets.toggle()
                } label: {
                    Label(ui.isArrangingWidgets ? "Done Arranging" : "Arrange Widgets", systemImage: "hand.draw")
                }
                .help("Drag widgets around the desktop")
            }
        }
    }

    /// One click, no confirmation: the widget leaves the desktop (Undo
    /// brings it back), and if its settings were open the window moves to
    /// the gallery.
    private func removeWidget(_ id: UUID) {
        withMotion(Motion.quick) { services.removeWidget(id) }
    }

    @ViewBuilder
    private func detail(_ page: AppPage) -> some View {
        switch page {
        case .island:
            IslandPage(services: services)
        case .activities:
            FormPage { ActivitySettings(settings: services.settings, media: services.media) }
        case .themes:
            ThemesPage(services: services)
        case .themeSet(let id):
            ThemeDetailPage(setID: id, services: services)
                .id(id)
        case .gallery(let category):
            GalleryPage(category: category, services: services)
        case .art:
            ArtLibraryPage(services: services)
        case .widget(let id):
            WidgetInspector(id: id, services: services)
        case .widgetAppearance:
            FormPage { WidgetSettings(settings: services.settings, services: services) }
        case .wallpaper:
            LiveWallpaperPage(services: services, tab: services.ui.wallpaperTab)
        case .wallpaperOptions:
            WallpaperOptionsPage(services: services)
        case .snapping:
            WindowSnappingPage(services: services)
        case .workspaces:
            WorkspacesPage(services: services)
        case .clipboard:
            ClipboardPage(services: services)
        case .shelf:
            ShelfPage(services: services)
        case .mixer:
            SoundMixerPage(services: services)
        case .knocks:
            KnockPage(services: services)
        case .notes:
            NotesPage(notes: services.notes)
        case .screenshot:
            ScreenshotPage(services: services)
        case .monitor:
            MonitorPage(services: services)
        case .general:
            FormPage { GeneralSettings(settings: services.settings) }
        case .about:
            FormPage { AboutSettings() }
        }
    }

    private func title(for page: AppPage) -> String {
        switch page {
        case .island: "Dynamic Island"
        case .activities: "Live Activities"
        case .themes: "Themes"
        case .themeSet(let id): ThemeLibrary.set(id)?.name ?? "Theme"
        case .gallery(let category): category?.title ?? "Widget Gallery"
        case .art: "Art"
        case .widget(let id): services.widgets.instance(id).map { "Customize \($0.kind.title)" } ?? "Widget"
        case .widgetAppearance: "Look & Layout"
        case .wallpaper: "Live Wallpaper"
        case .wallpaperOptions: "Wallpaper Options"
        case .snapping: "Window Snapping"
        case .workspaces: "Workspaces"
        case .clipboard: "Clipboard"
        case .shelf: "Shelf"
        case .mixer: "Sound Mixer"
        case .knocks: "TapTap"
        case .notes: "Notes"
        case .screenshot: "AI Screenshot"
        case .monitor: "Monitor"
        case .general: "General"
        case .about: "About"
        }
    }
}

/// "Removed Clock. Undo" for a few seconds after a widget leaves the desktop.
private struct RemovedWidgetBar: View {
    let removed: RemovedWidget
    let services: AppServices

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: removed.instance.kind.symbol).foregroundStyle(.secondary)
            Text("Removed \(removed.instance.kind.title) from the desktop.")
            Spacer()
            Button("Undo") { withMotion(Motion.quick) { services.undoRemoveWidget() } }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
        .task(id: removed.id) {
            try? await Task.sleep(for: .seconds(8))
            if services.ui.removedWidget?.id == removed.id {
                withMotion(Motion.quick) { services.ui.removedWidget = nil }
            }
        }
    }
}

/// A settings page: grouped form sections.
struct FormPage<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        Form { content }
            .dsFormStyle()
    }
}
