import CoreGraphics
import Foundation
import Testing
@testable import AllSetCore

@Suite struct ThemeCarouselLayoutTests {
    /// The page below the navigation (137 pt) in the app's smallest window,
    /// its default, a laptop's full screen and a large display.
    private static let viewports = [CGSize(width: 900, height: 463), CGSize(width: 1120, height: 623),
                                    CGSize(width: 1280, height: 663), CGSize(width: 1470, height: 819),
                                    CGSize(width: 1728, height: 943)]
    /// Under the cards: the gap, the category rail and the panel's padding.
    private static let footer: CGFloat = 62

    private static func layout(_ viewport: CGSize) -> ThemeCarouselLayout {
        ThemeCarouselLayout(viewport: viewport, margin: viewport.width < 1000 ? 24 : 32, chrome: 102, footer: footer)
    }

    /// Half of what a card `steps` from the center looks as wide as.
    private static func halfWidth(_ layout: ThemeCarouselLayout, _ steps: Int, flat: Bool = false) -> CGFloat {
        let depth = ThemeCarouselDepth(distance: CGFloat(steps), flat: flat)
        return layout.cardSize.width * depth.scale / 2 * cos(depth.tilt * .pi / 180)
    }

    @Test func heroGrowsWithTheWindowAndLeavesRoomBelow() {
        let layouts = Self.viewports.map(Self.layout)
        for (smaller, larger) in zip(layouts, layouts.dropFirst()) {
            #expect(larger.panelSize.height >= smaller.panelSize.height)
            #expect(larger.cardSize.height >= smaller.cardSize.height)
        }
        for (viewport, layout) in zip(Self.viewports, layouts) {
            #expect((350...640).contains(layout.panelSize.height))
            // The first rail's title still shows under the panel.
            #expect(viewport.height - layout.panelSize.height >= 100)
        }
    }

    @Test func cardsArePortraitAndFillThePanelAboveTheRail() {
        for width in stride(from: CGFloat(900), through: 2600, by: 85) {
            for height in stride(from: CGFloat(463), through: 1400, by: 47) {
                let layout = Self.layout(CGSize(width: width, height: height))
                #expect(abs(layout.cardSize.width / layout.cardSize.height - 0.75) < 0.0001, "\(width)x\(height)")
                // 85 to 90% of the panel's height above the category rail.
                let share = layout.cardSize.height / (layout.panelSize.height - Self.footer)
                #expect((0.85...0.9001).contains(share), "\(width)x\(height): \(share)")
                // Never past the panel's padding and the room side cards sink into.
                #expect(layout.cardSize.height <= layout.panelSize.height - 102 + 0.0001)
            }
        }
    }

    @Test func everyCardTucksBehindTheOneInFrontOfIt() {
        for viewport in Self.viewports {
            let layout = Self.layout(viewport)
            for flat in [false, true] {
                #expect(layout.offset(at: 0, flat: flat) == 0)
                for steps in 0..<3 {
                    let inner = layout.offset(at: CGFloat(steps + 1), flat: flat) - Self.halfWidth(layout, steps + 1, flat: flat)
                    let edge = layout.offset(at: CGFloat(steps), flat: flat) + Self.halfWidth(layout, steps, flat: flat)
                    // The same sliver of each card is hidden, turned or flat.
                    #expect(abs((edge - inner) - ThemeCarouselLayout.tuck) < 0.0001, "\(viewport) card \(steps + 1)")
                    // And it stops short of the label, 16 pt in from the edge at the card's own scale.
                    #expect(ThemeCarouselLayout.tuck / ThemeCarouselDepth(distance: CGFloat(steps + 1)).scale <= 16)
                }
            }
        }
    }

    @Test func theRowIsTheSameOnBothSidesAndMovesSmoothly() {
        let layout = Self.layout(Self.viewports[2])
        #expect(layout.step() == layout.offset(at: 1))
        var last: CGFloat = 0
        for step in 1...80 {
            let distance = CGFloat(step) / 20
            let along = layout.offset(at: distance)
            #expect(along > last)
            #expect(along - last < layout.cardSize.width * 0.06)
            #expect(layout.offset(at: -distance) == -along)
            last = along
        }
    }

