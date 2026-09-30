import AllSetCore
import AppKit
import SwiftUI

/// Ways to browse the library.
enum ThemeDiscovery: String, CaseIterable, Identifiable {
    case all, featured, trending, new, artist, football, music, popular, minimal, dark, colorful, developer, favorites

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .featured: "Featured"
        case .trending: "Trending"
        case .new: "New"
        case .artist: "Moodboards"
        case .football: "Football"
        case .music: "Music Icons"
        case .popular: "Popular"
        case .minimal: "Minimal"
        case .dark: "Dark"
        case .colorful: "Colorful"
        case .developer: "Developer"
        case .favorites: "Favorites"
        }
    }

    var symbol: String {
        switch self {
        case .all: "square.grid.2x2"
        case .featured: "star"
        case .trending: "chart.line.uptrend.xyaxis"
        case .new: "sparkle"
        case .artist: "photo.stack"
        case .football: "soccerball"
        case .music: "music.mic"
        case .popular: "flame"
        case .minimal: "circle"
        case .dark: "moon"
        case .colorful: "paintpalette"
        case .developer: "chevron.left.forwardslash.chevron.right"
        case .favorites: "heart"
        }
    }

    /// The sets it shows, in its own order.
    @MainActor
    func sets(stats: ThemeStats, now: Date = .now) -> [ThemeSet] {
        let all = ThemeLibrary.all
        switch self {
        case .all: return all
        case .featured: return all.filter { $0.collections.contains(.featured) }.sorted { stats.popularity($0) > stats.popularity($1) }
        case .trending: return all.sorted { stats.trending($0, now: now) > stats.trending($1, now: now) }.prefix(12).map { $0 }
        case .new:
            let recent = Calendar.current.date(byAdding: .day, value: -45, to: now) ?? now
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            return all.filter { (formatter.date(from: $0.added) ?? .distantPast) >= recent }.sorted { $0.added > $1.added }
        case .artist: return all.filter { $0.collections.contains(.artistWorlds) }
        case .football: return all.filter { $0.collections.contains(.football) }
        case .music: return all.filter { $0.collections.contains(.musicIcons) }
        case .popular: return all.sorted { stats.popularity($0) > stats.popularity($1) }
        case .minimal: return all.filter { $0.collections.contains(.minimal) || $0.collections.contains(.zen) }
        case .dark: return all.filter(\.isDark)
        case .colorful: return all.filter(Self.isColorful)
        case .developer: return all.filter { $0.collections.contains(.developer) }
        case .favorites: return all.filter { stats.isFavorite($0.id) }
        }
    }

    /// A vivid accent, or a colorful wallpaper.
    private static func isColorful(_ set: ThemeSet) -> Bool {
        if let theme = set.designTheme {
            let palette = theme.palette(dark: set.isDark)
            return palette.accent.hsvSaturation > 0.55 && !(theme.surface == .solid || theme.surface == .terminal)
        }
        if case .art(let piece) = set.wallpaper { return piece.palette.colors[2].hsvSaturation > 0.5 }
        return false
    }
}

// MARK: Library

/// The theme library: complete widget worlds to browse, preview and install.
struct ThemesPage: View {
    let services: AppServices

    @AppStorage("themes.setsWallpaper") private var setsWallpaper = true
    @AppStorage("themes.discovery") private var discovery = ThemeDiscovery.all.rawValue
    @State private var query = ""

    private var filter: ThemeDiscovery { ThemeDiscovery(rawValue: discovery) ?? .all }

