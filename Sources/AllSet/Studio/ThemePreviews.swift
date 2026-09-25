import AllSetCore
import AppKit
import Observation
import OSLog
import SwiftUI

/// A theme set's widgets laid out on its wallpaper, as they'd sit on the
/// desktop. Drawn live for a theme's hero, and into pictures for cards.
struct ThemeComposition: View {
    let set: ThemeSet
    let widgets: [WidgetInstance]
    let services: AppServices
    var dark = true
    /// Lets the wallpaper move (the live hero, while hovered).
    var isLive = false

    /// The area the layouts are designed in: six small cells by four.
    static let canvas = CGSize(width: 1136, height: 768)

    var body: some View {
        GeometryReader { geometry in
            let scale = max(geometry.size.width / Self.canvas.width, geometry.size.height / Self.canvas.height)
            ZStack(alignment: .topLeading) {
                wallpaper.environment(\.widgetIsVisible, isLive)
                ZStack(alignment: .topLeading) {
                    ForEach(widgets) { widget in
                        WidgetBody(instance: widget, services: services)
                            .modifier(CompositionShadow(hasCard: widget.hasCard))
                            .offset(x: widget.offset.x, y: widget.offset.y)
                    }
                }
                .frame(width: Self.canvas.width, height: Self.canvas.height, alignment: .topLeading)
                .environment(\.widgetIsVisible, false)
                .environment(\.widgetIsPreview, true)
                .environment(\.colorScheme, dark ? .dark : .light)
                .scaleEffect(scale, anchor: .topLeading)
                .allowsHitTesting(false)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .clipped()
        }
    }

    @ViewBuilder
    private var wallpaper: some View {
        switch set.wallpaper {
        case .art(let piece):
            ArtView(piece: piece, animated: isLive)
        case .photo(let source):
            PhotoContent(source: source, filter: .none, tint: .white, animated: false, library: services.images, maxPixels: 1200)
        case .video, nil:
            StudioBackdrop(piece: ArtPiece(style: .blobs, palette: dark ? .midnight : .pastel))
        }
    }

    /// The set's widgets, in the given appearance, with a city for anything
    /// that needs one, ready to preview.
    @MainActor
    static func widgets(for set: ThemeSet, dark: Bool, services: AppServices) -> [WidgetInstance] {
        let city = services.widgets.widgets.lazy.compactMap(\.options.location).first ?? Self.city
        let widgets = ThemeSet.personalized(set.widgets(screenName: nil, bounds: canvas), with: services.themePhotos.sources(for: set.id))
        return widgets.map { widget in
            var widget = widget
            if set.designTheme?.followsAppearance == true { widget.options.appearance = dark ? .dark : .light }
            if [.weather, .airQuality, .daylight].contains(widget.kind), widget.options.location == nil { widget.options.location = city }
            return widget
        }
    }

    @MainActor private static let city = TimeZonePlace.guess()
}

private struct CompositionShadow: ViewModifier {
    let hasCard: Bool

    func body(content: Content) -> some View {
        content.shadow(color: .black.opacity(hasCard ? 0.2 : 0), radius: 7, y: 3)
    }
}

/// Pictures of theme sets for the library's cards: drawn once each, when a
/// card first needs one, then kept in memory and on disk. Only visible cards
/// ask, so scrolling the library never draws dozens of live widgets.
@Observable @MainActor
final class ThemePreviewCache {
    private(set) var images: [String: NSImage] = [:]

    @ObservationIgnored private let photos: ThemePhotos

    init(photos: ThemePhotos) {
        self.photos = photos
        // Pictures from older ways of drawing (or naming) previews never match again.
        let folder = folder, current = "-d\(Self.drawingVersion)-"
        Task.detached(priority: .background) {
            for name in (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [] where !name.contains(current) {
                try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
            }
        }
    }

    @ObservationIgnored private var inFlight = Set<String>()
    @ObservationIgnored private let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("AllSet/ThemePreviews", isDirectory: true)
    @ObservationIgnored private let log = Logger(subsystem: "com.pratik.allset", category: "themes")

    /// Bump when the way previews are drawn changes, to redraw them all.
    private static let drawingVersion = 4

    /// The app's version: a release redraws previews; rebuilding the same one doesn't.
    private static let appVersion: String = {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "0")-\(info?["CFBundleVersion"] as? String ?? "0")"
    }()

    /// What each set shows, boiled down to a number: its widgets and their
    /// settings (on a fixed date, so countdowns don't change it) and its wallpaper.
    @ObservationIgnored private var fingerprints: [String: String] = [:]

    private func fingerprint(_ set: ThemeSet) -> String {
        if let known = fingerprints[set.id] { return known }
        let widgets = set.widgets(screenName: nil, bounds: ThemeComposition.canvas, now: Date(timeIntervalSince1970: 0))
            .map { widget in
                var widget = widget
                widget.id = UUID(uuid: UUID_NULL)
                // Countdowns are set relative to today; the preview needn't follow.
                widget.options.match.kickoff = nil
                widget.options.ticket.date = nil
                widget.options.countdownDate = nil
                return widget
            }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in (try? encoder.encode(widgets)) ?? Data() { hash = (hash ^ UInt64(byte)) &* 0x100_0000_01b3 }
        for byte in "\(String(describing: set.wallpaper))".utf8 { hash = (hash ^ UInt64(byte)) &* 0x100_0000_01b3 }
        let print = String(hash, radix: 36)
        fingerprints[set.id] = print
        return print
    }

