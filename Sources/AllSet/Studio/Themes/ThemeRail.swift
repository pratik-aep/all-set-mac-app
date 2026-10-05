import AllSetCore
import SwiftUI

/// One curated row of themes: a title, an optional "See All", and cards
/// that scroll sideways and settle on a card's edge. Lazy: only the cards
/// in view are made.
struct ThemeRail: View {
    let title: String
    let sets: [ThemeSet]
    let services: AppServices
    /// Shows the whole category, when the rail has one.
    var seeAll: (@MainActor () -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            if let seeAll {
                SectionHeader(title: title, subtitle: "\(sets.count) themes", actionTitle: "See All", ) { seeAll() }
            } else {
                SectionHeader(title: title, subtitle: "\(sets.count) themes")
            }
            MediaRail(items: sets, cardWidth: 300) { set in
                RailCard(set: set, services: services)
            }
        }
    }
}

/// A theme in a rail: its desktop, its name, how many widgets, and a line
/// about it. Still at rest (nothing to draw but the picture while
/// scrolling); lifts a little under the pointer and dips when pressed. With
/// Reduce Motion, Low Power Mode or a hot Mac it brightens instead of
/// lifting. Opens the theme's page.
struct RailCard: View {
    let set: ThemeSet
    let services: AppServices

    @State private var isHovering = false

    var body: some View {
        let stats = services.themeStats
        let favorite = stats.isFavorite(set.id)
        let shape = RoundedRectangle(cornerRadius: DS.Radius.media, style: .continuous)
        let motion = ThemesMotion(services.ui.performance)
        let lifted = isHovering && motion.lifts
        Button {
            services.ui.page = .themeSet(set.id)
        } label: {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                ThemeSnapshot(set: set, dark: set.isDark, services: services)
                    .overlay(Color.white.opacity(isHovering ? 0.06 : 0))
                    .clipShape(shape)
                    .overlay(shape.strokeBorder(DS.Surface.hairline))
                    .background { CardHalo(spread: .shadow).foregroundStyle(.black).opacity(lifted ? 0.35 : 0).offset(y: 8) }
                    .scaleEffect(lifted ? 1.03 : 1)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(set.name).dsText(.headline).lineLimit(1)
                        Spacer(minLength: DS.Space.xs)
                        Text("\(set.includedWidgets.count) widgets").dsText(.meta)
                    }
                    Text(set.inspiration ?? set.tagline).dsText(.meta).lineLimit(1)
                }
                .padding(.horizontal, DS.Space.xxs)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(RailCardPress(dips: motion.lifts))
        .overlay(alignment: .topTrailing) {
            Button {
                withMotion(Motion.standard) { stats.toggleFavorite(set.id) }
            } label: {
                Image(systemName: favorite ? "heart.fill" : "heart")
                    .foregroundStyle(favorite ? Color.pink : DS.Ink.primary)
            }
            .buttonStyle(FloatingButtonStyle(diameter: 30))
            .padding(DS.Space.s)
            .opacity(isHovering || favorite ? 1 : 0)
            .accessibilityLabel(favorite ? "Remove from favorites" : "Add to favorites")
        }
        .onHover { hovering in
            withAnimation(motion.fade) { isHovering = hovering }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(set.name) theme, \(set.includedWidgets.count) widgets. \(set.tagline)")
        .accessibilityHint("Opens the theme")
    }
}

/// A tiny dip while the pointer is down; a dimming when cards aren't moving.
private struct RailCardPress: ButtonStyle {
    let dips: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && dips ? 0.98 : 1)
            .opacity(configuration.isPressed && !dips ? 0.8 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
