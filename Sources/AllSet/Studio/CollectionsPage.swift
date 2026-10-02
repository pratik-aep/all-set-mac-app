import AllSetCore
import SwiftUI

/// Curated groups of themes: a rail of covers, and the chosen collection's
/// themes beneath it.
struct CollectionsPage: View {
    let services: AppServices

    @State private var selected = ThemeCollection.featured

    private var collections: [(collection: ThemeCollection, sets: [ThemeSet])] {
        ThemeCollection.allCases.compactMap { collection in
            let sets = ThemeLibrary.sets(in: collection)
            return sets.isEmpty ? nil : (collection, sets)
        }
    }

    var body: some View {
        let all = collections
        let current = all.first { $0.collection == selected } ?? all.first
        PageScaffold {
            PageHeader(eyebrow: "\(all.count) curated groups", title: "Collections",
                       subtitle: "Themes gathered by mood, music and craft. Pick a cover to see what's inside.")
            MediaRail(items: covers(all), cardWidth: 260) { cover in
                CoverCard(cover: cover, isSelected: cover.collection == current?.collection, services: services) {
                    withMotion(Motion.quick) { selected = cover.collection }
                }
            }
            if let current {
                SectionHeader(title: current.collection.title, subtitle: "\(current.sets.count) themes")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: DS.Space.m)], spacing: DS.Space.l) {
                    ForEach(current.sets) { set in ThemeSetCard(set: set, services: services) }
                }
            }
        }
    }

    /// Each cover shows a theme no earlier cover has, where the collection has one.
    private func covers(_ all: [(collection: ThemeCollection, sets: [ThemeSet])]) -> [Cover] {
        var used = Set<String>()
        return all.map { entry in
            let lead = entry.sets.first { !used.contains($0.id) } ?? entry.sets[0]
            used.insert(lead.id)
            return Cover(collection: entry.collection, lead: lead, count: entry.sets.count)
        }
    }

    struct Cover: Identifiable {
        let collection: ThemeCollection
        let lead: ThemeSet
        let count: Int
        var id: String { collection.id }
    }

    private struct CoverCard: View {
        let cover: Cover
        let isSelected: Bool
        let services: AppServices
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                ThemeSnapshot(set: cover.lead, dark: cover.lead.isDark, services: services, fills: true)
                    .frame(height: 150)
                    .overlay(LinearGradient(colors: [.black.opacity(0.8), .clear], startPoint: .bottom, endPoint: .center))
                    .overlay(alignment: .bottomLeading) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(cover.collection.title).dsText(.headline)
                            Text("\(cover.count) themes").dsText(.meta)
                        }
                        .padding(DS.Space.s)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.media, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: DS.Radius.media, style: .continuous)
                        .strokeBorder(isSelected ? DS.Ink.primary : DS.Surface.hairline, lineWidth: isSelected ? 2 : 1))
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("\(cover.collection.title), \(cover.count) themes")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
    }
}

/// The themes you hearted, and the ones you used lately.
struct FavoritesPage: View {
    let services: AppServices

    enum Tab: String, CaseIterable, Identifiable {
        case favorites = "Favorites", recent = "Recent"
        var id: String { rawValue }
        var symbol: String { self == .favorites ? "heart.fill" : "clock.fill" }
    }

    @State private var tab = Tab.favorites

    private var sets: [ThemeSet] {
        let stats = services.themeStats
        switch tab {
        case .favorites:
            return ThemeDiscovery.favorites.sets(stats: stats)
        case .recent:
            return ThemeLibrary.all
                .compactMap { set in stats.records[set.id]?.lastUsed.map { (set, $0) } }
                .sorted { $0.1 > $1.1 }
                .prefix(24).map(\.0)
        }
    }

    var body: some View {
        let sets = self.sets
        PageScaffold {
            PageHeader(eyebrow: "Yours", title: "Favorites", subtitle: "Themes you hearted and the ones you used lately.")
            HStack(spacing: DS.Space.xs) {
                ForEach(Tab.allCases) { item in
                    FilterPill(title: item.rawValue, symbol: item.symbol, isSelected: tab == item) {
                        withMotion(Motion.quick) { tab = item }
                    }
                }
            }
            if sets.isEmpty {
                EmptyState(symbol: tab.symbol,
                           title: tab == .favorites ? "No favorites yet" : "Nothing used yet",
                           message: tab == .favorites ? "Tap the heart on any theme to keep it here." : "Themes you install or try show up here.",
                           actionTitle: "Browse Themes", action: { services.ui.page = .themes })
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: DS.Space.m)], spacing: DS.Space.l) {
                    ForEach(sets) { set in ThemeSetCard(set: set, services: services) }
                }
            }
        }
    }
}
