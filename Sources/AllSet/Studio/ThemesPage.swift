import AllSetCore
import AppKit
import SwiftUI

/// Ways to browse the library.
enum ThemeDiscovery: String, CaseIterable, Identifiable {
    case all, featured, trending, new, artist, football, music, seasonal, popular, minimal, dark, colorful, developer, favorites

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
        case .seasonal: "Seasonal"
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
        case .seasonal: "leaf"
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
        case .seasonal:
            let month = Calendar.current.component(.month, from: now)
            return all.filter { !$0.seasons.isEmpty || $0.collections.contains(.seasonal) }
                .sorted { ($0.seasons.contains(month) ? 0 : 1) < ($1.seasons.contains(month) ? 0 : 1) }
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
    @FocusState private var searchFocused: Bool

    private var filter: ThemeDiscovery { ThemeDiscovery(rawValue: discovery) ?? .all }

    private var results: [ThemeSet] {
        let base = filter.sets(stats: services.themeStats)
        guard !SearchMatch.normalize(query).isEmpty else { return base }
        let matches = Set(ThemeLibrary.search(query).map(\.id))
        return ThemeLibrary.search(query).filter { set in base.contains { $0.id == set.id } && matches.contains(set.id) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header
                banners
                chips
                if filter == .all && SearchMatch.normalize(query).isEmpty {
                    shelves
                } else {
                    grid(results)
                }
            }
            .padding(28)
        }
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Themes").font(.largeTitle.bold())
                Text("Complete desktops. Pick one and your whole desktop follows: the widgets, their look, the way they move and the wallpaper.")
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 16)
            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search themes: night, pink, developerâ¦", text: $query)
                        .textFieldStyle(.plain)
                        .focused($searchFocused)
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Clear search")
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(width: 280)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.primary.opacity(0.07)))
                Toggle("Change the wallpaper too", isOn: $setsWallpaper)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var banners: some View {
        if let undo = services.ui.themeUndo {
            HStack(spacing: 12) {
                Image(systemName: "arrow.uturn.backward.circle.fill").font(.title2).foregroundStyle(.tint)
                Text("\(undo.name) is on your desktop. Undo puts back your widgets, their look and your wallpaper.")
                Spacer()
                Button("Undo") { withMotion(Motion.standard) { services.undoTheme() } }
                Button("Keep It") { withMotion(Motion.standard) { services.ui.themeUndo = nil } }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.tint.opacity(0.12)))
        }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ThemeDiscovery.allCases) { item in
                    let selected = filter == item
                    Button {
                        withMotion(Motion.quick) { discovery = item.rawValue }
                    } label: {
                        Label(item.title, systemImage: selected ? item.symbol + ".fill" : item.symbol)
                            .labelStyle(.titleAndIcon)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(selected ? Color.white : .primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(selected ? Color.accentColor : Color.primary.opacity(0.07)))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var shelves: some View {
        VStack(alignment: .leading, spacing: 30) {
            let sections = sections
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 420), spacing: 20)], spacing: 20) {
                ForEach(sections.featured) { set in
                    ThemeSetCard(set: set, services: services, large: true)
                }
            }
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
            ("Football", claim(ThemeDiscovery.football.sets(stats: stats)), .football),
            ("Music Icons", claim(ThemeDiscovery.music.sets(stats: stats)), .music),
            ("Moodboards", claim(ThemeDiscovery.artist.sets(stats: stats)), .artist),
            ("Trending now", claim(ThemeDiscovery.trending.sets(stats: stats)), .trending),
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
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(.title2.bold())
                    Spacer()
                    if let more {
                        Button("See All") { withMotion(Motion.quick) { discovery = more.rawValue } }
                            .buttonStyle(.link)
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 16) {
                        ForEach(sets) { set in
                            ThemeSetCard(set: set, services: services).frame(width: 300)
                        }
                    }
                    .padding(.bottom, 4)
                }
            }
        }
    }

    @ViewBuilder
    private func grid(_ sets: [ThemeSet]) -> some View {
        if sets.isEmpty {
            ContentUnavailableView(filter == .favorites ? "No favorites yet" : "No themes found",
                                   systemImage: filter == .favorites ? "heart" : "magnifyingglass",
                                   description: Text(filter == .favorites ? "Tap the heart on any theme to keep it here." : "Try another word or filter."))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 18)], spacing: 22) {
                ForEach(sets) { set in ThemeSetCard(set: set, services: services) }
            }
        }
    }
}

/// A theme set as a card: a miniature desktop of the whole set, its name,
/// what inspired it and how many widgets it brings. Opens its detail page.
private struct ThemeSetCard: View {
    let set: ThemeSet
    let services: AppServices
    var large = false

    @State private var isHovering = false