    private var results: [ThemeSet] {
        let base = filter.sets(stats: services.themeStats)
        guard !SearchMatch.normalize(query).isEmpty else { return base }
        let matches = Set(ThemeLibrary.search(query).map(\.id))
        return ThemeLibrary.search(query).filter { set in base.contains { $0.id == set.id } && matches.contains(set.id) }
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.section) {
                    VStack(alignment: .leading, spacing: DS.Space.l) {
                        header
                        banners
                        chips
                    }
                    if filter == .all && SearchMatch.normalize(query).isEmpty {
                        shelves(heroHeight: min(max(geometry.size.height * 0.5, 280), 460))
                    } else {
                        grid(results)
                    }
                }
                .padding(.horizontal, DS.Space.pageMargin(for: geometry.size.width))
                .padding(.vertical, DS.Space.xl)
            }
        }
        .background(AppBackground())
    }

    private var header: some View {
        PageHeader(eyebrow: "\(ThemeLibrary.all.count) complete desktops", title: "Themes",
                   subtitle: "Pick one and your whole desktop follows: the widgets, their look and the wallpaper.") {
            VStack(alignment: .trailing, spacing: DS.Space.s) {
                SearchField(text: $query, prompt: "Search themes: night, pink, developer…")
                    .frame(width: 280)
                Toggle("Change the wallpaper too", isOn: $setsWallpaper)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .foregroundStyle(DS.Ink.secondary)
            }
        }
    }

    @ViewBuilder
    private var banners: some View {
        DesktopUndoBanner(services: services)
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Space.xs) {
                ForEach(ThemeDiscovery.allCases) { item in
                    FilterPill(title: item.title, symbol: item.symbol, isSelected: filter == item) {
                        withMotion(Motion.quick) { discovery = item.rawValue }
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    /// The lead featured theme as a hero, then a rail per shelf.
    private func shelves(heroHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.section) {
            let sections = sections
            if let lead = sections.featured.first {
                FeaturedThemeHero(set: lead, services: services, height: heroHeight)
            }
            shelf("Featured", sets: Array(sections.featured.dropFirst()), more: .featured)
            ForEach(sections.shelves, id: \.title) { shelf in
                self.shelf(shelf.title, sets: shelf.sets, more: shelf.more)
            }
        }
    }

    /// The library split so every theme shows up exactly once: each shelf
    /// takes only what the ones above it haven't shown.
    private var sections: (featured: [ThemeSet], shelves: [(title: String, sets: [ThemeSet], more: ThemeDiscovery?)]) {
        let stats = services.themeStats
        var shown = Set<String>()
        func claim(_ sets: [ThemeSet]) -> [ThemeSet] {
            let fresh = sets.filter { !shown.contains($0.id) }
            shown.formUnion(fresh.map(\.id))
            return fresh
        }
        let featured = claim(Array(ThemeDiscovery.featured.sets(stats: stats).prefix(4)))
        var shelves: [(title: String, sets: [ThemeSet], more: ThemeDiscovery?)] = [
            ("Colour & Light", claim(ThemeLibrary.sets(in: .colourAndLight)), nil),
            ("Football", claim(ThemeDiscovery.football.sets(stats: stats)), .football),
            ("Music Icons", claim(ThemeDiscovery.music.sets(stats: stats)), .music),
            ("Moodboards", claim(ThemeDiscovery.artist.sets(stats: stats)), .artist),
            ("Night", claim(ThemeLibrary.sets(in: .night)), nil),
            ("Dreamy", claim(ThemeLibrary.sets(in: .dreamy)), nil),
            ("Minimal & Designer", claim(ThemeLibrary.sets(in: .designer) + ThemeLibrary.sets(in: .minimal)), nil),
            ("Developer", claim(ThemeDiscovery.developer.sets(stats: stats)), .developer),
        ]
        shelves.append(("More Setups", claim(ThemeLibrary.all), nil))
        return (featured, shelves)
    }

    private func shelf(_ title: String, _ discovery: ThemeDiscovery) -> some View {
        shelf(title, sets: discovery.sets(stats: services.themeStats), more: discovery)
    }

    @ViewBuilder
    private func shelf(_ title: String, sets: [ThemeSet], more: ThemeDiscovery? = nil) -> some View {
        if !sets.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                if let more {
                    SectionHeader(title: title, subtitle: "\(sets.count) themes", actionTitle: "See All") {
                        withMotion(Motion.quick) { discovery = more.rawValue }
                    }
                } else {
                    SectionHeader(title: title, subtitle: "\(sets.count) themes")
                }
                MediaRail(items: sets, cardWidth: 300) { set in
                    ThemeSetCard(set: set, services: services)
                }
            }
        }
    }

    @ViewBuilder
    private func grid(_ sets: [ThemeSet]) -> some View {
        if sets.isEmpty {
            EmptyState(symbol: filter == .favorites ? "heart" : "magnifyingglass",
                       title: filter == .favorites ? "No favorites yet" : "No themes found",
                       message: filter == .favorites ? "Tap the heart on any theme to keep it here." : "Try another word or filter.")
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: DS.Space.m)], spacing: DS.Space.l) {
                ForEach(sets) { set in ThemeSetCard(set: set, services: services) }
            }
        }
    }
}

