import AllSetCore
import SwiftUI

/// One theme in the hero carousel: its card picture edge to edge (the
/// wallpaper with a few of its widgets, drawn once by `ThemePreviewCache`),
/// and its words laid over the lower part on a soft scrim. The selected card
/// has the large name, the widget count and the actions; a side card only a
/// small name and count.
struct ThemePreviewCard: View {
    let set: ThemeSet
    let services: AppServices
    let isSelected: Bool
    /// A small card (a short window): a smaller name, no widget count under
    /// it and no badge, so the words don't cover the picture's middle.
    var isCompact = false

    @AppStorage("themes.setsWallpaper") private var setsWallpaper = true

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: DS.Radius.panel, style: .continuous) }

    var body: some View {
        let favorite = services.themeStats.isFavorite(set.id)
        let isActive = services.settings.activeThemeSet == set.id
        let motion = ThemesMotion(services.ui.performance)
        let glow = Color(services.lighting(of: set).primary)
        ZStack {
            // The card decides its size; the picture only fills it.
            Color.clear
                .overlay { ThemeSnapshot(set: set, dark: set.isDark, services: services, fills: true, variant: .card) }
                .clipped()
            // Clear over the picture, darkening toward the words: the art
            // carries on behind them.
            LinearGradient(stops: [.init(color: .clear, location: 0.38),
                                   .init(color: .black.opacity(0.5), location: 0.7),
                                   .init(color: .black.opacity(0.74), location: 1)],
                           startPoint: .top, endPoint: .bottom)
            // Only the selected card has buttons to build; the two sets of
            // words fade into each other as the selection moves.
            if isSelected {
                selectedWords(favorite: favorite, isActive: isActive)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .transition(.opacity)
                if !isCompact {
                    badge(isActive: isActive, glow: glow)
                        .padding(DS.Space.s)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .transition(.opacity)
                }
            } else {
                sideLabel
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .transition(.opacity)
            }
        }
        .clipShape(shape)
        // Lit along its edge in the theme's own color: brightly when
        // selected, faintly otherwise, so the row never reads as gray.
        .overlay(shape.strokeBorder(glow.opacity(isSelected ? 0.75 : 0.3), lineWidth: isSelected ? 1.5 : 1))
        // The words and buttons fade in and out as the selection arrives.
        .animation(motion.fade, value: isSelected)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(set.name) theme, \(set.includedWidgets.count) widgets")
    }

    /// A side card's label: who it is, and no more.
    private var sideLabel: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(set.name)
                .font(.system(size: isCompact ? 14 : 16, weight: .semibold))
                .foregroundStyle(DS.Ink.primary)
                .lineLimit(1)
            Text("\(set.includedWidgets.count) widgets")
                .font(.system(size: isCompact ? 11 : 11.5, weight: .medium))
                .foregroundStyle(DS.Ink.secondary)
        }
        .padding(isCompact ? DS.Space.s : DS.Space.m)
    }

    private func selectedWords(favorite: Bool, isActive: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(set.name)
                .font(.system(size: isCompact ? 24 : 32, weight: .bold))
                .tracking(-0.5)
                .foregroundStyle(DS.Ink.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if !isCompact {
                Text("\(set.includedWidgets.count) widgets")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(DS.Ink.secondary)
            }
            // Whatever of the three fits the card: a narrow one drops the
            // info button (a click on the card opens the theme anyway), then
            // shortens the label.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: DS.Space.xs) { apply(isActive, short: false); info; heart(favorite) }
                HStack(spacing: DS.Space.xs) { apply(isActive, short: false); heart(favorite) }
                HStack(spacing: DS.Space.xs) { apply(isActive, short: true); heart(favorite) }
            }
            .padding(.top, isCompact ? DS.Space.xxs : DS.Space.xs)
        }
        .padding(isCompact ? DS.Space.s : DS.Space.m)
    }

    private func apply(_ isActive: Bool, short: Bool) -> some View {
        Button {
            if isActive {
                withMotion(Motion.standard) { services.turnOffTheme() }
            } else {
                services.install(set, mode: .replace, wallpaper: setsWallpaper)
            }
        } label: {
            Label(isActive ? "Turn Off" : short ? "Apply" : "Apply Theme",
                  systemImage: isActive ? "power" : "square.grid.3x3.topleft.filled")
        }
        .buttonStyle(.pillProminent)
        .fixedSize()
    }

    private var info: some View {
        Button { services.ui.page = .themeSet(set.id) } label: {
            Image(systemName: "info").foregroundStyle(DS.Ink.primary)
        }
        .buttonStyle(.floating)
        .help("View Details")
        .accessibilityLabel("View details")
    }

    private func heart(_ favorite: Bool) -> some View {
        Button {
            withMotion(Motion.standard) { services.themeStats.toggleFavorite(set.id) }
        } label: {
            Image(systemName: favorite ? "heart.fill" : "heart")
                .foregroundStyle(favorite ? Color.pink : DS.Ink.primary)
        }
        .buttonStyle(.floating)
        .accessibilityLabel(favorite ? "Remove from favorites" : "Add to favorites")
    }

    /// A small tinted-glass pill, clear of the card's corner. A fill, not a
    /// material: the card moves, and a material would re-blur what's behind
    /// it every frame.
    private func badge(isActive: Bool, glow: Color) -> some View {
        Text(isActive ? "On your desktop" : "Featured")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                Capsule().fill(.black.opacity(0.42))
                Capsule().fill(glow.opacity(0.3))
            }
            .overlay(Capsule().strokeBorder(.white.opacity(0.24)))
    }
}