    @Test func aWideWindowShowsThreeNeighboursASide() {
        /// How much of the card `steps` from the center is inside the panel (0...1).
        func showing(_ layout: ThemeCarouselLayout, _ steps: Int) -> CGFloat {
            let half = Self.halfWidth(layout, steps)
            let inner = layout.offset(at: CGFloat(steps)) - half
            return min(max((layout.panelSize.width / 2 - inner) / (half * 2), 0), 1)
        }
        // A large window: two neighbours whole, the third cut by the panel's edge.
        let wide = Self.layout(Self.viewports[4])
        #expect(showing(wide, 1) == 1)
        #expect(showing(wide, 2) == 1)
        #expect((0.2..<1).contains(showing(wide, 3)))
        // A laptop window: the outer pair cut by the panel, as in the reference.
        let laptop = Self.layout(CGSize(width: 1400, height: 763))
        #expect(showing(laptop, 1) == 1)
        #expect((0.5..<1).contains(showing(laptop, 2)))
        // A narrow, tall one: the selected card and parts of its neighbours.
        let narrow = Self.layout(CGSize(width: 900, height: 900))
        #expect((0.3..<1).contains(showing(narrow, 1)))
        #expect(showing(narrow, 3) == 0)
    }

    @Test func depthFollowsDistanceFromTheCenter() {
        let center = ThemeCarouselDepth(distance: 0)
        #expect(center.scale == 1)
        #expect(center.dim == 0)
        #expect(center.opacity == 1)
        #expect(center.tilt == 0)
        #expect(center.dip == 0)
        #expect(center.glow == 1)

        let neighbour = ThemeCarouselDepth(distance: 1), outer = ThemeCarouselDepth(distance: 2)
        #expect(abs(neighbour.scale - 0.85) < 0.0001)
        #expect(abs(outer.scale - 0.7) < 0.0001)
        // Darkened as a see-through card at 0.8 and 0.5 would look, but solid.
        #expect(abs(neighbour.dim - 0.2) < 0.0001)
        #expect(abs(outer.dim - 0.5) < 0.0001)
        #expect(neighbour.opacity == 1)
        #expect(outer.opacity == 1)
        #expect(neighbour.tilt == -14)
        #expect(outer.tilt == -20)
        #expect(neighbour.glow == 0)
        #expect(neighbour.dip > 0)
        #expect(outer.dip > neighbour.dip)
        // Cards turn toward the center from either side.
        #expect(ThemeCarouselDepth(distance: -1).tilt == 14)
        #expect(ThemeCarouselDepth(distance: -1).scale == neighbour.scale)

        // Three a side at most, and nothing pops: everything changes smoothly.
        #expect(ThemeCarouselDepth(distance: 3).opacity == 1)
        #expect(ThemeCarouselDepth(distance: 3.5).opacity == 0)
        #expect(ThemeCarouselDepth(distance: 5).opacity == 0)
        var last = center
        for step in 1...80 {
            let depth = ThemeCarouselDepth(distance: CGFloat(step) / 20)
            #expect(depth.scale <= last.scale)
            #expect(depth.opacity <= last.opacity)
            #expect(depth.dip >= last.dip)
            #expect(depth.dim >= last.dim)
            let fade: CGFloat = abs(depth.opacity - last.opacity), shade: CGFloat = abs(depth.dim - last.dim)
            let turn: CGFloat = abs(depth.tilt - last.tilt), shrink: CGFloat = abs(depth.scale - last.scale)
            #expect(fade <= 0.1000001)
            #expect(shade <= 0.05)
            #expect(turn <= 1)
            #expect(shrink <= 0.01)
            last = depth
        }
    }

    @Test func aShortRowShowsFewerNeighbours() {
        // With three themes, one neighbour a side: a second would be the first again.
        #expect(ThemeCarouselDepth(distance: 1, reach: 1).opacity == 1)
        #expect(ThemeCarouselDepth(distance: 1.25, reach: 1).opacity == 0.5)
        #expect(ThemeCarouselDepth(distance: 2, reach: 1).opacity == 0)
    }

    @Test func reduceMotionFlattensTheRowAndNothingElse() {
        for distance in [CGFloat(-2), -0.4, 0, 1, 1.7, 3] {
            let turned = ThemeCarouselDepth(distance: distance), flat = ThemeCarouselDepth(distance: distance, flat: true)
            #expect(flat.tilt == 0)
            #expect(flat.scale == turned.scale)
            #expect(flat.opacity == turned.opacity)
            #expect(flat.dim == turned.dim)
            #expect(flat.dip == turned.dip)
            #expect(flat.glow == turned.glow)
        }
    }
}

