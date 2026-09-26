import AllSetCore
import AppKit
import Observation

/// UI state shared between windows: which page of the main window is showing,
/// and whether the desktop widgets are being arranged.
@Observable @MainActor
final class UIState {
    var page: AppPage? = .island
    var isArrangingWidgets = false
    /// False while the live wallpaper is paused to save energy.
    var wallpaperPlaying = true
    /// Window actions (by raw value) and workspaces (by id) whose shortcut
    /// another app already owns.
    var shortcutConflicts = Set<String>()
    var applyingWorkspace: UUID?
    /// The layout from before a theme's starter set replaced it, for Undo.
    var layoutBeforeTheme: [WidgetInstance]?
    /// The widget size from before that, for Undo.
    var scaleBeforeTheme: Double?
    /// A theme set being tried on the desktop, with what to go back to.
    var themePreview: ThemePreview?
    /// How hard to save energy, from Low Power Mode, Reduce Motion and the charger.
    var energy = EnergyMode()
}

/// What the Mac asks of apps right now, energy-wise.
struct EnergyMode: Equatable {
    var isLowPower = false
    var reducesMotion = false
    var isOnBattery = false

    /// Stop decorative motion entirely: Low Power Mode, or Reduce Motion is on.
    var pausesMotion: Bool { isLowPower || reducesMotion }

    static func current(onBattery: Bool) -> EnergyMode {
        EnergyMode(isLowPower: ProcessInfo.processInfo.isLowPowerModeEnabled,
                   reducesMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                   isOnBattery: onBattery)
    }
}

/// The app's long-lived models, shared by the notch, widgets, menu bar and settings.
@MainActor
final class AppServices {
    let settings = AppSettings()
    let monitor = SystemMonitor()
    let media = MediaController()
    let volume = VolumeMonitor()
    let power = PowerSourceMonitor()
    let widgets = WidgetStore(fileURL: AppServices.widgetsFileURL)
    let weather = WeatherService()
    let themeStats = ThemeStats()
    /// The person's own photos for each theme set.
    let themePhotos = ThemePhotos()
    private(set) lazy var themePreviews = ThemePreviewCache(photos: themePhotos)
    let github = GitHubService()
    let status = StatusService()
    /// Wallpaper-aware accents for design themes.
    let themes = ThemeManager()
    let calendar = CalendarService()
    let images = ImageLibrary()
    let search = PhotoSearch()
    let wallpaper = WallpaperStore()
    let aerials = AerialCatalog()
    let workspaces = WorkspaceStore()
    let clipboard = ClipboardStore()
    let shelf = ShelfStore()
    let appVolumes = AppVolumeStore()
    lazy var mixer = MixerController(store: appVolumes, output: volume)
    let knockStore = KnockStore()
    let notes = NotesStore()
    lazy var knocks = KnockController(services: self)
    lazy var clipboardMonitor = ClipboardMonitor(services: self)
    lazy var workspaceController = WorkspaceController(services: self)
    /// Set by the app delegate.
    weak var windowManager: WindowManager?
    let ui = UIState()
    /// Set by the app delegate so pages can drive the island (for "Try it").
    weak var notch: NotchController?

    func start() {
        startWatchingEnergy()
        applyMonitorPace()
        observe({ [settings] in settings.refreshInterval }) { [weak self] _ in self?.applyMonitorPace() }
        monitor.start()
        media.start()
        volume.start()
        mixer.start()
        knocks.start()
        power.start()
        calendar.start()
        themes.start(services: self)
    }

    func stop() {
        knocks.stop()
        notes.save()
        mixer.stop()
        media.stop()
        monitor.stop()
        widgets.saveNow()
        clipboard.save()
    }

    // MARK: Energy

    private var energyObservers: [NSObjectProtocol] = []