    var body: some View {
        let stats = services.themeStats
        Button {
            services.ui.page = .themeSet(set.id)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                ThemeSnapshot(set: set, dark: set.isDark, services: services)
                    .clipShape(RoundedRectangle(cornerRadius: large ? 16 : 12, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        Button {
                            withMotion(Motion.bouncy) { stats.toggleFavorite(set.id) }
                        } label: {
                            Image(systemName: stats.isFavorite(set.id) ? "heart.fill" : "heart")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(stats.isFavorite(set.id) ? Color.pink : .white)
                                .frame(width: 28, height: 28)
                                .background(Circle().fill(.black.opacity(0.4)))
                        }
                        .buttonStyle(PressableStyle())
                        .padding(8)
                        .opacity(isHovering || stats.isFavorite(set.id) ? 1 : 0)
                        .accessibilityLabel(stats.isFavorite(set.id) ? "Remove from favorites" : "Add to favorites")
                    }
                    .scaleEffect(isHovering ? 1.015 : 1)
                    .shadow(color: .black.opacity(isHovering ? 0.25 : 0.12), radius: isHovering ? 14 : 6, y: isHovering ? 8 : 3)
                HStack(alignment: .firstTextBaseline) {
                    Text(set.name).font(large ? .title2.bold() : .headline)
                    Spacer(minLength: 6)
                    Text("\(set.includedWidgets.count) widgets")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text(set.inspiration ?? set.tagline)
                    .font(large ? .callout : .caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
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

/// A theme's preview picture, drawn on first sight.
private struct ThemeSnapshot: View {
    let set: ThemeSet
    let dark: Bool
    let services: AppServices

    var body: some View {
        let cache = services.themePreviews
        ZStack {
            if let image = cache.image(for: set, dark: dark) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill).transition(.opacity)
            } else {
                Rectangle().fill(.quaternary)
                    .overlay(ProgressView().controlSize(.small))
            }
        }
        .aspectRatio(ThemeComposition.canvas.width / ThemeComposition.canvas.height, contentMode: .fit)
        .motion(Motion.standard, value: cache.image(for: set, dark: dark) != nil)
        .task(id: cache.key(set, dark: dark)) { cache.request(set, dark: dark, services: services) }
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
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Button {
                        services.ui.page = .themes
                    } label: {
                        Label("Themes", systemImage: "chevron.left")
                    }
                    .buttonStyle(.link)
                    hero(set)
                    titleRow(set)
                    actions(set)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 360), spacing: 22, alignment: .top)], alignment: .leading, spacing: 22) {
                        about(set)
                        included(set)
                        appearance(set)
                        palette(set)
                        typography(set)
                        motion(set)
                    }
                    research(set)
                }
                .padding(28)
            }
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
            .frame(maxWidth: 980)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
            .onHover { heroHovering = $0 }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Preview of the \(set.name) desktop")
    }

    private func titleRow(_ set: ThemeSet) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(set.name).font(.system(size: 40, weight: .bold))
                if let inspiration = set.inspiration {
                    Text(inspiration).font(.title3).foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    ForEach(set.collections.prefix(5)) { collection in
                        Text(collection.title)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(.primary.opacity(0.07)))
                    }
                }
            }
            Spacer()
            Button {
                withMotion(Motion.bouncy) { services.themeStats.toggleFavorite(set.id) }
            } label: {
                Image(systemName: services.themeStats.isFavorite(set.id) ? "heart.fill" : "heart")
                    .font(.title2)
                    .foregroundStyle(services.themeStats.isFavorite(set.id) ? Color.pink : .secondary)
            }
            .buttonStyle(PressableStyle())
            .help("Favorite")
            .accessibilityLabel(services.themeStats.isFavorite(set.id) ? "Remove from favorites" : "Add to favorites")
        }
    }

    private func actions(_ set: ThemeSet) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    confirmsReplace = true
                } label: {
                    Label(done ?? "Apply Theme", systemImage: done == nil ? "square.grid.3x3.topleft.filled" : "checkmark")
                        .contentTransition(.symbolEffect(.replace))
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .help("Replace your widgets with this set")
                Button {
                    services.previewOnDesktop(set, wallpaper: setsWallpaper)
                } label: {
                    Label("Preview on Desktop", systemImage: "eye")
                }
                .help("Try it on the desktop, then keep it or go back")
                Button {
                    install(set, .add, "Added")
                } label: {
                    Label("Add Widgets", systemImage: "plus.square.on.square")
                }
                .help("Add this set's widgets next to yours")
                Button {
                    install(set, .restyle, "Restyled")
                } label: {
                    Label("Restyle My Widgets", systemImage: "paintbrush")
                }
                .help("Keep your widgets, give them this look")
                Button {
                    services.install(set, mode: .replace, wallpaper: setsWallpaper)
                    services.ui.isArrangingWidgets = true
                } label: {
                    Label("Customize", systemImage: "slider.horizontal.3")
                }
                .help("Apply it, then arrange the widgets your way")
            }
            .controlSize(.large)
            if Self.hasPhotoSlots(set) {
                HStack(spacing: 10) {
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
                    if services.themePhotos.hasPhotos(set.id) {
                        Button {
                            withMotion(Motion.standard) { services.themePhotos.clear(set.id) }
                        } label: {
                            Label("Use Theme Photos", systemImage: "arrow.uturn.backward")
                        }
                        .help("Go back to the photos the theme comes with")
                    }
                    Text(services.themePhotos.hasPhotos(set.id)
                         ? "Showing your \(services.themePhotos.photos[set.id]?.count ?? 0) photos. They're kept on this Mac only."
                         : set.collections.contains(.football) || set.collections.contains(.musicIcons)
                         ? "Add photos of your favorite player or artist: they fill every photo, tape and card."
                         : "Your pictures in every photo, tape and print.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Toggle("Change the wallpaper too", isOn: $setsWallpaper)
                .toggleStyle(.checkbox)
                .disabled(set.wallpaper == nil)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.quaternary.opacity(0.45)))
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