@Suite struct ThemeCardArtTests {
    private typealias Widget = (kind: WidgetKind, size: WidgetSize)

    private static let football: [Widget] = [
        (.jersey, .large), (.wordArt, .medium), (.clock, .small), (.photo, .small), (.playerCard, .large), (.milestone, .medium),
        (.scoreboard, .medium), (.photo, .medium), (.quote, .medium), (.focus, .medium), (.calendar, .small), (.photo, .small),
    ]

    private static func frame(_ piece: ThemeCardArt.Piece, _ widgets: [Widget]) -> CGRect {
        let size = widgets[piece.widget].size.dimensions
        return CGRect(x: piece.origin.x, y: piece.origin.y, width: size.width * piece.scale, height: size.height * piece.scale)
    }

    @Test func theCanvasIsTheCardsShape() {
        #expect(ThemeCardArt.canvas.width / ThemeCardArt.canvas.height == ThemeCarouselLayout.cardAspect)
    }

    @Test func picksTheWordTheFirstLargeWidgetAndSmallOnesOfDifferentKinds() throws {
        let picks = try #require(ThemeCardArt.picks(from: Self.football))
        #expect(picks.title == 1)
        #expect(picks.hero == 0)
        // A clock, a photo and a calendar before the second photo.
        #expect(picks.flankers == [2, 3, 10, 11])
    }

    @Test func makesDoWithWhatAThemeHas() throws {
        // No word art, nothing large: the first medium leads.
        let quiet: [Widget] = [(.photo, .small), (.nowPlaying, .medium), (.battery, .small), (.photo, .medium)]
        let picks = try #require(ThemeCardArt.picks(from: quiet))
        #expect(picks.title == nil)
        #expect(picks.hero == 1)
        #expect(picks.flankers == [0, 2])
        // One widget is still a card; none isn't.
        #expect(ThemeCardArt.picks(from: [(.wordArt, .medium)])?.hero == 0)
        #expect(ThemeCardArt.picks(from: [(.wordArt, .medium)])?.title == nil)
        #expect(ThemeCardArt.picks(from: []) == nil)
    }

    @Test func piecesSitInTheUpperPartWithoutCoveringEachOther() throws {
        for widgets in [Self.football, Array(Self.football.dropFirst(2))] {
            let picks = try #require(ThemeCardArt.picks(from: widgets))
            let pieces = ThemeCardArt.pieces(picks, sizes: widgets.map(\.size))
            let expected: Int = picks.flankers.count + (picks.title == nil ? 1 : 2)
            #expect(pieces.count == expected)
            let frames = pieces.map { Self.frame($0, widgets) }
            for frame in frames {
                #expect(CGRect(origin: .zero, size: ThemeCardArt.canvas).contains(frame))
                // The lower third is the wallpaper's, for the name and buttons.
                #expect(frame.maxY <= ThemeCardArt.canvas.height * 0.67)
            }
            for (index, frame) in frames.enumerated() {
                for other in frames.dropFirst(index + 1) { #expect(!frame.intersects(other)) }
            }
            // Back to front: the small ones, the hero, then the word above it.
            let hero = try #require(pieces.firstIndex { $0.widget == picks.hero })
            #expect(hero == picks.flankers.count)
            #expect(abs(frames[hero].midX - ThemeCardArt.canvas.width / 2) < 0.001)
            if let title = picks.title {
                #expect(pieces.last?.widget == title)
                #expect(frames[frames.count - 1].maxY <= frames[hero].minY)
            }
        }
    }

    @Test func picksPastTheEndOfTheLayoutAreLeftOut() {
        let pieces = ThemeCardArt.pieces(ThemeCardArt.Picks(hero: 0, title: 9, flankers: [1, 7]), sizes: [.large, .small])
        #expect(pieces.map(\.widget) == [1, 0])
    }

    @Test func handPickedCardsPointAtWidgetsTheirThemesHave() throws {
        for (id, picks) in ThemeCardArt.curated {
            let set = try #require(ThemeLibrary.set(id), "\(id)")
            let widgets = set.widgets(screenName: nil, bounds: CGSize(width: 1136, height: 768))
            var used: [Int] = [picks.hero] + picks.flankers
            if let title = picks.title { used.append(title) }
            for widget in used {
                #expect(widgets.indices.contains(widget), "\(id) has no widget \(widget)")
            }
            #expect(Set(used).count == used.count, "\(id) uses a widget twice")
        }
    }
}

@Suite struct ThemeAccentTests {
    private static func saturation(_ color: WidgetColor) -> Double {
        let brightest = max(color.red, color.green, color.blue)
        return brightest == 0 ? 0 : (brightest - min(color.red, color.green, color.blue)) / brightest
    }

