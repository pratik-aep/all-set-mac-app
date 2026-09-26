import AllSetCore
import AppKit

/// A theme set being tried on the desktop, and what to put back.
struct ThemePreview: Equatable {
    let setID: String
    let widgets: [WidgetInstance]
    let wallpaper: WallpaperConfig
    /// The widget size to go back to.
    let scale: Double
}

/// How a theme set goes onto the desktop.
enum ThemeInstall {
    /// The set's widgets replace the current ones (Undo brings them back).
    case replace
    /// The set's widgets join the current ones, in free spots.
    case add
    /// The current widgets take on the set's look; nothing is added.
    case restyle
}

extension AppServices {
    /// Installs a theme set: its widgets, look and (if asked) wallpaper.
    func install(_ set: ThemeSet, mode: ThemeInstall, wallpaper setsWallpaper: Bool) {
        let photos = themePhotos.sources(for: set.id)
        let screen = NSScreen.screens.first
        let bounds = screen?.visibleFrame.size ?? CGSize(width: 1440, height: 860)
        switch mode {
        case .replace:
            ui.layoutBeforeTheme = widgets.widgets
            ui.scaleBeforeTheme = settings.widgetScale
            // Sized and centered to fill this screen, whatever its size.
            widgets.replaceAll(with: prepared(fittedToScreen(ThemeSet.personalized(
                set.widgets(screenName: screen?.localizedName, bounds: Self.unbounded), with: photos))))
            themeStats.record(.install, for: set.id)
        case .add:
            for widget in prepared(ThemeSet.personalized(set.widgets(screenName: screen?.localizedName, bounds: bounds), with: photos)) {
                addWidget(widget)
            }
            themeStats.record(.install, for: set.id)
        case .restyle:
            if let theme = set.designTheme {
                apply(theme, wallpaper: false)
            } else if let setup = set.setup {
                apply(setup, wallpaper: false, useKit: false)
            }
            themeStats.record(.apply, for: set.id)
        }
        if let setup = set.setup, mode != .restyle {
            // The original setups also set the font and corners.
            settings.widgetFont = setup.font
            settings.widgetCornerRadius = setup.cornerRadius
        }
        if setsWallpaper, let wallpaper = set.wallpaper { self.wallpaper.set(wallpaper) }
        settings.widgetDesignTheme = set.designTheme?.id
        settings.widgetTheme = set.setup?.id
        settings.showWidgets = true
    }

    /// Tries a set on the desktop until Keep or Go Back.
    func previewOnDesktop(_ set: ThemeSet) {
        if ui.themePreview != nil { endThemePreview(keep: false) }
        let screen = NSScreen.screens.first
        ui.themePreview = ThemePreview(setID: set.id, widgets: widgets.widgets, wallpaper: wallpaper.config, scale: settings.widgetScale)
        widgets.replaceAll(with: prepared(fittedToScreen(ThemeSet.personalized(
            set.widgets(screenName: screen?.localizedName, bounds: Self.unbounded),
            with: themePhotos.sources(for: set.id)))))
        if let source = set.wallpaper { wallpaper.set(source) }
        settings.showWidgets = true
        themeStats.record(.preview, for: set.id)
    }

    func endThemePreview(keep: Bool) {
        guard let preview = ui.themePreview else { return }
        ui.themePreview = nil
        if keep {
            ui.layoutBeforeTheme = preview.widgets
            ui.scaleBeforeTheme = preview.scale
            if let set = ThemeLibrary.set(preview.setID) {
                settings.widgetDesignTheme = set.designTheme?.id
                themeStats.record(.install, for: set.id)
            }
        } else {
            widgets.replaceAll(with: preview.widgets)
            settings.widgetScale = preview.scale
            wallpaper.config = preview.wallpaper
        }
    }

    /// Gives location-based widgets a city: one already used, else a guess
    /// from the Mac's time zone, so they don't arrive asking for one.
    private func prepared(_ instances: [WidgetInstance]) -> [WidgetInstance] {
        let city = widgets.widgets.lazy.compactMap(\.options.location).first ?? TimeZonePlace.guess()
        return instances.map { widget in
            var widget = widget
            if [.weather, .airQuality, .daylight].contains(widget.kind), widget.options.location == nil {
                widget.options.location = city
            }
            return widget
        }
    }
}

extension AppServices {
    /// Asks for photos, then puts the whole set on the desktop with them in
    /// every picture slot. Returns false when nothing was chosen.
    @discardableResult
    func installWithMyPhotos(_ set: ThemeSet, wallpaper setsWallpaper: Bool) -> Bool {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.allowedContentTypes = [.image, .folder]
        panel.prompt = "Use These"
        panel.message = "Choose photos for \(set.name). They fill every photo, tape and print in the theme."
        guard panel.runModal() == .OK else { return false }
        let names = images.importImages(from: panel.urls)
        guard !names.isEmpty else { return false }
        themePhotos.set(names, for: set.id)
        install(set, mode: .replace, wallpaper: setsWallpaper)
        return true
    }
}
