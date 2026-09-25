import AllSetCore
import AppKit
import SwiftUI

enum WidgetDragPhase {
    case changed
    case ended
}

/// Keeps one window per widget in `WidgetStore`, placed where the store says,
/// and runs arrange mode: dragging, snapping and the floating toolbar.
@MainActor
final class DesktopWidgetController {
    private let services: AppServices
    private var windows: [UUID: WidgetWindow] = [:]
    /// Windows from removed widgets, kept for the next ones: making a window
    /// and tearing one down both cost the window server work.
    private var spares: [WidgetWindow] = []
    /// New widgets waiting for their turn to appear.
    private var pendingArrivals: [UUID] = []
    private var arrivals: Task<Void, Never>?
    private var occlusionObservers: [UUID: NSObjectProtocol] = [:]
    private var screenObserver: NSObjectProtocol?
    private var toolbar: NSPanel?
    /// "Keep / Go Back" while a theme is being tried on the desktop.
    private var previewBar: NSPanel?
    /// False during the first layout, so widgets don't fade in at launch.
    private var hasStarted = false
    /// The widget being dragged, where the pointer started and where its window was.
    private var drag: (id: UUID, startPointer: CGPoint, startOrigin: CGPoint)?

    init(services: AppServices) {
        self.services = services
    }