/// Offers to take back the last whole-desktop change: a theme going on, or
/// the widgets a newly picked wallpaper cleared away.
struct DesktopUndoBanner: View {
    let services: AppServices

    var body: some View {
        if let undo = services.ui.desktopUndo {
            HStack(spacing: 12) {
                Image(systemName: "arrow.uturn.backward.circle.fill").font(.title2).foregroundStyle(.tint)
                Text(message(for: undo.change))
                Spacer()
                Button(undo.change == .clearedForWallpaper ? "Bring Widgets Back" : "Undo") {
                    withMotion(Motion.standard) { services.undoDesktopChange() }
                }
                Button("Keep It") { withMotion(Motion.standard) { services.ui.desktopUndo = nil } }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.tint.opacity(0.12)))
            .task(id: undo.id) {
                // Clearing for a wallpaper is expected; the offer doesn't linger.
                guard undo.change == .clearedForWallpaper else { return }
                try? await Task.sleep(for: .seconds(12))
                if services.ui.desktopUndo?.id == undo.id {
                    withMotion(Motion.standard) { services.ui.desktopUndo = nil }
                }
            }
        }
    }

    private func message(for change: DesktopUndo.Change) -> String {
        switch change {
        case .theme(let name): "\(name) is on your desktop. Undo puts back your widgets, their look and your wallpaper."
        case .clearedForWallpaper: "Your widgets were cleared for the new wallpaper."
        }
    }
}

/// A theme set as a card: a miniature desktop of the whole set, its name
/// and what inspired it. Opens its detail page.
private struct ThemeSetCard: View {
    let set: ThemeSet
    let services: AppServices

    @State private var isHovering = false

    var body: some View {
        let stats = services.themeStats
        let favorite = stats.isFavorite(set.id)
        Button {
            services.ui.page = .themeSet(set.id)
        } label: {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                ThemeSnapshot(set: set, dark: set.isDark, services: services)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.media, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: DS.Radius.media, style: .continuous).strokeBorder(DS.Surface.hairline))
                    .overlay(alignment: .topTrailing) {
                        Button {
                            withMotion(Motion.bouncy) { stats.toggleFavorite(set.id) }
                        } label: {
                            Image(systemName: favorite ? "heart.fill" : "heart")
                                .foregroundStyle(favorite ? Color.pink : DS.Ink.primary)
                        }
                        .buttonStyle(FloatingButtonStyle(diameter: 30))
                        .padding(DS.Space.s)
                        .opacity(isHovering || favorite ? 1 : 0)
                        .accessibilityLabel(favorite ? "Remove from favorites" : "Add to favorites")
                    }
                    .scaleEffect(isHovering ? 1.02 : 1)
                    .dsElevated()
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(set.name).dsText(.headline).lineLimit(1)
                        Spacer(minLength: DS.Space.xs)
                        Text("\(set.includedWidgets.count) widgets").dsText(.meta)
                    }
                    Text(set.inspiration ?? set.tagline)
                        .dsText(.meta)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, DS.Space.xxs)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in withMotion(Motion.responsive) { isHovering = hovering } }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(set.name) theme, \(set.includedWidgets.count) widgets. \(set.tagline)")
        .accessibilityHint("Opens the theme")
    }
}

/// The lead featured theme, large: its desktop fills the hero.
private struct FeaturedThemeHero: View {
    let set: ThemeSet
    let services: AppServices
    var height: CGFloat

