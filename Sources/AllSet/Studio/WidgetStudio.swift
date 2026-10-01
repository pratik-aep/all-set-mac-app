import AllSetCore
import AppKit
import SwiftUI

/// A soft, colorful backdrop so glass widgets have something to show through.
struct StudioBackdrop: View {
    var piece = ArtPiece(style: .blobs, palette: .midnight)

    var body: some View {
        ArtView(piece: piece)
            .overlay(Color.black.opacity(0.1))
    }
}

// MARK: Gallery

struct GalleryPage: View {
    let category: WidgetCategory?
    let services: AppServices

    @State private var query = ""

    private var entries: [CatalogEntry] {
        category.map(WidgetCatalog.entries(in:)) ?? WidgetCatalog.entries
    }

    /// Entries whose name matches best first, then those whose words do.
    private var matches: [CatalogEntry] {
        let ranked = SearchMatch.rank(entries, by: query, name: \.title)
        let rankedIDs = Set(ranked.map(\.id))
        return ranked + entries.filter { !rankedIDs.contains($0.id) && SearchMatch.containsAll(query, in: $0.searchText) }
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.section) {
                    VStack(alignment: .leading, spacing: DS.Space.m) {
                        PageHeader(eyebrow: "\(entries.count) widgets",
                                   title: category?.title ?? "Widget Gallery",
                                   subtitle: category == .aesthetic
                                       ? "Decorative pieces for the desktop: signs, stickers, prints and scenes."
                                       : "Pick a size, add it, then make it yours with a theme, colors and settings.") {
                            SearchField(text: $query, prompt: "Search widgets")
                                .frame(width: geometry.size.width < 1000 ? 220 : 280)
                        }
                        categoryPills
                    }
                    if !SearchMatch.normalize(query).isEmpty {
                        if matches.isEmpty {
                            EmptyState(symbol: "magnifyingglass", title: "No widgets match \u{201C}\(query)\u{201D}",
                                       message: "Try another word, or clear the search.",
                                       actionTitle: "Clear Search", action: { query = "" })
                        } else {
                            grid(matches)
                        }
                    } else {
                        ForEach(category.map { [$0] } ?? WidgetCategory.allCases) { section in
                            VStack(alignment: .leading, spacing: DS.Space.m) {
                                if category == nil {
                                    let count = WidgetCatalog.entries(in: section).count
                                    SectionHeader(title: section.title, subtitle: "\(count) widgets",
                                                  actionTitle: "See All", action: { services.ui.page = .gallery(section) })
                                }
                                grid(WidgetCatalog.entries(in: section))
                            }
                        }
                    }
                }
                .padding(.horizontal, DS.Space.pageMargin(for: geometry.size.width))
                .padding(.vertical, DS.Space.xl)
            }
        }
    }

    /// Every category a click away, so a category page never strands you.
    private var categoryPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Space.xs) {
                FilterPill(title: "All", symbol: "square.grid.2x2.fill", isSelected: category == nil) {
                    services.ui.page = .gallery(nil)
                }
                ForEach(WidgetCategory.allCases) { item in
                    FilterPill(title: item.title, symbol: item.symbol, isSelected: category == item) {
                        services.ui.page = .gallery(item)
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func grid(_ entries: [CatalogEntry]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: DS.Space.l)], spacing: DS.Space.l) {
            ForEach(entries) { entry in
                GalleryCard(entry: entry, services: services)
            }
        }
    }
}

struct GalleryCard: View {
    let entry: CatalogEntry
    let services: AppServices

    @State private var size: WidgetSize
    @State private var added = false
    /// Nil keeps the widget's own starting look.
    @State private var look: WidgetMaterial?
    /// A design theme picked on the card, for widgets drawn by themes.
    @State private var theme: String?
    /// Moves through the curated photos and palettes.
    @State private var variation = 0
    @State private var isHovering = false

    init(entry: CatalogEntry, services: AppServices) {
        self.entry = entry
        self.services = services
        _size = State(initialValue: entry.defaultSize)
    }

