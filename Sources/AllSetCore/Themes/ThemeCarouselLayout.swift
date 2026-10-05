import CoreGraphics
import Foundation

/// The Themes hero's sizes for a window, worked out in one place so the
/// panel, the carousel and its cards agree, and so the rules can be tested.
///
/// A taller window gets a larger hero. Cards are always portrait (3:4) and
/// the selected one takes 85 to 90% of the panel's height above the category
/// rail. The row loops, so the selected card always has neighbours on both
/// sides; how many of them show is whatever the panel's width leaves.
public struct ThemeCarouselLayout: Equatable, Sendable {
    /// Width over height of every card.
    public static let cardAspect: CGFloat = 0.75
    /// How much of a card's edge sits behind the card in front of it, as
    /// seen: enough to read as behind it, short of the label that starts
    /// 16 pt in from that edge (15 pt of the smallest card, at its scale).
    public static let tuck: CGFloat = 9
    /// Neighbours a side that can show, in a window wide enough for them.
    public static let reach = 3

    /// The glass panel.
    public let panelSize: CGSize
    /// The selected card; the others scale down from it.
    public let cardSize: CGSize

    /// - Parameters:
    ///   - viewport: The page below the navigation.
    ///   - margin: The page's side margin.
    ///   - chrome: What the panel holds above and below the cards: its
    ///     padding, the category rail, and the room side cards sink into.
    ///   - footer: The part of that under the cards: the rail, the gap
    ///     above it and the panel's bottom padding.
    public init(viewport: CGSize, margin: CGFloat, chrome: CGFloat, footer: CGFloat) {
        // Most of the first screen, leaving the first rail's title in sight.
        let panelHeight = min(max(viewport.height * 0.76, 350), 640)
        let panelWidth = max(viewport.width - margin * 2, 0)
        let cardHeight = max(min(panelHeight - chrome, (panelHeight - footer) * 0.9), 0)
        panelSize = CGSize(width: panelWidth, height: panelHeight)
        cardSize = CGSize(width: cardHeight * Self.cardAspect, height: cardHeight)
    }

    /// How far along the row, from its center, a card sits when it is
    /// `distance` cards away (fractions while the row moves). Each card
    /// tucks `tuck` points of its edge behind the one in front of it, so
    /// the steps shorten outward as the cards shrink and turn.
    public func offset(at distance: CGFloat, flat: Bool = false) -> CGFloat {
        let away = abs(distance)
        let whole = Int(away.rounded(.down))
        var along: CGFloat = 0
        for card in 0..<whole { along += step(from: card, flat: flat) }
        along += step(from: whole, flat: flat) * (away - CGFloat(whole))
        return distance < 0 ? -along : along
    }

    /// From the selected card's center to its neighbour's: what one card of
    /// dragging or swiping covers.
    public func step(flat: Bool = false) -> CGFloat { step(from: 0, flat: flat) }

    private func step(from card: Int, flat: Bool) -> CGFloat {
        max(halfWidth(card, flat: flat) + halfWidth(card + 1, flat: flat) - Self.tuck, 1)
    }

    /// Half of what a card's width looks like once it's shrunk and turned.
    private func halfWidth(_ card: Int, flat: Bool) -> CGFloat {
        let depth = ThemeCarouselDepth(distance: CGFloat(card), flat: flat)
        return cardSize.width * depth.scale / 2 * cos(depth.tilt * .pi / 180)
    }
}

/// How a card looks at a distance from the carousel's center, in cards:
/// 0 is the selected one, 1 a neighbour, fractions while the row moves.
/// Everything a card does on the way (shrink, darken, turn, sink) comes from
/// that one number, so a drag, a swipe and a key press all look alike.
public struct ThemeCarouselDepth: Equatable, Sendable {
    /// 1, then 0.85 for a neighbour and 0.7 for the next.
    public let scale: CGFloat
    /// How much black lies over the card (0...1): 0.2 on a neighbour, 0.5 on
    /// the next. Side cards are darkened, not made see-through: a
    /// see-through card lets the one behind it show through.
    public let dim: CGFloat
    /// 1 for every card in the row; the one past the last fades out before
    /// it arrives.
    public let opacity: CGFloat
    /// Degrees about the vertical axis, turning the card toward the center:
    /// 14 for a neighbour, 20 for the next.
    public let tilt: CGFloat
    /// Points down.
    public let dip: CGFloat
    /// How much of the selected card's glow and lift it has (0...1).
    public let glow: CGFloat

    /// - Parameters:
    ///   - flat: No rotation (Reduce Motion).
    ///   - reach: Neighbours a side that show.
    public init(distance: CGFloat, flat: Bool = false, reach: Int = ThemeCarouselLayout.reach) {
        let away = abs(distance)
        scale = away <= 2 ? 1 - 0.15 * away : max(0.7 - 0.1 * (away - 2), 0.55)
        dim = away <= 1 ? 0.2 * away : away <= 2 ? 0.2 + 0.3 * (away - 1) : min(0.5 + 0.18 * (away - 2), 0.72)
        opacity = min(max(1 - 2 * (away - CGFloat(reach)), 0), 1)
        let turn = away <= 1 ? 14 * away : away <= 2 ? 14 + 6 * (away - 1) : min(20 + 4 * (away - 2), 26)
        tilt = flat ? 0 : (distance < 0 ? turn : -turn)
        dip = min(away, 3) * 8
        glow = max(0, 1 - away)
    }
}