    @Test func aLightChosenForTheThemeWins() throws {
        // Seven's look has a gold accent; its light is neon crimson over that gold.
        let seven = try #require(ThemeLibrary.set("setup.seven"))
        #expect(seven.accent?.primary == WidgetColor(hex: 0xFF2D4A))
        #expect(seven.lighting() == ThemeAccent(primary: WidgetColor(hex: 0xFF2D4A), secondary: WidgetColor(hex: 0xFFB347)))
        #expect(seven.setup?.accent == WidgetColor(hex: 0xE8C15A))
        // Whatever its wallpaper measures as.
        #expect(seven.lighting(wallpaper: WidgetColor(hex: 0x00FF00)) == seven.lighting())
    }

    @Test func everyLightChosenByHandIsForAThemeThatExists() {
        for id in ThemeLibrary.accents.keys {
            #expect(ThemeLibrary.set("setup.\(id)")?.accent != nil, "\(id)")
        }
        // The black-and-white themes that can lead the carousel each have one.
        for id in ["leopardNoir", "cityNoir", "angelic", "hypnotic", "afterDark"] {
            #expect(ThemeLibrary.accents[id] != nil, "\(id)")
        }
    }

    @Test func otherwiseTheLooksOwnAccentBrightEnoughToGlow() throws {
        // Deep crimson, lifted; its second accent is the same red, so the haze is that red paled.
        let crimson = try #require(ThemeLibrary.set("setup.crimsonNights"))
        #expect(crimson.accent == nil)
        let light = crimson.lighting()
        #expect(abs(max(light.primary.red, light.primary.green, light.primary.blue) - 0.94) < 0.001)
        #expect(light.primary.red > light.primary.blue && light.primary.blue > light.primary.green)
        #expect(light.secondary.green > light.primary.green)
        // Magenta with a cyan second accent: two colors, both kept.
        let neon = try #require(ThemeLibrary.set("setup.neonNights")).lighting()
        #expect(neon.primary.red > neon.primary.green)
        #expect(neon.secondary.blue > neon.secondary.red)
    }

    @Test func aLookWithNoColorFallsThroughToItsWallpaperThenGold() throws {
        // White on black and white: nothing in the look to light a panel with.
        let grunge = try #require(ThemeLibrary.set("setup.grunge"))
        #expect(grunge.accent == nil)
        #expect(grunge.lighting() == .neutral)
        // Its wallpaper's color, when that has one.
        let blue = grunge.lighting(wallpaper: WidgetColor(hex: 0x2255AA))
        #expect(blue.primary.blue > blue.primary.red)
        #expect(abs(blue.primary.blue - 0.94) < 0.001)
        // A gray wallpaper is no better than a white accent.
        #expect(grunge.lighting(wallpaper: WidgetColor(hex: 0x808080)) == .neutral)
        #expect(grunge.lighting(wallpaper: WidgetColor(hex: 0x050505)) == .neutral)
    }

    @Test func everyThemeIsLitInAColor() {
        for set in ThemeLibrary.all {
            let light = set.lighting()
            #expect(max(light.primary.red, light.primary.green, light.primary.blue) > 0.3, "\(set.id) is too dark to glow")
            #expect(Self.saturation(light.primary) >= 0.18, "\(set.id) would glow gray")
            #expect((0.6...1).contains(light.glowIntensity), "\(set.id)")
        }
    }

    @Test func brightThemesGlowLess() throws {
        let peach = try #require(ThemeLibrary.set("setup.peachFizz")), seven = try #require(ThemeLibrary.set("setup.seven"))
        #expect(peach.lighting().glowIntensity < seven.lighting().glowIntensity)
        // Out of range is brought back in.
        #expect(ThemeAccent(primary: .init(hex: 0xFF0000), secondary: .init(hex: 0xFF0000), glowIntensity: 0.1).glowIntensity == 0.6)
        // A light theme with no chosen light glows less than a dark one.
        let light = try #require(ThemeLibrary.all.first { $0.accent == nil && !$0.isDark })
        let dark = try #require(ThemeLibrary.all.first { $0.accent == nil && $0.isDark })
        #expect(light.lighting().glowIntensity < dark.lighting().glowIntensity)
    }
}
