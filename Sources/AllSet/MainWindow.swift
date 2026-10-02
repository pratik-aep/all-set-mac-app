import AllSetCore
import AppKit
import SwiftUI

/// Every page of the main window.
enum AppPage: Hashable {
    // Dynamic Island
    case island
    case activities
    // Widgets
    /// The Desktop section's front page.
    case home
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
    /// The widgets on the desktop now.
    case desktop
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
    case lidPlane
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

    /// No title or bar: the page runs to the top, the navigation floats
    /// beneath the window buttons, and each page names itself.
    static func dress(_ window: NSWindow) {
        window.title = "All Set"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(DS.Surface.canvasLift)
    }

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
            Self.dress(window)
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
        GeometryReader { geometry in
            let margin = DS.Space.pageMargin(for: geometry.size.width)
            // A page swaps at once and eases in under a Core Animation veil
            // (`PageVeil`); the navigation stays put above it.
            ZStack {
                detail(ui.page ?? .island)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .id(ui.page)
            }
            .overlay { PageVeil(page: ui.page).allowsHitTesting(false) }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    FloatingNav(services: services, ui: ui, margin: margin)
                    if let error = services.widgets.saveError {
                        Label("Your widget layout couldn't be saved: \(error)", systemImage: "exclamationmark.triangle.fill")
                            .dsText(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, DS.Space.m)
                            .padding(.vertical, DS.Space.xs)
                            .background(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous).fill(Color.orange.opacity(0.22)))
                            .padding(.horizontal, margin)
                            .padding(.bottom, DS.Space.xs)
                            .accessibilityAddTraits(.isStaticText)
                    }
                }
            }
            .overlay(alignment: .top) {
                if let toast = ui.toast {
                    ToastView(toast: toast, ui: ui).padding(.top, 64)
                }
            }
            .overlay {
                if ui.isSearching { SearchOverlay(services: services, ui: ui) }
            }
            .background {
                Button("Search") { withMotion(Motion.quick) { ui.isSearching.toggle() } }
                    .keyboardShortcut("k", modifiers: .command)
                    .opacity(0).accessibilityHidden(true)
            }
            .overlay(alignment: .bottom) {
                if let removed = ui.removedWidget {
                    RemovedWidgetBar(removed: removed, services: services)
                        .padding(.bottom, DS.Space.l)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .background(WindowBackdrop(paused: ui.performance.pausesDecorativeMotion))
        .environment(ui)
        // The main window is always dark: the content (art, wallpapers,
        // themes) leads, and a dark canvas is what lets it. Desktop widgets
        // and the notch keep their own appearance.
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func detail(_ page: AppPage) -> some View {
        switch page {
        case .island:
            IslandPage(services: services)
        case .activities:
            FormPage(eyebrow: "Island", title: "Live Activities", subtitle: "What the notch shows around itself while things happen.") {
                ActivitySettings(settings: services.settings, media: services.media)
            }
        case .home:
            HomePage(services: services)
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
            FormPage(eyebrow: "Desktop", title: "Look & Layout", subtitle: "How every widget looks and lines up, all at once.") {
                WidgetSettings(settings: services.settings, services: services)
            }
        case .desktop:
            DesktopWidgetsPage(services: services)
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
        case .lidPlane:
            LidPlanePage(services: services)
        case .general:
            FormPage(eyebrow: "System", title: "General", subtitle: "Startup, the Dock and the menu bar.") {
                GeneralSettings(settings: services.settings)
            }
        case .about:
            FormPage(eyebrow: "System", title: "About") { AboutSettings() }
        }
    }
}

/// "Removed Clock. Undo" for a few seconds after a widget leaves the desktop:
/// a floating capsule at the bottom of the window.
private struct RemovedWidgetBar: View {
    let removed: RemovedWidget
    let services: AppServices

    var body: some View {
        GlassPanel(cornerRadius: 22, padding: 0) {
            HStack(spacing: DS.Space.s) {
                Image(systemName: removed.instance.kind.symbol).foregroundStyle(DS.Ink.secondary)
                Text("Removed \(removed.instance.kind.title) from the desktop.").dsText(.body)
                Button("Undo") { withMotion(Motion.quick) { services.undoRemoveWidget() } }
                    .buttonStyle(.pillProminent)
            }
            .padding(.leading, DS.Space.m)
            .padding(.trailing, DS.Space.xxs + 1)
            .frame(height: 44)
        }
        .dsElevated()
        .task(id: removed.id) {
            try? await Task.sleep(for: .seconds(8))
            if services.ui.removedWidget?.id == removed.id {
                withMotion(Motion.quick) { services.ui.removedWidget = nil }
            }
        }
    }
}

/// A settings page: its header and any lead content (a preview, a stage) on
/// the canvas, then grouped form sections.
struct FormPage<Lead: View, Content: View>: View {
    var eyebrow: String?
    var title: String?
    var subtitle: String?
    @ViewBuilder var lead: Lead
    @ViewBuilder var content: Content

    var body: some View {
        Form {
            if title != nil || Lead.self != EmptyView.self {
                // A section of nothing but a header: grouped forms draw headers
                // on the canvas, outside the rounded boxes.
                Section {
                } header: {
                    VStack(alignment: .leading, spacing: DS.Space.l) {
                        if let title { PageHeader(eyebrow: eyebrow, title: title, subtitle: subtitle) }
                        lead
                    }
                    .textCase(nil)
                    .padding(.bottom, DS.Space.m)
                }
            }
            content
        }
        .dsFormStyle()
    }
}

extension FormPage where Lead == EmptyView {
    init(eyebrow: String? = nil, title: String? = nil, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(eyebrow: eyebrow, title: title, subtitle: subtitle, lead: { EmptyView() }, content: content)
    }
}
