import AllSetCore
import SwiftUI

/// Which theme the hero is on. A class so the page can hold it (and later
/// set it from a rail) without redrawing itself every time it changes.
@MainActor
@Observable
final class ThemeHeroState {
    var index = 0
}

/// The Themes hero: a rounded glass panel over the page's atmosphere, with
/// the carousel in it, the search field top right and the categories along
/// the bottom. It sizes itself to the window (`ThemeCarouselLayout`), draws
/// the atmosphere behind itself and on down the page, and keeps it on
/// whichever theme the carousel is on.
struct ThemesHero: View {
    let items: [ThemeSet]
    let services: AppServices
    @Bindable var state: ThemeHeroState
    let atmosphere: ThemeAtmosphereState
    /// A `ThemeDiscovery` raw value.
    @Binding var discovery: String
    @Binding var query: String
    let layout: BleedLayout

    private static let railHeight: CGFloat = 34
    /// Under the cards: the gap, the rail and the panel's padding.
    private static let footer = DS.Space.s + railHeight + DS.Space.m
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: DS.Radius.hero, style: .continuous) }

    /// The carousel's sizes for a page. Around the cards, besides what's
    /// under them: the panel's padding above, and the room side cards sink into.
    static func carousel(for layout: BleedLayout) -> ThemeCarouselLayout {
        ThemeCarouselLayout(viewport: layout.viewport, margin: layout.margin,
                            chrome: footer + DS.Space.m + DS.Space.l, footer: footer)
    }

    /// How far down the page the middle of the selected card is.
    static func focusY(for layout: BleedLayout) -> CGFloat {
        let panel = carousel(for: layout).panelSize.height
        return layout.topInset + DS.Space.m + (panel - DS.Space.m - footer) / 2
    }

    var body: some View {
        let set = items[min(max(state.index, 0), items.count - 1)]
        let motion = ThemesMotion(services.ui.performance)
        let carousel = Self.carousel(for: layout)
        VStack(spacing: DS.Space.s) {
            HeroCarousel(items: items, services: services, selection: $state.index, layout: carousel, margin: DS.Space.m)
            CategoryRail(selection: $discovery, reduced: motion.reduced)
                .frame(height: Self.railHeight)
                .padding(.horizontal, DS.Space.m)
        }
        .padding(.vertical, DS.Space.m)
        .frame(maxWidth: .infinity)
        .frame(height: carousel.panelSize.height)
        .overlay(alignment: .topTrailing) {
            SearchField(text: $query, prompt: "Search themes…")
                .frame(width: min(240, carousel.panelSize.width * 0.25))
                .padding(DS.Space.m)
        }
        // Glass, not a wall: the atmosphere behind shows through it.
        .background(Color.white.opacity(0.04))
        .clipShape(shape)
        .overlay(shape.strokeBorder(DS.Surface.hairline))
        .padding(.horizontal, layout.margin)
        // Straight after the navigation: the gap under its cluster is the
        // navigation's own.
        .padding(.top, layout.topInset)
        // The page's content climbs `overlap` onto the hero: that, and a gap.
        .padding(.bottom, layout.overlap + DS.Space.m)
        // Taller than the hero: it carries on behind the first rails.
        .background(alignment: .top) {
            ThemeAtmosphere(state: atmosphere, services: services, focusY: Self.focusY(for: layout), panel: carousel.panelSize)
        }
        .onChange(of: set.id, initial: true) { atmosphere.show(set, animation: motion.backdrop) }
        // Every theme in the row has its backdrop made (or read back from
        // disk) as the page opens, so none is drawn or blurred when the
        // carousel reaches it.
        .task(id: items.map(\.id)) {
            for item in items { services.themePreviews.request(item, dark: item.isDark, variant: .backdrop, services: services) }
        }
        .onDisappear {
            for item in items { services.themePreviews.cancel(item, dark: item.isDark, variant: .backdrop) }
        }
    }
}
