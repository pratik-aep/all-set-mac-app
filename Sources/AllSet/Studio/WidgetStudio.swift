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
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack(alignment: .bottom, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(category?.title ?? "All Widgets")
                            .font(.largeTitle.bold())
                        Text(category == .aesthetic
                             ? "Decorative pieces for the desktop: signs, stickers, prints and scenes."
                             : "\(entries.count) widgets. Pick a size, add it, then make it yours with a theme, colors and settings.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Search widgets", text: $query)
                            .textFieldStyle(.plain)
                        if !query.isEmpty {
                            Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Clear search")
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(width: 220)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.primary.opacity(0.07)))
                }
                if !SearchMatch.normalize(query).isEmpty {
                    if matches.isEmpty {
                        ContentUnavailableView.search(text: query)
                    } else {
                        grid(matches)
                    }
                } else {
                    ForEach(category.map { [$0] } ?? WidgetCategory.allCases) { section in
                        VStack(alignment: .leading, spacing: 14) {
                            if category == nil {
                                Label(section.title, systemImage: section.symbol)
                                    .font(.title2.bold())
                            }
                            grid(WidgetCatalog.entries(in: section))
                        }
                    }
                }
            }
            .padding(28)
        }
    }

    private func grid(_ entries: [CatalogEntry]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 18)], spacing: 18) {
            ForEach(entries) { entry in
                GalleryCard(entry: entry, services: services)
            }
        }
    }
}

private struct GalleryCard: View {
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
        VStack(alignment: .leading, spacing: 12) {
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
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if !isThemed, !looks.isEmpty || kind == .photo {
                    Button {
                        withMotion(Motion.responsive) { variation += 1 }
                    } label: {
                        Image(systemName: "shuffle")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(.black.opacity(0.35)))
                    }
                    .buttonStyle(PressableStyle())
                    .padding(10)
                    .opacity(isHovering ? 1 : 0)
                    .help("Another photo or colors")
                    .accessibilityLabel("Show another look")
                }
            }
            .onHover { hovering in withMotion(Motion.responsive) { isHovering = hovering } }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Preview of \(entry.title)")

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Label(entry.title, systemImage: entry.symbol).font(.headline)
                    Text(entry.summary).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if entry.sizes.count > 1 {
                    Picker("Size", selection: $size.animation(Motion.resolved(Motion.responsive))) {
                        ForEach(entry.sizes) { size in
                            Text(size.shortTitle).tag(size)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
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
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.quaternary.opacity(0.5)))
    }

    private func chips(_ items: [(String, String)], selected: String?, pick: @escaping (String) -> Void) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(items, id: \.0) { id, title in
                    let isSelected = selected == id
                    Button {
                        withMotion(Motion.responsive) { pick(id) }
                    } label: {
                        Text(title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(isSelected ? Color.white : .primary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(isSelected ? Color.accentColor : Color.primary.opacity(0.07)))
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
                    VStack(spacing: 14) {
                        WidgetPreview(instance: instance, services: services, fit: CGSize(width: 380, height: 380))
                            .motion(Motion.responsive, value: instance.size)
                        Text("Live preview")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .frame(width: 420)
                .frame(maxHeight: .infinity)

                Form {
                    WidgetOptionsEditor(id: id, services: services)
                }
                .dsFormStyle()
            }
        } else {
            ContentUnavailableView("Widget removed", systemImage: "square.dashed",
                                   description: Text("Pick another widget, or add one from the gallery."))
        }
    }
}