    private var kind: WidgetKind { entry.kind }
    private var entryIndex: Int { WidgetCatalog.entries.firstIndex { $0.id == entry.id } ?? 0 }
    /// Whether it starts out drawn by a design theme.
    private var isThemed: Bool { entry.make().options.designTheme != nil }

    /// Looks worth offering: kinds that paint their own backgrounds have none.
    private var looks: [WidgetMaterial] {
        switch kind {
        case .note, .photo, .ambient, .vinyl, .moon, .daylight, .polaroids, .sticker, .jersey, .playerCard, .pitch,
             .scoreboard, .cassette, .vhs, .visualizer, .ticket, .wordArt,
             .spiral, .charm, .label, .aura, .tarot, .zodiac, .eightBall, .candle: []
        case .neon: [.clear, .outline, .dark]
        default: [.photo, .paper, .frosted, .outline, .mesh, .glass, .art, .clear, .tinted, .dark]
        }
    }

    private static let themeChoices = ["native", "liquidGlass", "darkGlass", "aurora", "neumorphism", "editorial", "terminal", "brutalist"]

    private var sample: WidgetInstance {
        var instance = entry.make(size: size)
        if isThemed {
            if let theme { instance.options.designTheme = theme }
            return instance
        }
        let material = look ?? instance.material
        instance.material = material
        let palettes: [ArtPalette] = [.midnight, .aurora, .sunset, .lavender, .ocean, .neon, .peach, .forest]
        switch material {
        case .photo:
            if look != nil || variation > 0 {
                instance.options.background = .web(CuratedBackgrounds.suggestion(entryIndex * 11 + variation * 7))
            }
        case .mesh, .art:
            if look != nil || variation > 0 {
                instance.options.art = ArtPiece(style: material == .art ? ArtStyle.allCases[(entryIndex + variation) % ArtStyle.allCases.count] : .aurora,
                                                palette: palettes[(entryIndex + variation) % palettes.count])
            }
        case .tinted:
            instance.tint = WidgetColor.presets[(entryIndex + variation) % WidgetColor.presets.count]
        case .paper, .frosted:
            // A theme that uses this card, for colors that belong together.
            let themes = WidgetTheme.all.filter { $0.material == material }
            if look != nil || variation > 0, !themes.isEmpty {
                instance = themes[(entryIndex + variation) % themes.count].styled(instance)
                instance.material = material
            }
        case .clear where kind == .neon:
            let glows = [0xFF3CAC, 0x2DE2E6, 0xFFD23F, 0x9B5CFF, 0xFF3D3D]
            instance.tint = WidgetColor(hex: glows[(entryIndex + variation) % glows.count])
        case .clear:
            // The gallery's backdrops are dark.
            instance.tint = WidgetColor(red: 1, green: 1, blue: 1)
            instance.options.ink = WidgetColor(red: 1, green: 1, blue: 1)
            instance.options.accent = WidgetColor(red: 1, green: 1, blue: 1)
        default:
            break
        }
        return instance
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            ZStack {
                StudioBackdrop(piece: ArtPiece(style: .blobs, palette: backdropPalette))
                WidgetPreview(instance: sample, services: services, fit: CGSize(width: 250, height: 190))
                    // Moving widgets come alive under the pointer; a page of
                    // them all moving at once would keep the Mac busy.
                    .environment(\.widgetIsVisible, isHovering)
                    .scaleEffect(isHovering ? 1.03 : 1)
                    .id("\(look?.rawValue ?? "default")-\(theme ?? "")-\(variation)-\(size.rawValue)")
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous).strokeBorder(DS.Surface.hairline))
            .overlay(alignment: .topTrailing) {
                if !isThemed, !looks.isEmpty || kind == .photo {
                    Button {
                        withMotion(Motion.responsive) { variation += 1 }
                    } label: {
                        Image(systemName: "shuffle")
                    }
                    .buttonStyle(FloatingButtonStyle(diameter: 30))
                    .padding(DS.Space.s)
                    .opacity(isHovering ? 1 : 0)
                    .help("Another photo or colors")
                    .accessibilityLabel("Show another look")
                }
            }
            .onHover { hovering in withMotion(Motion.responsive) { isHovering = hovering } }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Preview of \(entry.title)")

