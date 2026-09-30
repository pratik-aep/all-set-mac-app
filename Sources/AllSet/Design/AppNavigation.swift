import AllSetCore
import SwiftUI

// The main window's floating navigation: five places along the top, and the
// pages of the current one as pills beneath. `AppPage` stays the single
// source of truth, so deep links, `openWindow` and `-openPage` are unchanged.

/// The five places of the main window.
enum NavSection: String, CaseIterable, Identifiable {
    case island, desktop, workspace, tools, system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .island: "Island"
        case .desktop: "Desktop"
        case .workspace: "Workspace"
        case .tools: "Tools"
        case .system: "System"
        }
    }

    var symbol: String {
        switch self {
        case .island: "capsule.fill"
        case .desktop: "macwindow"
        case .workspace: "rectangle.split.2x1.fill"
        case .tools: "wrench.and.screwdriver.fill"
        case .system: "gearshape.fill"
        }
    }

    /// Where a click on the section lands the first time.
    var home: AppPage {
        switch self {
        case .island: .island
        case .desktop: .themes
        case .workspace: .snapping
        case .tools: .clipboard
        case .system: .monitor
        }
    }

    static func of(_ page: AppPage) -> NavSection {
        switch page {
        case .island, .activities: .island
        case .themes, .themeSet, .gallery, .art, .widget, .widgetAppearance, .wallpaper, .wallpaperOptions, .desktop: .desktop
        case .snapping, .workspaces: .workspace
        case .clipboard, .shelf, .mixer, .knocks, .notes, .screenshot: .tools
        case .monitor, .general, .about: .system
        }
    }
}

/// One page's pill in the second row.
struct NavItem: Identifiable {
    let page: AppPage
    let title: String
    let symbol: String
    var badge = 0

    var id: String { title }

    /// Detail pages light up the pill they belong to.
    func matches(_ current: AppPage) -> Bool {
        switch (page, current) {
        case (.themes, .themeSet), (.gallery, .gallery), (.desktop, .widget): true
        default: page == current
        }
    }

    @MainActor
    static func items(in section: NavSection, services: AppServices) -> [NavItem] {
        switch section {
        case .island:
            [NavItem(page: .island, title: "Dynamic Island", symbol: "capsule.fill"),
             NavItem(page: .activities, title: "Live Activities", symbol: "waveform")]
        case .desktop:
            [NavItem(page: .themes, title: "Themes", symbol: "wand.and.stars"),
             NavItem(page: .gallery(nil), title: "Widgets", symbol: "square.grid.2x2.fill"),
             NavItem(page: .art, title: "Art", symbol: "paintpalette.fill"),
             NavItem(page: .wallpaper, title: "Wallpaper", symbol: "photo.artframe"),
             NavItem(page: .widgetAppearance, title: "Look & Layout", symbol: "paintbrush.fill"),
             NavItem(page: .wallpaperOptions, title: "Wallpaper Options", symbol: "slider.horizontal.3"),
             NavItem(page: .desktop, title: "On Your Desktop", symbol: "rectangle.on.rectangle", badge: services.widgets.widgets.count)]
        case .workspace:
            [NavItem(page: .snapping, title: "Window Snapping", symbol: "rectangle.split.2x1.fill"),
             NavItem(page: .workspaces, title: "Workspaces", symbol: "square.stack.3d.down.right.fill")]
        case .tools:
            [NavItem(page: .clipboard, title: "Clipboard", symbol: "doc.on.clipboard.fill", badge: services.clipboard.items.count),
             NavItem(page: .shelf, title: "Shelf", symbol: "tray.full.fill", badge: services.shelf.items.count),
             NavItem(page: .mixer, title: "Sound Mixer", symbol: "slider.vertical.3"),
             NavItem(page: .knocks, title: "TapTap", symbol: "hand.tap.fill"),
             NavItem(page: .screenshot, title: "AI Screenshot", symbol: "camera.viewfinder"),
             NavItem(page: .notes, title: "Notes", symbol: "note.text", badge: services.notes.notes.filter { !$0.isDone }.count)]
        case .system:
            [NavItem(page: .monitor, title: "Monitor", symbol: "gauge.with.dots.needle.50percent"),
             NavItem(page: .general, title: "General", symbol: "gearshape.fill"),
             NavItem(page: .about, title: "About", symbol: "info.circle.fill")]
        }
    }
}

/// The top of the main window: the sections in a glass capsule, desktop
/// switches on the trailing edge, and the section's pages beneath.
struct FloatingNav: View {
    let services: AppServices
    @Bindable var ui: UIState
    let margin: CGFloat

    /// The page last shown in each section, so switching back returns to it.
    @State private var lastPage: [NavSection: AppPage] = [:]
    @Namespace private var selection

    private var page: AppPage { ui.page ?? .island }
    private var section: NavSection { .of(page) }

