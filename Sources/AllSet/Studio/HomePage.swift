import AllSetCore
import SwiftUI

/// The Desktop section's front door: the theme on the desktop (or today's
/// pick) as a full-bleed hero, shortcuts into each library, then rails.
/// It only composes the pages' own cards, so nothing here has logic of its own.
struct HomePage: View {
    let services: AppServices

    var body: some View {
        let stats = services.themeStats
        let active = services.settings.activeThemeSet.flatMap { ThemeLibrary.set($0) }
        let trending = ThemeDiscovery.trending.sets(stats: stats)
        let lead = active ?? ThemeDiscovery.featured.sets(stats: stats).first ?? trending.first
        BleedScrollPage(showsHero: lead != nil) { layout in
            if let lead {
                FeaturedThemeHero(set: lead, isActive: active != nil, services: services, layout: layout)
            }
        } content: { _ in
            strip
            rail("Trending Themes", subtitle: "\(trending.count) themes", more: .themes) {
                MediaRail(items: trending.filter { $0.id != lead?.id }, cardWidth: 300) { set in
                    ThemeSetCard(set: set, services: services)
                }
            }
            if !favorites.isEmpty {
                rail("Your Favorites", subtitle: "\(favorites.count) themes", more: .themes) {
                    MediaRail(items: favorites, cardWidth: 300) { set in
                        ThemeSetCard(set: set, services: services)
                    }
                }
            }
            rail("Popular Widgets", subtitle: "\(WidgetCatalog.entries.count) in the gallery", more: .gallery(nil)) {
                MediaRail(items: Array(WidgetCatalog.entries.prefix(12)), cardWidth: 220) { entry in
                    GalleryCard(entry: entry, services: services)
                        .frame(height: GalleryCard.height)
                }
            }
            rail("Art", subtitle: "Generative, and every piece can move", more: .art) {
                MediaRail(items: Self.artPicks, cardWidth: 200) { piece in
                    ShortcutArt(piece: piece)
                        .aspectRatio(4 / 3, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.media, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: DS.Radius.media, style: .continuous).strokeBorder(DS.Surface.hairline))
                        .onTapGesture { services.ui.page = .art }
                }
            }
        }
    }

    private var favorites: [ThemeSet] { ThemeDiscovery.favorites.sets(stats: services.themeStats) }

    private static let artPicks: [ArtPiece] = ArtStyle.allCases.enumerated().map { ArtPiece(style: $1, palette: ArtPalette.allCases[($0 * 3) % ArtPalette.allCases.count]) }

    private var strip: some View {
        let art = Self.artPicks
        let items: [(String, String, String, AppPage, Int)] = [
            ("Themes", "\(ThemeLibrary.all.count) desktops", "wand.and.stars", .themes, 0),
            ("Widgets", "\(WidgetCatalog.entries.count) widgets", "square.grid.2x2.fill", .gallery(nil), 1),
            ("Wallpaper", "Live and still", "photo.artframe", .wallpaper, 2),
            ("Art", "\(ArtStyle.allCases.count * ArtPalette.allCases.count) pieces", "paintpalette.fill", .art, 3),
            ("On Your Desktop", "\(services.widgets.widgets.count) placed", "rectangle.on.rectangle", .desktop, 4),
        ]
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Space.m) {
                ForEach(items, id: \.0) { title, subtitle, symbol, page, index in
                    Button { services.ui.page = page } label: {
                        ShortcutArt(piece: art[index % art.count])
                            .overlay(LinearGradient(colors: [.black.opacity(0.8), .black.opacity(0.2), .clear], startPoint: .bottom, endPoint: .top))
                            .overlay(alignment: .bottomLeading) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Image(systemName: symbol).foregroundStyle(DS.Ink.secondary)
                                    Text(title).dsText(.headline)
                                    Text(subtitle).dsText(.meta)
                                }
                                .padding(DS.Space.s)
                            }
                            .frame(width: 190, height: 120)
                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.media, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: DS.Radius.media, style: .continuous).strokeBorder(DS.Surface.hairline))
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel("\(title), \(subtitle)")
                }
            }
            .padding(.vertical, DS.Space.xxs)
        }
    }

    private func rail<Content: View>(_ title: String, subtitle: String, more: AppPage, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            SectionHeader(title: title, subtitle: subtitle, actionTitle: "See All") { services.ui.page = more }
            content()
        }
    }
}

/// A still piece of generative art as a card's backdrop.
private struct ShortcutArt: View {
    let piece: ArtPiece

    var body: some View { ArtView(piece: piece, animated: false) }
}