    /// Changes when what the preview shows does: the set's contents, the
    /// person's photos for it, the app's version or the way previews are drawn.
    func key(_ set: ThemeSet, dark: Bool) -> String {
        "\(set.id)-\(dark ? "dark" : "light")-\(fingerprint(set))-\(Self.appVersion)-d\(Self.drawingVersion)-p\(photos.version(of: set.id))"
    }

    func image(for set: ThemeSet, dark: Bool) -> NSImage? { images[key(set, dark: dark)] }

    /// Asks for a preview. Pictures already on disk load at once, off the main
    /// thread; the rest are drawn one at a time, in the order asked, so a page
    /// full of new cards never floods the main thread (drawing uses it).
    func request(_ set: ThemeSet, dark: Bool, services: AppServices) {
        let name = key(set, dark: dark)
        guard images[name] == nil, !inFlight.contains(name) else { return }
        inFlight.insert(name)
        Task {
            if let cached = await Self.load(folder.appendingPathComponent(name + ".png")) {
                images[name] = cached
                inFlight.remove(name)
                return
            }
            queue.append((name, set, dark))
            drawQueued(services: services)
        }
    }

    /// A card that scrolled away no longer needs its picture drawn first.
    func cancel(_ set: ThemeSet, dark: Bool) {
        let name = key(set, dark: dark)
        guard let index = queue.firstIndex(where: { $0.name == name }) else { return }
        queue.remove(at: index)
        inFlight.remove(name)
    }

    @ObservationIgnored private var queue: [(name: String, set: ThemeSet, dark: Bool)] = []
    @ObservationIgnored private var drawing: Task<Void, Never>?

    private func drawQueued(services: AppServices) {
        guard drawing == nil else { return }
        drawing = Task {
            while !queue.isEmpty {
                let (name, set, dark) = queue.removeFirst()
                if let image = await render(set, dark: dark, services: services) {
                    images[name] = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
                    let file = folder.appendingPathComponent(name + ".png"), folder = folder
                    let picture = SendableImage(image)
                    let older = "\(set.id)-\(dark ? "dark" : "light")-"
                    Task.detached(priority: .utility) {
                        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                        // Earlier pictures of this set are stale now.
                        for stale in (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
                        where stale.hasPrefix(older) && stale != file.lastPathComponent {
                            try? FileManager.default.removeItem(at: folder.appendingPathComponent(stale))
                        }
                        guard let destination = CGImageDestinationCreateWithURL(file as CFURL, "public.png" as CFString, 1, nil) else { return }
                        CGImageDestinationAddImage(destination, picture.image, nil)
                        CGImageDestinationFinalize(destination)
                    }
                }
                inFlight.remove(name)
                // A frame for the page between pictures.
                try? await Task.sleep(for: .milliseconds(16))
            }
            drawing = nil
        }
    }

    /// Draws after fetching what the widgets show (photos, the forecast), so
    /// the picture never catches them still loading.
    private func render(_ set: ThemeSet, dark: Bool, services: AppServices) async -> CGImage? {
        let widgets = ThemeComposition.widgets(for: set, dark: dark, services: services)
        for widget in widgets {
            for image in widget.options.images { _ = await services.images.image(for: image, maxPixels: 768) }
            // Player cards stand their player on the foil, cut out ahead of time.
            if widget.kind == .playerCard, let portrait = widget.options.images.first {
                _ = await SubjectCutout.cutout(for: portrait, library: services.images)
            }
            if let location = widget.options.location {
                if widget.kind == .weather { services.weather.refreshIfNeeded(location) }
                if widget.kind == .airQuality { services.weather.refreshAirQualityIfNeeded(location) }
            }
        }
        if case .photo(let source) = set.wallpaper { _ = await services.images.image(for: source, maxPixels: 1200) }
        // Give the forecast a moment to arrive.
        for _ in 0..<20 where widgets.contains(where: { widget in
            widget.options.location.map { location in
                (widget.kind == .weather && services.weather.reports[location] == nil && services.weather.failures[location] == nil)
                    || (widget.kind == .airQuality && services.weather.airQuality[location] == nil && services.weather.failures[location] == nil)
            } ?? false
        }) {
            try? await Task.sleep(for: .milliseconds(150))
        }
        let size = CGSize(width: 568, height: 384)
        let view = ThemeComposition(set: set, widgets: widgets, services: services, dark: dark)
            .frame(width: size.width, height: size.height)
            .environment(\.widgetSnapshot, true)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.cgImage else {
            log.error("Couldn't draw a preview of \(set.id, privacy: .public)")
            return nil
        }
        return image
    }

    private static func load(_ file: URL) async -> NSImage? {
        let image = await Task.detached(priority: .userInitiated) { () -> CGImage? in
            guard let source = CGImageSourceCreateWithURL(file as CFURL, nil) else { return nil }
            return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        }.value
        return image.map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
    }
}
