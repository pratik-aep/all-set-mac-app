import AppKit
import Observation

/// A borderless panel that sits on the desktop: above the desktop icons, below
/// every app window, on every Space, and left alone by Mission Control.
final class WidgetWindow: NSPanel {
    /// Room around the widget for its shadow and the arrange-mode buttons.
    static let margin: CGFloat = 16
    static let desktopLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
    /// While arranging, widgets float above windows so they can all be reached.
    static let arrangingLevel = NSWindow.Level.floating

    /// Only notes take keyboard focus; other widgets shouldn't pull it away
    /// from the app being used.
    var allowsKey = false

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = Self.desktopLevel
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .none
    }

    let state = WidgetWindowState()

    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }
}

/// Whether one widget's window can be seen. Each window has its own, so a
/// widget being covered redraws that widget alone, not every one on the desktop.
@Observable @MainActor
final class WidgetWindowState {
    var isOccluded = false
}