    var body: some View {
        let favorite = services.themeStats.isFavorite(set.id)
        HeroSection(eyebrow: "Featured theme", title: set.name,
                    metadata: [set.inspiration ?? set.tagline, "\(set.includedWidgets.count) widgets"], height: height) {
            ThemeSnapshot(set: set, dark: set.isDark, services: services, fills: true)
        } actions: {
            Button("View Theme") { services.ui.page = .themeSet(set.id) }
                .buttonStyle(.pillProminent)
            Button {
                withMotion(Motion.bouncy) { services.themeStats.toggleFavorite(set.id) }
            } label: {
                Image(systemName: favorite ? "heart.fill" : "heart")
                    .foregroundStyle(favorite ? Color.pink : DS.Ink.primary)
            }
            .buttonStyle(.floating)
            .accessibilityLabel(favorite ? "Remove from favorites" : "Add to favorites")
        }
    }
}

/// A theme's preview picture, drawn on first sight.
private struct ThemeSnapshot: View {
    let set: ThemeSet
    let dark: Bool
    let services: AppServices
    /// Fills its frame (cropping) rather than keeping the desktop's shape.
    var fills = false

    var body: some View {
        let cache = services.themePreviews
        ZStack {
            if let image = cache.image(for: set, dark: dark) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill).transition(.opacity)
            } else {
                Rectangle().fill(DS.Surface.raised)
                    .overlay(ProgressView().controlSize(.small))
            }
        }
        .aspectRatio(fills ? nil : ThemeComposition.canvas.width / ThemeComposition.canvas.height, contentMode: fills ? .fill : .fit)
        .motion(Motion.standard, value: cache.image(for: set, dark: dark) != nil)
        // Keyed on the purge generation too: a purge (memory pressure) drops
        // queued requests, and a card still waiting must ask again.
        .task(id: "\(cache.key(set, dark: dark))#\(cache.generation)") { cache.request(set, dark: dark, services: services) }
        .onDisappear { cache.cancel(set, dark: dark) }
        .accessibilityHidden(true)
    }
}

// MARK: Detail

/// Everything about one theme: a live preview, what's in it, its colors,
/// type and motion, where it came from, and the ways to install it.
struct ThemeDetailPage: View {
    let setID: String
    let services: AppServices

    @AppStorage("themes.setsWallpaper") private var setsWallpaper = true
    @State private var confirmsReplace = false
    @State private var heroHovering = false
    @State private var done: String?
    @State private var heroWidgets: [WidgetInstance] = []

