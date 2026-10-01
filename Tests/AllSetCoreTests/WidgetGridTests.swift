import CoreGraphics
import Foundation
import Testing
@testable import AllSetCore

@Suite struct WidgetGridTests {
    /// This Mac's visible desktop at widget size 1: 1470 × 923 points.
    private let airBounds = CGSize(width: 1470, height: 923)

    private func frames(_ widgets: [WidgetInstance]) -> [CGRect] {
        widgets.map { CGRect(origin: $0.offset, size: $0.size.dimensions) }
    }

    private func expectNoOverlaps(_ widgets: [WidgetInstance], sourceLocation: SourceLocation = #_sourceLocation) {
        let rects = frames(widgets)
        for (index, rect) in rects.enumerated() {
            for other in rects[(index + 1)...] {
                #expect(!rect.intersects(other.insetBy(dx: 1, dy: 1)), sourceLocation: sourceLocation)
            }
        }
    }

    private func expectOnGrid(_ widgets: [WidgetInstance], _ grid: WidgetGrid, sourceLocation: SourceLocation = #_sourceLocation) {
        for widget in widgets {
            let column = (widget.offset.x - grid.origin.x) / WidgetGrid.pitch
            let row = (widget.offset.y - grid.origin.y) / WidgetGrid.pitch
            #expect(column == column.rounded() && row == row.rounded(), sourceLocation: sourceLocation)
            let span = WidgetGrid.span(of: widget.size)
            #expect(Int(column) >= 0 && Int(column) + span.columns <= grid.columns, sourceLocation: sourceLocation)
            #expect(Int(row) >= 0 && Int(row) + span.rows <= grid.rows, sourceLocation: sourceLocation)
        }
    }

    @Test func gridFitsTheScreenAndIsCentered() {
        let grid = WidgetGrid(bounds: airBounds)
        #expect(grid.columns == 7 && grid.rows == 4)
        let width = CGFloat(grid.columns) * WidgetGrid.pitch - WidgetLayout.spacing
        #expect(abs(grid.origin.x - (airBounds.width - width) / 2) <= 0.5)
        #expect(grid.origin.x >= WidgetLayout.margin && grid.origin.y >= WidgetLayout.margin)
        // Bigger widgets mean fewer, larger slots.
        let larger = WidgetGrid(bounds: CGSize(width: airBounds.width / 1.4, height: airBounds.height / 1.4))
        #expect(larger.columns == 5 && larger.rows == 3)
    }

    @Test func everySizeSpansWholeCells() {
        #expect(WidgetGrid.span(of: .small) == (1, 1))
        #expect(WidgetGrid.span(of: .medium) == (2, 1))
        #expect(WidgetGrid.span(of: .large) == (2, 2))
        #expect(WidgetGrid.span(of: .extraLarge) == (4, 2))
    }

    @Test func aDropLandsInTheNearestFreeSlot() {
        let grid = WidgetGrid(bounds: airBounds)
        let first = grid.offset(of: .init(column: 0, row: 0))
        // Dropped right on top of a widget already there: the next slot over.
        let taken = CGRect(origin: first, size: WidgetSize.small.dimensions)
        let spot = grid.place(.small, near: CGPoint(x: first.x + 10, y: first.y + 5), avoiding: [taken])
        #expect(spot == grid.offset(of: .init(column: 0, row: 1)) || spot == grid.offset(of: .init(column: 1, row: 0)))
        // Dropped past the edge: kept on the screen.
        let edge = grid.place(.medium, near: CGPoint(x: 5000, y: -300), avoiding: [])
        #expect(edge == grid.offset(of: .init(column: grid.columns - 2, row: 0)))
        // A full grid has no slot.
        let everything = CGRect(x: 0, y: 0, width: airBounds.width, height: airBounds.height)
        #expect(grid.place(.small, near: .zero, avoiding: [everything]) == nil)
    }

    @Test func newWidgetsFillColumnsFromTheLeft() {
        let grid = WidgetGrid(bounds: airBounds)
        let first = grid.firstFree(.small, avoiding: [])
        #expect(first == grid.offset(of: .init(column: 0, row: 0)))
        let taken = CGRect(origin: first!, size: WidgetSize.small.dimensions)
        #expect(grid.firstFree(.small, avoiding: [taken]) == grid.offset(of: .init(column: 0, row: 1)))
    }

    @Test func cleanUpRemovesOverlapsAndLinesEverythingUp() {
        let grid = WidgetGrid(bounds: airBounds)
        // Strewn about, several on top of one another, one half off screen.
        let strewn: [WidgetInstance] = [
            WidgetInstance(kind: .clock, size: .medium, offset: CGPoint(x: 40, y: 31)),
            WidgetInstance(kind: .calendar, size: .small, offset: CGPoint(x: 60, y: 50)),
            WidgetInstance(kind: .system, size: .small, offset: CGPoint(x: 75, y: 60)),
            WidgetInstance(kind: .weather, size: .large, offset: CGPoint(x: 600, y: 200)),
            WidgetInstance(kind: .photo, size: .large, offset: CGPoint(x: 650, y: 230)),
            WidgetInstance(kind: .quote, size: .medium, offset: CGPoint(x: 1400, y: 880)),
        ]
        let tidy = grid.arranged(strewn)
        #expect(tidy.map(\.id) == strewn.map(\.id))
        expectNoOverlaps(tidy)
        expectOnGrid(tidy, grid)
        // A tidy desktop stays exactly as it is.
        #expect(frames(grid.arranged(tidy)) == frames(tidy))
    }

    @Test func cleanUpKeepsAThemesShape() {
        for set in ThemeLibrary.all {
            let layout = set.widgets(screenName: nil, bounds: CGSize(width: 10_000, height: 10_000))
            let fitted = WidgetLayout.fitted(layout, in: airBounds, range: 0.7...1.6)
            let bounds = CGSize(width: airBounds.width / fitted.scale, height: airBounds.height / fitted.scale)
            let themeGrid = WidgetGrid(bounds: bounds, margin: WidgetLayout.margin / fitted.scale)
            let tidy = themeGrid.arranged(fitted.widgets)
            expectNoOverlaps(tidy)
            // Every widget moved by the same amount: the composition is intact.
            let shifts = Set(zip(fitted.widgets, tidy).map {
                "\((($1.offset.x - $0.offset.x) * 10).rounded()),\((($1.offset.y - $0.offset.y) * 10).rounded())"
            })
            #expect(shifts.count == 1, "\(set.id) lost its shape")
        }
    }

    @Test func aGrownWidgetPushesNeighboursAside() {
        let grid = WidgetGrid(bounds: airBounds)
        let a = grid.offset(of: .init(column: 0, row: 0))
        let b = grid.offset(of: .init(column: 1, row: 0))
        var widgets = [
            WidgetInstance(kind: .clock, size: .small, offset: a),
            WidgetInstance(kind: .calendar, size: .small, offset: b),
        ]
        widgets[0].size = .large
        let tidy = grid.arranged(widgets)
        #expect(tidy[0].offset == a)
        expectNoOverlaps(tidy)
        expectOnGrid(tidy, grid)
    }
}