            HStack(alignment: .top, spacing: DS.Space.s) {
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Label(entry.title, systemImage: entry.symbol).dsText(.headline)
                    Text(entry.summary).dsText(.meta).lineLimit(2)
                }
                Spacer(minLength: 0)
                if entry.sizes.count > 1 {
                    Picker("Size", selection: $size.animation(Motion.resolved(Motion.responsive))) {
                        ForEach(entry.sizes) { size in
                            Text(size.shortTitle).tag(size)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .controlSize(.small)
                    .help("Size")
                }
            }

            if isThemed {
                chips(Self.themeChoices.compactMap(DesignTheme.named).map { ($0.id, $0.title) },
                      selected: theme ?? sample.options.designTheme) { id in theme = id }
            } else if !looks.isEmpty {
                chips(looks.map { ($0.rawValue, $0.title) }, selected: (look ?? entry.make().material).rawValue) { raw in
                    look = WidgetMaterial(rawValue: raw)
                }
            }

            Button {
                services.addWidget(sample)
                withMotion(Motion.responsive) { added = true }
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    withMotion(Motion.standard) { added = false }
                }
            } label: {
                Label(added ? "Added" : "Add to Desktop", systemImage: added ? "checkmark" : "plus")
                    .contentTransition(.symbolEffect(.replace))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.pillProminent)
        }
        .padding(DS.Space.s)
        .background(RoundedRectangle(cornerRadius: DS.Radius.media, style: .continuous).fill(DS.Surface.raised))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.media, style: .continuous).strokeBorder(DS.Surface.hairline))
    }

    private func chips(_ items: [(String, String)], selected: String?, pick: @escaping (String) -> Void) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Space.xxs + 2) {
                ForEach(items, id: \.0) { id, title in
                    let isSelected = selected == id
                    Button {
                        withMotion(Motion.responsive) { pick(id) }
                    } label: {
                        Text(title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(isSelected ? Color.black.opacity(0.88) : DS.Ink.secondary)
                            .padding(.horizontal, 9)
                            .frame(height: 22)
                            .background(Capsule().fill(isSelected ? Color.white.opacity(0.92) : DS.Surface.hover))
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
    }

    /// A different backdrop per entry keeps the gallery lively.
    private var backdropPalette: ArtPalette {
        let palettes: [ArtPalette] = [.midnight, .ocean, .lavender, .forest, .neon, .sunset, .aurora]
        return palettes[entryIndex % palettes.count]
    }
}

// MARK: Inspector

struct WidgetInspector: View {
    let id: UUID
    let services: AppServices

    var body: some View {
        if let instance = services.widgets.instance(id) {
            HStack(spacing: 0) {
                ZStack {
                    StudioBackdrop()
                    VStack(spacing: DS.Space.m) {
                        WidgetPreview(instance: instance, services: services, fit: CGSize(width: 360, height: 360))
                            .motion(Motion.responsive, value: instance.size)
                        Text("Live preview").dsText(.eyebrow, color: .white.opacity(0.7))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.panel, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.panel, style: .continuous).strokeBorder(DS.Surface.hairline))
                .overlay(alignment: .topLeading) {
                    Button {
                        services.ui.page = .desktop
                    } label: {
                        Label("On Your Desktop", systemImage: "chevron.left")
                    }
                    .buttonStyle(.pill)
                    .padding(DS.Space.s)
                }
                .overlay(alignment: .topTrailing) {
                    Button {
                        withMotion(Motion.quick) { services.removeWidget(id) }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.floating)
                    .padding(DS.Space.s)
                    .help("Remove from the desktop")
                    .accessibilityLabel("Remove \(instance.kind.title) from the desktop")
                }
                .frame(width: 400)
                .frame(maxHeight: .infinity)
                .padding([.leading, .bottom], DS.Space.l)

                Form {
                    WidgetOptionsEditor(id: id, services: services)
                }
                .dsFormStyle()
            }
        } else {
            EmptyState(symbol: "square.dashed", title: "Widget removed",
                       message: "Pick another widget, or add one from the gallery.",
                       actionTitle: "On Your Desktop", action: { services.ui.page = .desktop })
        }
    }
}

// MARK: On your desktop

/// Every widget on the desktop now, to customize or remove (with Undo).
struct DesktopWidgetsPage: View {
    let services: AppServices

    var body: some View {
        let widgets = services.widgets.widgets
        PageScaffold {
            PageHeader(eyebrow: widgets.count == 1 ? "1 widget" : "\(widgets.count) widgets", title: "On Your Desktop",
                       subtitle: "Click one to customize it. Removing is instant, and Undo brings it back.") {
                HStack(spacing: DS.Space.xs) {
                    Button {
                        services.ui.isArrangingWidgets.toggle()
                    } label: {
                        Label(services.ui.isArrangingWidgets ? "Done Arranging" : "Arrange", systemImage: "hand.draw")
                    }
                    .buttonStyle(.pill)
                    .disabled(widgets.isEmpty)
                    Button {
                        services.ui.page = .gallery(nil)
                    } label: {
                        Label("Add Widgets", systemImage: "plus")
                    }
                    .buttonStyle(.pillProminent)
                }
            }
            if widgets.isEmpty {
                EmptyState(symbol: "rectangle.dashed", title: "No widgets yet",
                           message: "Pick a theme for a whole desktop at once, or add widgets one by one.",
                           actionTitle: "Browse Themes", action: { services.ui.page = .themes })
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: DS.Space.l)], spacing: DS.Space.l) {
                    ForEach(Array(widgets.enumerated()), id: \.element.id) { index, instance in
                        DesktopWidgetCard(instance: instance, index: index, services: services)
                    }
                }
            }
        }
    }
}