    var body: some View {
        if let set = ThemeLibrary.set(setID) {
            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Space.l) {
                        Button {
                            services.ui.page = .themes
                        } label: {
                            Label("Themes", systemImage: "chevron.left")
                        }
                        .buttonStyle(.pill)
                        hero(set)
                        titleRow(set)
                        actions(set)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 360), spacing: DS.Space.xl, alignment: .top)],
                                  alignment: .leading, spacing: DS.Space.xl) {
                            about(set)
                            included(set)
                            appearance(set)
                            palette(set)
                            typography(set)
                            // Only design skins carry a motion language; the
                            // setups would all read "Calm".
                            if set.designTheme != nil { motion(set) }
                        }
                        research(set)
                    }
                    .padding(.horizontal, DS.Space.pageMargin(for: geometry.size.width))
                    .padding(.vertical, DS.Space.xl)
                }
            }
            .background(AppBackground(accent: accent(of: set)))
            .task(id: services.themePhotos.version(of: set.id)) {
                heroWidgets = ThemeComposition.widgets(for: set, dark: set.isDark, services: services)
            }
            .confirmationDialog("Replace your widgets with \(set.name)?", isPresented: $confirmsReplace) {
                Button("Replace \(services.widgets.widgets.count) Widgets") { install(set, .replace, "Applied") }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Installs \(set.includedWidgets.count) widgets\(setsWallpaper && set.wallpaper != nil ? " and the wallpaper" : ""). You can undo it from the Themes page.")
            }
        } else {
            ContentUnavailableView("Theme not found", systemImage: "questionmark.square.dashed")
        }
    }

    /// Whether the set has pictures to swap for the person's own.
    private static func hasPhotoSlots(_ set: ThemeSet) -> Bool {
        set.widgets(screenName: nil, bounds: ThemeComposition.canvas).contains { [.photo, .vhs, .polaroids, .playerCard, .lockScreen].contains($0.kind) }
    }

    private func install(_ set: ThemeSet, _ mode: ThemeInstall, _ message: String) {
        withMotion(Motion.standard) {
            services.install(set, mode: mode, wallpaper: setsWallpaper)
            done = message
        }
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            withMotion(Motion.standard) { done = nil }
        }
    }

    private func hero(_ set: ThemeSet) -> some View {
        ThemeComposition(set: set, widgets: heroWidgets, services: services, dark: set.isDark, isLive: heroHovering)
            .aspectRatio(ThemeComposition.canvas.width / ThemeComposition.canvas.height, contentMode: .fit)
            .frame(maxWidth: 1080)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.hero, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.hero, style: .continuous).strokeBorder(DS.Surface.hairline))
            .dsElevated()
            .onHover { heroHovering = $0 }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Preview of the \(set.name) desktop")
    }

    private func titleRow(_ set: ThemeSet) -> some View {
        let favorite = services.themeStats.isFavorite(set.id)
        return HStack(alignment: .top, spacing: DS.Space.m) {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                if !set.collections.isEmpty {
                    Text(set.collections.prefix(4).map(\.title).joined(separator: "  ·  ")).dsText(.eyebrow)
                }
                Text(set.name).dsText(.hero)
                Text(set.inspiration ?? set.tagline).dsText(.body, color: DS.Ink.secondary)
            }
            Spacer()
            Button {
                withMotion(Motion.bouncy) { services.themeStats.toggleFavorite(set.id) }
            } label: {
                Image(systemName: favorite ? "heart.fill" : "heart")
                    .foregroundStyle(favorite ? Color.pink : DS.Ink.primary)
            }
            .buttonStyle(FloatingButtonStyle(diameter: 38))
            .help("Favorite")
            .accessibilityLabel(favorite ? "Remove from favorites" : "Add to favorites")
        }
    }

    /// The theme's own accent, for a faint glow at the top of the page.
    private func accent(of set: ThemeSet) -> Color? {
        if let theme = set.designTheme { return Color(theme.palette(dark: set.isDark).accent) }
        return set.setup.map { Color($0.wallpaperAccent) }
    }

    private func actions(_ set: ThemeSet) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            FlowLayout(spacing: DS.Space.xs) {
                Button {
                    confirmsReplace = true
                } label: {
                    Label(done ?? "Apply Theme", systemImage: done == nil ? "square.grid.3x3.topleft.filled" : "checkmark")
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.pillProminent)
                .keyboardShortcut(.defaultAction)
                .help("Replace your widgets with this set")
                Button {
                    services.previewOnDesktop(set, wallpaper: setsWallpaper)
                } label: {
                    Label("Preview on Desktop", systemImage: "eye")
                }
                .help("Try it on the desktop, then keep it or go back")
                .buttonStyle(.pill)
                Button {
                    install(set, .add, "Added")
                } label: {
                    Label("Add Widgets", systemImage: "plus.square.on.square")
                }
                .help("Add this set's widgets next to yours")
                .buttonStyle(.pill)
                Button {
                    install(set, .restyle, "Restyled")
                } label: {
                    Label("Restyle My Widgets", systemImage: "paintbrush")
                }
                .help("Keep your widgets, give them this look")
                .buttonStyle(.pill)
                Button {
                    services.install(set, mode: .replace, wallpaper: setsWallpaper)
                    services.ui.isArrangingWidgets = true
                } label: {
                    Label("Customize", systemImage: "slider.horizontal.3")
                }
                .help("Apply it, then arrange the widgets your way")
                .buttonStyle(.pill)
            }
            if Self.hasPhotoSlots(set) {
                FlowLayout(spacing: DS.Space.xs) {
                    Button {
                        if services.installWithMyPhotos(set, wallpaper: setsWallpaper) {
                            withMotion(Motion.standard) { done = "Applied" }
                            Task {
                                try? await Task.sleep(for: .seconds(2.5))
                                withMotion(Motion.standard) { done = nil }
                            }
                        }
                    } label: {
                        Label("Use My Photos…", systemImage: "person.crop.rectangle.stack")
                    }
                    .help("Apply it with your own pictures in every photo, tape and print")
                    .buttonStyle(.pill)
                    if services.themePhotos.hasPhotos(set.id) {
                        Button {
                            withMotion(Motion.standard) { services.themePhotos.clear(set.id) }
                        } label: {
                            Label("Use Theme Photos", systemImage: "arrow.uturn.backward")
                        }
                        .help("Go back to the photos the theme comes with")
                        .buttonStyle(.pill)
                    }
                    Text(services.themePhotos.hasPhotos(set.id)
                         ? "Showing your \(services.themePhotos.photos[set.id]?.count ?? 0) photos. They're kept on this Mac only."
                         : set.collections.contains(.football) || set.collections.contains(.musicIcons)
                         ? "Add photos of your favorite player or artist: they fill every photo, tape and card."
                         : "Your pictures in every photo, tape and print.")
                        .dsText(.meta)
                }
            }
            Toggle("Change the wallpaper too", isOn: $setsWallpaper)
                .toggleStyle(.checkbox)
                .foregroundStyle(DS.Ink.secondary)
                .disabled(set.wallpaper == nil)
        }
    }

    /// One fact about the theme: a small label over its content, no box.
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            Text(title).dsText(.eyebrow)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func about(_ set: ThemeSet) -> some View {
        section("About") {
            Text(set.description)
            Text(set.philosophy).foregroundStyle(.secondary)
        }
    }

    private func included(_ set: ThemeSet) -> some View {
        section("\(set.includedWidgets.count) Widgets") {
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 8) {
                ForEach(Array(set.includedWidgets.enumerated()), id: \.offset) { _, widget in
                    Label {
                        Text(widget.title) + Text("  \(widget.size.shortTitle)").foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: widget.symbol).foregroundStyle(.tint)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func appearance(_ set: ThemeSet) -> some View {
        section(set.designTheme?.followsAppearance == true ? "Light & Dark" : "Appearance") {
            HStack(spacing: 10) {
                if set.designTheme?.followsAppearance == true {
                    labeled("Light") { ThemeSnapshot(set: set, dark: false, services: services) }
                    labeled("Dark") { ThemeSnapshot(set: set, dark: true, services: services) }
                } else {
                    labeled(set.isDark ? "Dark only" : "Light only") { ThemeSnapshot(set: set, dark: set.isDark, services: services) }
                }
            }
            if let theme = set.designTheme {
                Picker("Wallpaper color", selection: Binding(
                    get: { services.widgets.widgets.first { $0.options.designTheme == theme.id }?.options.accentMode
                            ?? (theme.accentSource == .wallpaper ? .automatic : .fixed) },
                    set: { mode in
                        for widget in services.widgets.widgets where widget.options.designTheme == theme.id {
                            services.widgets.update(widget.id) { $0.options.accentMode = mode }
                        }
                    }
                )) {
                    ForEach(WallpaperAdaptation.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Text("Automatic tints highlights toward your wallpaper's color, never the whole widget. Applies to this theme's widgets on your desktop.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func labeled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            content().clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func palette(_ set: ThemeSet) -> some View {
        section("Colors") {
            let swatches = colors(set)
            HStack(spacing: 12) {
                ForEach(Array(swatches.enumerated()), id: \.offset) { _, swatch in
                    VStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(swatch.1))
                            .frame(width: 52, height: 52)
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.primary.opacity(0.12)))
                        Text(swatch.0).font(.caption2.weight(.semibold))
                        Text(swatch.1.hexString).font(.caption2.monospaced()).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func colors(_ set: ThemeSet) -> [(String, WidgetColor)] {
        if let theme = set.designTheme {
            let palette = theme.palette(dark: set.isDark)
            var swatches = [("Card", palette.background)]
            if let second = palette.background2 { swatches.append(("Glow", second)) }
            swatches += [("Ink", palette.ink), ("Muted", palette.secondaryInk), ("Accent", palette.accent)]
            return swatches
        }
        if let setup = set.setup {
            return [("Card", setup.card), ("Ink", setup.ink), ("Accent", setup.accent), ("Wallpaper", setup.wallpaperAccent)]
        }
        return []
    }

    private func typography(_ set: ThemeSet) -> some View {
        let style = set.designTheme.map { theme in
            WidgetStyle.themed(theme, palette: theme.palette(dark: set.isDark), isDark: set.isDark, accent: Color(theme.palette(dark: set.isDark).accent))
        } ?? WidgetStyle.classic(font: set.setup?.font ?? .standard, accent: .accentColor, cornerRadius: 16)
        return section("Typography") {
            HStack(alignment: .firstTextBaseline, spacing: 18) {
                Text("12:47").font(style.number(44))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Friday, 25 September").font(style.title(15))
                    Text("Up next").font(style.label(11)).textCase(style.uppercaseLabels ? .uppercase : nil).tracking(style.labelTracking)
                        .foregroundStyle(.secondary)
                    Text("All system fonts, in \(set.designTheme?.typography.font.title.lowercased() ?? "the setup's") style.")
                        .font(style.body(11)).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func motion(_ set: ThemeSet) -> some View {
        section("Motion: \(set.motion.title)") {
            MotionPreview(motion: set.motion, accent: set.designTheme.map { Color($0.palette(dark: set.isDark).accent) } ?? .accentColor)
            Text(set.motion.summary + " With Reduce Motion on, everything simply dissolves.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func research(_ set: ThemeSet) -> some View {
        if let research = set.research {
            DisclosureGroup("Design notes & references") {
                VStack(alignment: .leading, spacing: 10) {
                    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                        note("Era", research.visualEra)
                        note("Color", research.color)
                        note("Type", research.typography)
                        note("Motion", research.motion)
                        note("Texture", research.texture)
                        note("Referenced", research.referenced)
                        note("Original", research.original)
                    }
                    Text("References").font(.subheadline.bold()).padding(.top, 4)
                    ForEach(Array((research.primary + research.secondary).enumerated()), id: \.offset) { _, source in
                        if let url = URL(string: source.url) {
                            Link(source.title, destination: url).font(.callout)
                        }
                    }
                    Text("An original theme inspired by public visual characteristics of a genre and era. Not affiliated with or endorsed by any artist; no logos, album art, photography or trademarks are used.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.top, 8)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.quaternary.opacity(0.45)))
        }
    }

    private func note(_ title: String, _ text: String) -> some View {
        GridRow {
            Text(title).font(.callout.weight(.semibold)).foregroundStyle(.secondary)
            Text(text).font(.callout)
        }
    }
}

/// A number changing and a dot arriving, the way the theme moves them.
private struct MotionPreview: View {
    let motion: MotionLanguage
    let accent: Color

    @State private var step = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 18) {
            Text("\(42 + step % 3 * 7)%")
                .font(.system(size: 30, weight: .light).monospacedDigit())
                .contentTransition(motion == .still ? .identity : .numericText())
            ZStack(alignment: step.isMultiple(of: 2) ? .leading : .trailing) {
                Capsule().fill(.primary.opacity(0.08)).frame(width: 140, height: 8)
                Circle().fill(accent).frame(width: 16, height: 16)
            }
            .frame(width: 140)
        }
        .animation(motion.change, value: step)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.6))
                step += 1
            }
        }
        .accessibilityHidden(true)
    }
}

extension WidgetColor {
    /// "#1D1D1F"
    var hexString: String {
        String(format: "#%02X%02X%02X", Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
    }
}