    func start() {
        if !services.widgets.hasSavedLayout, let screen = NSScreen.screens.first {
            services.widgets.add(contentsOf: WidgetLayout.starterSet(screenName: screen.localizedName))
        }
        sync(animated: false)

        observe({ [services] in services.widgets.widgets }) { [weak self] _ in self?.sync() }
        observe({ [services] in services.settings.showWidgets }) { [weak self] _ in self?.sync() }
        observe({ [services] in services.ui.isArrangingWidgets }) { [weak self] arranging in
            self?.setArranging(arranging)
        }
        observe({ [services] in services.ui.themePreview?.setID }) { [weak self] setID in
            self?.showPreviewBar(for: setID)
        }
        hasStarted = true
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.sync(animated: false) }
        }
    }

    // MARK: Windows

    private func sync(animated: Bool = true) {
        let wanted = services.settings.showWidgets ? services.widgets.widgets : []
        let wantedIDs = Set(wanted.map(\.id))
        for id in windows.keys where !wantedIDs.contains(id) {
            closeWindow(id)
        }
        pendingArrivals.removeAll { !wantedIDs.contains($0) }

        // A whole new set (a theme) arrives a couple of widgets a frame instead
        // of all in one: no stall, and the desktop fills in like a cascade.
        let newCount = wanted.count { windows[$0.id] == nil }
        let staggers = hasStarted && newCount > Self.arrivalBatch
        for instance in wanted {
            if windows[instance.id] == nil {
                if staggers || pendingArrivals.contains(instance.id) {
                    if !pendingArrivals.contains(instance.id) { pendingArrivals.append(instance.id) }
                    continue
                }
                show(instance)
            } else {
                place(instance, animated: animated)
            }
        }
        startArrivals()
        updateStatsViewer()
    }

    /// How many new widgets appear per frame.
    private static var arrivalBatch: Int {
        #if DEBUG
        // `-arrivalBatch 100`: everything at once, as before, for comparing.
        let value = UserDefaults.standard.integer(forKey: "arrivalBatch")
        if value > 0 { return value }
        #endif
        return 3
    }

    private func startArrivals() {
        guard arrivals == nil, !pendingArrivals.isEmpty else { return }
        arrivals = Task { [weak self] in
            while let self, !self.pendingArrivals.isEmpty {
                let batch = self.pendingArrivals.prefix(Self.arrivalBatch)
                self.pendingArrivals.removeFirst(batch.count)
                for id in batch where self.windows[id] == nil {
                    guard self.services.settings.showWidgets, let instance = self.services.widgets.instance(id) else { continue }
                    self.show(instance)
                }
                self.updateStatsViewer()
                try? await Task.sleep(for: .milliseconds(34))
            }
            self?.arrivals = nil
        }
    }

    /// Puts a widget on the desktop in a fresh (or recycled) window.
    private func show(_ instance: WidgetInstance) {
        let window = makeWindow(for: instance)
        window.allowsKey = instance.kind == .note || instance.kind == .todo
        if let frame = frame(for: instance) { window.setFrame(frame, display: false) }
        if hasStarted { arrive(window, motion: instance.designTheme?.motion ?? .calm) }
        window.orderFront(nil)
    }

    /// Moves an existing widget's window to where the store says.
    private func place(_ instance: WidgetInstance, animated: Bool) {
        guard let window = windows[instance.id] else { return }
        window.allowsKey = instance.kind == .note || instance.kind == .todo
        guard drag?.id != instance.id, let frame = frame(for: instance) else { return }
        if window.frame != frame {
            if animated, window.isVisible {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.25
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    window.animator().setFrame(frame, display: true)
                }
            } else {
                window.setFrame(frame, display: true)
            }
        }
        if !window.isVisible { window.orderFront(nil) }
    }

    /// A new widget fades in the way its theme moves: quickly for energetic
    /// themes, slowly for calm ones, at once for still ones (or with Reduce Motion, briefly).
    private func arrive(_ window: WidgetWindow, motion: MotionLanguage) {
        let duration = Motion.reducesMotion ? 0.15 : motion.appearDuration
        guard duration > 0 else { return }
        window.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
        }
    }

    private func showPreviewBar(for setID: String?) {
        previewBar?.orderOut(nil)
        previewBar = nil
        guard let setID, let set = ThemeLibrary.set(setID), let screen = NSScreen.screens.first else { return }
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        let hostingView = FirstClickHostingView(rootView: ThemePreviewBar(
            name: set.name,
            onKeep: { [weak self] in self?.services.endThemePreview(keep: true) },
            onRevert: { [weak self] in self?.services.endThemePreview(keep: false) }
        ))
        hostingView.sizingOptions = []
        panel.contentView = hostingView
        let size = CGSize(width: 520, height: 84)
        let visible = screen.visibleFrame
        panel.setFrame(CGRect(x: visible.midX - size.width / 2, y: visible.minY + 20, width: size.width, height: size.height), display: true)
        panel.orderFront(nil)
        previewBar = panel
    }

    private func makeWindow(for instance: WidgetInstance) -> WidgetWindow {
        let id = instance.id
        let window = spares.popLast() ?? WidgetWindow()
        window.state.isOccluded = false
        let root = WidgetRoot(
            id: id,
            services: services,
            window: window.state,
            onDrag: { [weak self] phase in self?.handleDrag(id, phase) },
            onRemove: { [weak self] in self?.services.widgets.remove(id) },
            onConfigure: { [weak self] in self?.services.openWindow(.widget(id)) }
        )
        if let hostingView = window.contentView as? FirstClickHostingView<WidgetRoot> {
            hostingView.rootView = root
        } else {
            let hostingView = FirstClickHostingView(rootView: root)
            hostingView.sizingOptions = []
            window.contentView = hostingView
        }
        window.level = services.ui.isArrangingWidgets ? WidgetWindow.arrangingLevel : WidgetWindow.desktopLevel

        occlusionObservers[id] = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.visibilityChanged() }
        }
        windows[id] = window
        return window
    }

    private func closeWindow(_ id: UUID) {
        if let observer = occlusionObservers.removeValue(forKey: id) {
            NotificationCenter.default.removeObserver(observer)
        }
        guard let window = windows.removeValue(forKey: id) else { return }
        window.orderOut(nil)
        if spares.count < Self.spareLimit {
            (window.contentView as? FirstClickHostingView<WidgetRoot>)?.rootView = WidgetRoot.empty(services: services)
            window.alphaValue = 1
            spares.append(window)
        } else {
            window.close()
        }
    }

    private static let spareLimit = 16

    private func visibilityChanged() {
        for window in windows.values {
            let occluded = !window.occlusionState.contains(.visible)
            if window.state.isOccluded != occluded { window.state.isOccluded = occluded }
        }
        updateStatsViewer()
    }

    /// The window frame for a widget: its saved spot, kept on screen, plus the
    /// margin around it.
    private func frame(for instance: WidgetInstance) -> CGRect? {
        guard let screen = screen(named: instance.screenName) else { return nil }
        let visible = screen.visibleFrame
        let size = instance.size.dimensions
        let offset = WidgetLayout.snap(instance.offset, size: size, within: visible.size)
        let content = CGRect(x: visible.minX + offset.x, y: visible.maxY - offset.y - size.height,
                             width: size.width, height: size.height)
        return content.insetBy(dx: -WidgetWindow.margin, dy: -WidgetWindow.margin)
    }

    private func screen(named name: String?) -> NSScreen? {
        NSScreen.screens.first { $0.localizedName == name } ?? NSScreen.screens.first
    }

    /// Stats widgets only need fresh numbers while someone can see them, and
    /// only as often as the most eager visible one asks.
    private func updateStatsViewer() {
        let intervals = windows.compactMap { id, window -> TimeInterval? in
            guard window.occlusionState.contains(.visible), let instance = services.widgets.instance(id) else { return nil }
            switch instance.kind {
            case .system, .battery, .terminal:
                return instance.options.refresh.interval(for: .systemStats) ?? 5
            case .metric where ![.wifi, .uptime].contains(instance.options.metric):
                return instance.options.refresh.interval(for: .systemStats) ?? 5
            default:
                return nil
            }
        }
        services.monitor.setViewer("widgets", visible: !intervals.isEmpty, interval: intervals.min())
    }

    // MARK: Arranging

    private func handleDrag(_ id: UUID, _ phase: WidgetDragPhase) {
        guard let window = windows[id] else { return }
        // Global pointer position, since the view under the pointer moves with the window.
        let pointer = NSEvent.mouseLocation
        switch phase {
        case .changed:
            if drag?.id != id {
                drag = (id, pointer, window.frame.origin)
            }
            guard let drag else { return }
            window.setFrameOrigin(CGPoint(x: drag.startOrigin.x + pointer.x - drag.startPointer.x,
                                          y: drag.startOrigin.y + pointer.y - drag.startPointer.y))
        case .ended:
            guard drag?.id == id else { return }
            drag = nil
            let content = window.frame.insetBy(dx: WidgetWindow.margin, dy: WidgetWindow.margin)
            let center = CGPoint(x: content.midX, y: content.midY)
            guard let screen = NSScreen.screens.first(where: { $0.frame.contains(center) }) ?? screen(named: nil) else { return }
            let visible = screen.visibleFrame
            let offset = WidgetLayout.snap(CGPoint(x: content.minX - visible.minX, y: visible.maxY - content.maxY),
                                           size: content.size, within: visible.size)
            services.widgets.update(id) {
                $0.offset = offset
                $0.screenName = screen.localizedName
            }
            // Settle onto the grid even if the saved spot didn't change.
            sync()
        }
    }

    private func setArranging(_ arranging: Bool) {
        for window in windows.values {
            window.level = arranging ? WidgetWindow.arrangingLevel : WidgetWindow.desktopLevel
        }
        if arranging {
            showToolbar()
        } else {
            toolbar?.orderOut(nil)
            toolbar = nil
        }
    }

    private func showToolbar() {
        guard toolbar == nil, let screen = NSScreen.screens.first else { return }
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: WidgetWindow.arrangingLevel.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false

        let hostingView = FirstClickHostingView(rootView: ArrangeToolbar(
            onAdd: { [weak self] in self?.services.openWindow(.gallery(nil)) },
            onDone: { [weak self] in self?.services.ui.isArrangingWidgets = false }
        ))
        hostingView.sizingOptions = []
        panel.contentView = hostingView

        let size = CGSize(width: 480, height: 84)
        let visible = screen.visibleFrame
        panel.setFrame(CGRect(x: visible.midX - size.width / 2, y: visible.minY + 20, width: size.width, height: size.height),
                       display: true)
        panel.orderFront(nil)
        toolbar = panel
    }
}

/// A widget window's content: the widget, with a fresh identity whenever a
/// recycled window takes on a different widget.
private struct WidgetRoot: View {
    let id: UUID
    let services: AppServices
    let window: WidgetWindowState
    let onDrag: @MainActor (WidgetDragPhase) -> Void
    let onRemove: @MainActor () -> Void
    let onConfigure: @MainActor () -> Void

    var body: some View {
        WidgetHostView(id: id, services: services, window: window, onDrag: onDrag, onRemove: onRemove, onConfigure: onConfigure)
            .id(id)
    }

    /// What a spare window holds: nothing (no widget has this id).
    static func empty(services: AppServices) -> WidgetRoot {
        WidgetRoot(id: UUID(), services: services, window: WidgetWindowState(), onDrag: { _ in }, onRemove: {}, onConfigure: {})
    }
}