    private func startWatchingEnergy() {
        let update: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.updateEnergy() }
        }
        energyObservers = [
            NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main, using: update),
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main, using: update),
        ]
        observe({ [power] in power.state?.isPluggedIn }) { [weak self] _ in self?.updateEnergy() }
        updateEnergy()
    }

    private func updateEnergy() {
        let mode = EnergyMode.current(onBattery: power.state.map { !$0.isPluggedIn } ?? false)
        guard mode != ui.energy else { return }
        ui.energy = mode
        applyMonitorPace()
    }

    /// On battery, live stats refresh at most once a second and idle
    /// sampling slows down; plugged in, they follow the setting.
    private func applyMonitorPace() {
        let saving = ui.energy.isOnBattery || ui.energy.isLowPower
        monitor.activeInterval = saving ? max(settings.refreshInterval, 1) : settings.refreshInterval
        monitor.idleInterval = ui.energy.isLowPower ? 10 : saving ? 5 : 3
    }

    private static var widgetsFileURL: URL {
        #if DEBUG
        // `AllSet -widgetsFile /path/layout.json` tries a layout without
        // touching the real one.
        if let path = UserDefaults.standard.string(forKey: "widgetsFile") {
            return URL(fileURLWithPath: path)
        }
        #endif
        return WidgetStore.defaultFileURL
    }

    /// Brings up the main window, optionally on a given page.
    func openWindow(_ page: AppPage? = nil) {
        if let page { ui.page = page }
        MainWindowController.shared.show(services: self)
    }

    /// Dresses the desktop in a theme: every widget, the font and corners,
    /// and (if asked) the wallpaper. With `useKit`, the theme's own starter
    /// layout replaces the widgets, which Undo can bring back.
    func apply(_ theme: WidgetTheme, wallpaper setsWallpaper: Bool, useKit: Bool) {
        settings.widgetFont = theme.font
        settings.widgetCornerRadius = theme.cornerRadius
        if useKit {
            let screen = NSScreen.screens.first
            ui.layoutBeforeTheme = widgets.widgets
            ui.scaleBeforeTheme = settings.widgetScale
            widgets.replaceAll(with: fittedToScreen(theme.kitWidgets(screenName: screen?.localizedName, bounds: Self.unbounded)))
        } else {
            for widget in widgets.widgets {
                widgets.update(widget.id) { $0 = theme.styled($0) }
            }
        }
        if setsWallpaper { wallpaper.set(theme.wallpaper) }
        settings.widgetTheme = theme.id
        settings.showWidgets = true
    }

    /// Draws every widget that has a card in a design theme, and makes it the
    /// theme for new widgets. Kinds with their own backgrounds keep them.
    func apply(_ theme: DesignTheme, wallpaper setsWallpaper: Bool) {
        for widget in widgets.widgets where !widget.kind.isFreeform && !widget.kind.paintsOwnBackground {
            widgets.update(widget.id) { widget in
                widget.options.designTheme = theme.id
                // The theme's own accent, unless it follows the wallpaper anyway.
                widget.options.accent = nil
            }
        }
        if setsWallpaper, let source = theme.wallpaper { wallpaper.set(source) }
        settings.widgetDesignTheme = theme.id
        settings.widgetTheme = nil
        settings.showWidgets = true
    }

    /// Follows an `allset://` link.
    func handle(_ link: DeepLink) {
        switch link {
        case .page(let name):
            let pages: [String: AppPage] = [
                "home": .island, "island": .island, "themes": .themes, "gallery": .gallery(nil), "monitor": .monitor,
                "wallpaper": .wallpaper, "photos": .photos, "art": .art, "clipboard": .clipboard, "notes": .notes,
                "workspaces": .workspaces, "mixer": .mixer, "settings": .general,
            ]
            openWindow(pages[name] ?? WidgetCategory(rawValue: name).map { .gallery($0) } ?? .island)
        case .widget(let id):
            openWindow(widgets.instance(id) != nil ? .widget(id) : .gallery(nil))
        case .arrange:
            ui.isArrangingWidgets = true
        case .fit:
            fitWidgetsToScreen()
        case .theme(let id):
            if let theme = DesignTheme.named(id) {
                apply(theme, wallpaper: false)
            } else if let setup = WidgetTheme.named(id) {
                apply(setup, wallpaper: false, useKit: false)
            } else if let set = ThemeLibrary.set(id) {
                install(set, mode: .restyle, wallpaper: false)
            }
        case .focus(let action):
            guard let focus = widgets.widgets.first(where: { $0.kind == .focus }) else { return }
            widgets.update(focus.id) { widget in
                switch action {
                case .start: widget.options.focus.start(at: .now, focusMinutes: widget.options.focusMinutes, breakMinutes: widget.options.breakMinutes)
                case .pause: widget.options.focus.pause(at: .now)
                case .reset: widget.options.focus.reset()
                }
            }
        }
    }

    /// Puts back the widgets a theme's starter set replaced.
    func undoThemeLayout() {
        guard let previous = ui.layoutBeforeTheme else { return }
        widgets.replaceAll(with: previous)
        if let scale = ui.scaleBeforeTheme { settings.widgetScale = scale }
        ui.layoutBeforeTheme = nil
        ui.scaleBeforeTheme = nil
    }

    /// Puts a widget in the first free spot on the primary screen.
    @discardableResult
    func addWidget(_ instance: WidgetInstance) -> WidgetInstance {
        var instance = instance
        // New widgets join the chosen design theme.
        if let theme = settings.widgetDesignTheme, instance.options.designTheme == nil,
           !instance.kind.isFreeform, !instance.kind.paintsOwnBackground, instance.material != .clear {
            instance.options.designTheme = theme
        }
        if let screen = NSScreen.screens.first {
            // Offsets are in layout points: the screen, divided by the widget size.
            let occupied = widgets.widgets
                .filter { $0.screenName == screen.localizedName || $0.screenName == nil }
                .map { CGRect(origin: $0.offset, size: $0.size.dimensions) }
            let scale = settings.widgetScale
            instance.screenName = screen.localizedName
            instance.offset = WidgetLayout.freeOffset(for: instance.size.dimensions, avoiding: occupied,
                                                      within: CGSize(width: screen.visibleFrame.width / scale,
                                                                     height: screen.visibleFrame.height / scale))
        }
        settings.showWidgets = true
        return widgets.add(instance)
    }
}

