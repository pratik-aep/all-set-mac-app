import AllSetCore
import AppKit

/// A theme set being tried on the desktop, and everything to put back.
struct ThemePreview: Equatable {
    let setID: String
    let before: DesktopSnapshot
}

/// A theme set just put on the desktop, and the desktop from before it.
struct ThemeUndo: Equatable {
    let name: String
    let before: DesktopSnapshot
}

/// How a theme set goes onto the desktop. Every mode can be undone.
enum ThemeInstall {
    /// The set's widgets replace the current ones.
    case replace
    /// The set's widgets join the current ones, in free spots.
    case add
    /// The current widgets take on the set's look; nothing is added.
    case restyle
}

extension AppServices {
    /// Installs a theme set: its widgets, look and (if asked) wallpaper.
    func install(_ set: ThemeSet, mode: ThemeInstall, wallpaper setsWallpaper: Bool) {
        // Installing over a preview starts from the desktop before the preview.
        if ui.themePreview != nil { endThemePreview(keep: false) }
        let before = desktopSnapshot
        switch mode {
        case .replace:
            widgets.replaceAll(with: themeWidgets(set))
            themeStats.record(.install, for: set.id)
        case .add:
            let screen = NSScreen.screens.first
            let bounds = screen?.visibleFrame.size ?? CGSize(width: 1440, height: 860)
            let added = ThemeSet.personalized(set.widgets(screenName: screen?.localizedName, bounds: bounds),
                                              with: themePhotos.sources(for: set.id))
            for widget in prepared(added) { addWidget(widget) }
            themeStats.record(.install, for: set.id)
        case .restyle:
            if let theme = set.designTheme {
                apply(theme, wallpaper: false)
            } else if let setup = set.setup {
                apply(setup, wallpaper: false)
            }
            themeStats.record(.apply, for: set.id)
        }
        if setsWallpaper, let source = set.wallpaper { wallpaper.set(source) }
        settings.adopt(set)
        ui.themeUndo = ThemeUndo(name: set.name, before: before)
    }

    /// Tries a set on the desktop until Keep or Go Back. It's put there
    /// exactly as Install would, so Keep has nothing left to change.
    func previewOnDesktop(_ set: ThemeSet, wallpaper setsWallpaper: Bool) {
        if ui.themePreview != nil { endThemePreview(keep: false) }
        ui.themePreview = ThemePreview(setID: set.id, before: desktopSnapshot)
        widgets.replaceAll(with: themeWidgets(set))
        if setsWallpaper, let source = set.wallpaper { wallpaper.set(source) }
        settings.adopt(set)
        themeStats.record(.preview, for: set.id)
    }

    func endThemePreview(keep: Bool) {
        guard let preview = ui.themePreview else { return }
        ui.themePreview = nil
        if keep {
            // Undo goes back to the desktop from before the preview.
            if let set = ThemeLibrary.set(preview.setID) {
                ui.themeUndo = ThemeUndo(name: set.name, before: preview.before)
                themeStats.record(.install, for: set.id)
            }
        } else {
            preview.before.restore(settings: settings, widgets: widgets, wallpaper: wallpaper)
        }
    }

    /// Puts back the desktop from before the last theme: widgets, size,
    /// font, corners, theme and wallpaper.
    func undoTheme() {
        guard let undo = ui.themeUndo else { return }
        // The undo reaches further back than any preview on top of it.
        ui.themePreview = nil
        undo.before.restore(settings: settings, widgets: widgets, wallpaper: wallpaper)
        ui.themeUndo = nil
    }

    private var desktopSnapshot: DesktopSnapshot {
        DesktopSnapshot(settings: settings, widgets: widgets, wallpaper: wallpaper)
    }

    /// A set's widgets with the person's photos, sized and centered to fill
    /// the primary screen, whatever its size.
    private func themeWidgets(_ set: ThemeSet) -> [WidgetInstance] {
        let layout = set.widgets(screenName: NSScreen.screens.first?.localizedName, bounds: Self.unbounded)
        return prepared(fittedToScreen(ThemeSet.personalized(layout, with: themePhotos.sources(for: set.id))))
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