private struct DesktopWidgetCard: View {
    let instance: WidgetInstance
    let index: Int
    let services: AppServices

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            Button {
                services.ui.page = .widget(instance.id)
            } label: {
                ZStack {
                    StudioBackdrop(piece: ArtPiece(style: .blobs, palette: Self.palettes[index % Self.palettes.count]))
                    WidgetPreview(instance: instance, services: services, fit: CGSize(width: 200, height: 140))
                        // Still until pointed at, like the gallery.
                        .environment(\.widgetIsVisible, isHovering)
                        .allowsHitTesting(false)
                }
                .frame(height: 170)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous).strokeBorder(DS.Surface.hairline))
                .scaleEffect(isHovering ? 1.02 : 1)
                .contentShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            }
            .buttonStyle(.plain)
            .onHover { hovering in withMotion(Motion.responsive) { isHovering = hovering } }
            .accessibilityLabel("Customize \(instance.kind.title)")

            HStack(spacing: DS.Space.s) {
                Image(systemName: instance.kind.symbol).foregroundStyle(DS.Ink.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(instance.kind.title).dsText(.headline).lineLimit(1)
                    Text(instance.size.title).dsText(.meta)
                }
                Spacer(minLength: 0)
                Button {
                    services.ui.page = .widget(instance.id)
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .buttonStyle(FloatingButtonStyle(diameter: 30))
                .help("Customize")
                .accessibilityLabel("Customize \(instance.kind.title)")
                Button {
                    withMotion(Motion.quick) { services.removeWidget(instance.id) }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(FloatingButtonStyle(diameter: 30))
                .help("Remove from the desktop")
                .accessibilityLabel("Remove \(instance.kind.title) from the desktop")
            }
        }
    }

    private static let palettes: [ArtPalette] = [.midnight, .ocean, .lavender, .forest, .neon, .sunset, .aurora]
}