/// Calls `onChange` with the new value each time anything `value` reads changes.
@MainActor
func observe<Value>(_ value: @escaping @MainActor @Sendable () -> Value,
                    onChange: @escaping @MainActor @Sendable (Value) -> Void) {
    withObservationTracking {
        _ = value()
    } onChange: {
        Task { @MainActor in
            onChange(value())
            observe(value, onChange: onChange)
        }
    }
}

extension AppServices {
    /// Room enough that laying out a theme's grid never clamps it; fitting
    /// then places it on the real screen.
    static let unbounded = CGSize(width: 10_000, height: 10_000)

    /// A theme's arrangement sized and centered to fill the primary screen:
    /// sets the widget size and returns the widgets moved to match.
    func fittedToScreen(_ layout: [WidgetInstance]) -> [WidgetInstance] {
        let bounds = NSScreen.screens.first?.visibleFrame.size ?? CGSize(width: 1440, height: 860)
        let fitted = WidgetLayout.fitted(layout, in: bounds, range: AppSettings.widgetScaleRange)
        settings.widgetScale = fitted.scale
        return fitted.widgets
    }

    /// Resizes and recenters the widgets on the primary screen so they fill it.
    func fitWidgetsToScreen() {
        guard let screen = NSScreen.screens.first else { return }
        let onScreen = widgets.widgets.filter { $0.screenName == screen.localizedName || $0.screenName == nil }
        guard !onScreen.isEmpty else { return }
        let moved = Dictionary(uniqueKeysWithValues: fittedToScreen(onScreen).map { ($0.id, $0.offset) })
        for (id, offset) in moved { widgets.update(id) { $0.offset = offset } }
    }
}
