import Foundation
import Observation

public enum NotchDisplay: String, CaseIterable, Identifiable, Sendable {
    /// The MacBook's own screen, falling back to the primary one when it's closed.
    case builtIn
    /// The screen with the menu bar.
    case primary

    public var id: String { rawValue }
    public var title: String { self == .builtIn ? "Built-in display" : "Primary display" }
}

/// Which tab the island shows when it opens.
public enum NotchStartTab: String, CaseIterable, Identifiable, Sendable {
    case last
    case home
    case system

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .last: "Where I left it"
        case .home: "Home"
        case .system: "System"
        }
    }
}

/// User preferences, persisted to UserDefaults as they change.
@Observable @MainActor
public final class AppSettings {
    // Notch
    public var notchEnabled: Bool { didSet { save(notchEnabled, Key.notchEnabled) } }
    public var notchStartTab: NotchStartTab { didSet { save(notchStartTab.rawValue, Key.notchStartTab) } }
    public var notchDisplay: NotchDisplay { didSet { save(notchDisplay.rawValue, Key.notchDisplay) } }
    public var expandOnHover: Bool { didSet { save(expandOnHover, Key.expandOnHover) } }
    /// Seconds the pointer must rest on the notch before it opens.
    public var hoverDelay: Double { didSet { save(hoverDelay, Key.hoverDelay) } }
    public var hapticFeedback: Bool { didSet { save(hapticFeedback, Key.hapticFeedback) } }

    // Live activities
    public var showNowPlaying: Bool { didSet { save(showNowPlaying, Key.showNowPlaying) } }
    public var showVolume: Bool { didSet { save(showVolume, Key.showVolume) } }
    public var showBattery: Bool { didSet { save(showBattery, Key.showBattery) } }
    public var showAudioDevice: Bool { didSet { save(showAudioDevice, Key.showAudioDevice) } }

    // App
    public var showInDock: Bool { didSet { save(showInDock, Key.showInDock) } }

    // Menu bar
    public var showMenuBarIcon: Bool { didSet { save(showMenuBarIcon, Key.showMenuBarIcon) } }
    public var showCPUInMenuBar: Bool { didSet { save(showCPUInMenuBar, Key.showCPUInMenuBar) } }

    // Desktop widgets
    public var showWidgets: Bool { didSet { save(showWidgets, Key.showWidgets) } }
    public var widgetFont: WidgetFont { didSet { save(widgetFont.rawValue, Key.widgetFont) } }
    public var widgetCornerRadius: Double { didSet { save(widgetCornerRadius, Key.widgetCornerRadius) } }
    /// The theme last applied, by id; nil once widgets have been styled by hand.
    public var widgetTheme: String? { didSet { defaults.set(widgetTheme, forKey: Key.widgetTheme) } }
    /// The design theme new widgets start in; nil for their own looks.
    public var widgetDesignTheme: String? { didSet { defaults.set(widgetDesignTheme, forKey: Key.widgetDesignTheme) } }

    // System monitor
    /// Seconds between samples while stats are on screen.
    public var refreshInterval: Double { didSet { save(refreshInterval, Key.refreshInterval) } }
    public var temperatureUnit: TemperatureUnit { didSet { save(temperatureUnit.rawValue, Key.temperatureUnit) } }

    @ObservationIgnored private let defaults: UserDefaults

    enum Key {
        static let notchEnabled = "notch.enabled"
        static let notchStartTab = "notch.startTab"
        static let showInDock = "app.showInDock"
        static let notchDisplay = "notch.display"
        static let expandOnHover = "notch.expandOnHover"
        static let hoverDelay = "notch.hoverDelay"
        static let hapticFeedback = "notch.hapticFeedback"
        static let showNowPlaying = "activities.nowPlaying"
        static let showVolume = "activities.volume"
        static let showBattery = "activities.battery"
        static let showAudioDevice = "activities.audioDevice"
        static let showMenuBarIcon = "menuBar.showIcon"
        static let showCPUInMenuBar = "menuBar.showCPU"
        static let showWidgets = "widgets.show"
        static let widgetFont = "widgets.font"
        static let widgetCornerRadius = "widgets.cornerRadius"
        static let widgetTheme = "widgets.theme"
        static let widgetDesignTheme = "widgets.designTheme"
        static let refreshInterval = "monitor.refreshInterval"
        static let temperatureUnit = "monitor.temperatureUnit"
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        notchEnabled = defaults.object(forKey: Key.notchEnabled) as? Bool ?? true
        notchStartTab = defaults.string(forKey: Key.notchStartTab).flatMap(NotchStartTab.init) ?? .last
        showInDock = defaults.object(forKey: Key.showInDock) as? Bool ?? true
        notchDisplay = defaults.string(forKey: Key.notchDisplay).flatMap(NotchDisplay.init) ?? .builtIn
        expandOnHover = defaults.object(forKey: Key.expandOnHover) as? Bool ?? true
        hoverDelay = defaults.object(forKey: Key.hoverDelay) as? Double ?? 0.15
        hapticFeedback = defaults.object(forKey: Key.hapticFeedback) as? Bool ?? true
        showNowPlaying = defaults.object(forKey: Key.showNowPlaying) as? Bool ?? true
        showVolume = defaults.object(forKey: Key.showVolume) as? Bool ?? true
        showBattery = defaults.object(forKey: Key.showBattery) as? Bool ?? true
        showAudioDevice = defaults.object(forKey: Key.showAudioDevice) as? Bool ?? true
        showMenuBarIcon = defaults.object(forKey: Key.showMenuBarIcon) as? Bool ?? true
        showCPUInMenuBar = defaults.object(forKey: Key.showCPUInMenuBar) as? Bool ?? false
        showWidgets = defaults.object(forKey: Key.showWidgets) as? Bool ?? true
        widgetFont = defaults.string(forKey: Key.widgetFont).flatMap(WidgetFont.init) ?? .rounded
        widgetCornerRadius = defaults.object(forKey: Key.widgetCornerRadius) as? Double ?? 22
        widgetTheme = defaults.string(forKey: Key.widgetTheme)
        widgetDesignTheme = defaults.string(forKey: Key.widgetDesignTheme)
        refreshInterval = defaults.object(forKey: Key.refreshInterval) as? Double ?? 1
        temperatureUnit = defaults.string(forKey: Key.temperatureUnit).flatMap(TemperatureUnit.init) ?? .celsius
    }

    private func save(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
    }
}