    var body: some View {
        VStack(spacing: DS.Space.s) {
            ZStack {
                HStack(spacing: DS.Space.s) {
                    Text("All Set")
                        .font(.system(size: 15, weight: .bold))
                        .tracking(-0.2)
                        .foregroundStyle(DS.Ink.primary)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 0)
                    desktopSwitches
                }
                sections
            }
            pages
        }
        .padding(.horizontal, margin)
        .padding(.top, DS.Space.xxs)
        .padding(.bottom, DS.Space.s)
        .background {
            // Content scrolls away beneath the navigation: a fade, not a blur.
            LinearGradient(stops: [.init(color: DS.Surface.canvasLift, location: 0),
                                   .init(color: DS.Surface.canvasLift.opacity(0.94), location: 0.7),
                                   .init(color: DS.Surface.canvasLift.opacity(0), location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .top)
        }
        .onChange(of: ui.page) { _, new in
            if let new { lastPage[.of(new)] = new }
        }
    }

    private var sections: some View {
        GlassPanel(cornerRadius: 22, padding: DS.Space.xxs) {
            HStack(spacing: 2) {
                ForEach(Array(NavSection.allCases.enumerated()), id: \.element) { index, item in
                    let isSelected = item == section
                    Button {
                        withMotion(Motion.responsive) { ui.page = destination(of: item) }
                    } label: {
                        Label(item.title, systemImage: item.symbol)
                            .labelStyle(SectionLabelStyle())
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(isSelected ? DS.Ink.primary : DS.Ink.secondary)
                            .padding(.horizontal, DS.Space.s + 2)
                            .frame(height: 34)
                            .background {
                                if isSelected {
                                    Capsule().fill(.white.opacity(0.14))
                                        .matchedGeometryEffect(id: "section", in: selection)
                                }
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(PressableStyle())
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                    .help("\(item.title) (⌘\(index + 1))")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
    }

    /// The section's last page, unless it was a widget that has since left.
    private func destination(of item: NavSection) -> AppPage {
        guard let last = lastPage[item] else { return item.home }
        if case .widget(let id) = last, services.widgets.instance(id) == nil { return .desktop }
        return last
    }

    /// Show or hide the widgets, and arrange them: always a click away.
    private var desktopSwitches: some View {
        GlassPanel(cornerRadius: 21, padding: DS.Space.xxs) {
            HStack(spacing: 2) {
                navIcon(services.settings.showWidgets ? "eye" : "eye.slash",
                        isOn: !services.settings.showWidgets,
                        help: services.settings.showWidgets ? "Hide widgets on the desktop" : "Show widgets on the desktop") {
                    services.settings.showWidgets.toggle()
                }
                navIcon("hand.draw", isOn: ui.isArrangingWidgets,
                        help: ui.isArrangingWidgets ? "Done arranging" : "Drag widgets around the desktop") {
                    ui.isArrangingWidgets.toggle()
                }
            }
        }
    }

    private func navIcon(_ symbol: String, isOn: Bool, help: String, action: @escaping @MainActor () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(isOn ? Color.black.opacity(0.88) : DS.Ink.primary)
                .frame(width: 34, height: 34)
                .background(Circle().fill(isOn ? Color.white.opacity(0.92) : .clear))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .help(help)
        .accessibilityLabel(help)
    }

    /// The section's pages, centred when they fit and scrolling when not.
    private var pages: some View {
        let items = NavItem.items(in: section, services: services)
        let row = HStack(spacing: DS.Space.xs) {
            ForEach(items) { item in
                PagePill(item: item, isSelected: item.matches(page)) {
                    withMotion(Motion.quick) { ui.page = item.page }
                }
            }
        }
        return ViewThatFits(in: .horizontal) {
            row.frame(maxWidth: .infinity)
            ScrollView(.horizontal, showsIndicators: false) { row.padding(.vertical, 1) }
        }
    }
}

/// Icon and title side by side; the icon goes first when space is short.
private struct SectionLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                configuration.icon.font(.system(size: 12, weight: .semibold))
                configuration.title
            }
            configuration.title
        }
    }
}

/// A page in the second row: a filter-style pill with an optional count.
private struct PagePill: View {
    let item: NavItem
    let isSelected: Bool
    let action: @MainActor () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: item.symbol).font(.system(size: 11, weight: .semibold))
                Text(item.title)
                if item.badge > 0 {
                    Text("\(item.badge)")
                        .font(.system(size: 10, weight: .bold).monospacedDigit())
                        .padding(.horizontal, 5)
                        .frame(minWidth: 16, minHeight: 16)
                        .background(Capsule().fill(isSelected ? Color.black.opacity(0.12) : DS.Surface.hover))
                }
            }
            .font(.system(size: 12, weight: .medium))
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(isSelected ? Color.black.opacity(0.88) : DS.Ink.secondary)
            .padding(.horizontal, DS.Space.s)
            .frame(height: 28)
            .background(Capsule().fill(isSelected ? Color.white.opacity(0.92) : DS.Surface.raised))
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(item.badge > 0 ? "\(item.title), \(item.badge)" : item.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
