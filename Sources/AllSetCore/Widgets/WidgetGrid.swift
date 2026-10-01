import CoreGraphics

/// The desktop's widget slots: squares the size of a small widget, `spacing`
/// apart, centered in the screen's visible area. Every widget size spans whole
/// cells (medium 2×1, large 2×2, extra large 4×2), so widgets placed here line
/// up with each other and never overlap. Works in the coordinates
/// `WidgetInstance.offset` uses (layout points, origin top-left, y down).
public struct WidgetGrid: Equatable, Sendable {
    public struct Cell: Hashable, Sendable {
        public var column: Int
        public var row: Int
        public init(column: Int, row: Int) {
            self.column = column
            self.row = row
        }
    }

    /// From one cell's top-left to the next.
    public static let pitch = WidgetSize.small.dimensions.width + WidgetLayout.spacing

    public let columns: Int
    public let rows: Int
    /// Top-left of the first cell.
    public let origin: CGPoint

    /// `margin` is the least room left at each edge, in layout points: pass
    /// the screen margin divided by the widget size, so a grid at any size
    /// keeps the same margin on screen as `WidgetLayout.fitted` does.
    public init(bounds: CGSize, margin: CGFloat = WidgetLayout.margin) {
        let spacing = WidgetLayout.spacing
        let usable = CGSize(width: bounds.width - 2 * margin + spacing,
                            height: bounds.height - 2 * margin + spacing)
        // A hair of tolerance: a theme fitted edge to edge fills it exactly.
        columns = max(Int((usable.width / Self.pitch + 0.001).rounded(.down)), 1)
        rows = max(Int((usable.height / Self.pitch + 0.001).rounded(.down)), 1)
        let width = CGFloat(columns) * Self.pitch - spacing
        let height = CGFloat(rows) * Self.pitch - spacing
        origin = CGPoint(x: max(((bounds.width - width) / 2).rounded(), 0),
                         y: max(((bounds.height - height) / 2).rounded(), 0))
    }

    /// How many cells a size covers across and down.
    public static func span(of size: WidgetSize) -> (columns: Int, rows: Int) {
        let dimensions = size.dimensions
        return (max(Int(((dimensions.width + WidgetLayout.spacing) / pitch).rounded()), 1),
                max(Int(((dimensions.height + WidgetLayout.spacing) / pitch).rounded()), 1))
    }

    public func fits(_ size: WidgetSize) -> Bool {
        let span = Self.span(of: size)
        return span.columns <= columns && span.rows <= rows
    }

    public func offset(of cell: Cell) -> CGPoint {
        CGPoint(x: origin.x + CGFloat(cell.column) * Self.pitch, y: origin.y + CGFloat(cell.row) * Self.pitch)
    }

    /// The cell whose top-left is closest to `offset`, kept so a widget of
    /// `size` starting there stays on the grid. Nil when the size is larger
    /// than the whole grid.
    public func nearestCell(to offset: CGPoint, size: WidgetSize) -> Cell? {
        guard fits(size) else { return nil }
        let span = Self.span(of: size)
        let column = Int(((offset.x - origin.x) / Self.pitch).rounded())
        let row = Int(((offset.y - origin.y) / Self.pitch).rounded())
        return Cell(column: min(max(column, 0), columns - span.columns), row: min(max(row, 0), rows - span.rows))
    }

    /// The free spot nearest to `offset` for a widget of `size`, clear of
    /// every rect in `occupied`. Nil when nothing is free.
    public func place(_ size: WidgetSize, near offset: CGPoint, avoiding occupied: [CGRect]) -> CGPoint? {
        var taken = Occupancy(self)
        occupied.forEach { taken.mark($0) }
        return taken.nearestFree(size, to: offset).map(offset(of:))
    }

    /// The first free spot, filling columns from the left as macOS does
    /// (desktop icons live top right). Nil when nothing is free.
    public func firstFree(_ size: WidgetSize, avoiding occupied: [CGRect]) -> CGPoint? {
        guard fits(size) else { return nil }
        var taken = Occupancy(self)
        occupied.forEach { taken.mark($0) }
        let span = Self.span(of: size)
        for column in 0...(columns - span.columns) {
            for row in 0...(rows - span.rows) {
                let cell = Cell(column: column, row: row)
                if taken.isFree(cell, span: span) { return offset(of: cell) }
            }
        }
        return nil
    }

    /// The widgets tidied onto the grid: each moves to the free cell nearest
    /// where it is, the whole group first shifted onto the grid so an
    /// arrangement already built from cells (a theme's) keeps its shape.
    /// Larger widgets choose first. A widget with no free cell left stays
    /// where it is, inside the screen. Running it again changes nothing.
    public func arranged(_ widgets: [WidgetInstance]) -> [WidgetInstance] {
        guard let first = widgets.first else { return widgets }
        let box = widgets.dropFirst().reduce(CGRect(origin: first.offset, size: first.size.dimensions)) {
            $0.union(CGRect(origin: $1.offset, size: $1.size.dimensions))
        }
        let shift = CGPoint(x: ((box.minX - origin.x) / Self.pitch).rounded() * Self.pitch + origin.x - box.minX,
                            y: ((box.minY - origin.y) / Self.pitch).rounded() * Self.pitch + origin.y - box.minY)
        let order = widgets.indices.sorted { a, b in
            let areaA = widgets[a].size.dimensions.width * widgets[a].size.dimensions.height
            let areaB = widgets[b].size.dimensions.width * widgets[b].size.dimensions.height
            if areaA != areaB { return areaA > areaB }
            if widgets[a].offset.y != widgets[b].offset.y { return widgets[a].offset.y < widgets[b].offset.y }
            return widgets[a].offset.x < widgets[b].offset.x
        }
        var taken = Occupancy(self)
        var result = widgets
        let bounds = CGSize(width: CGFloat(columns) * Self.pitch - WidgetLayout.spacing + 2 * origin.x,
                            height: CGFloat(rows) * Self.pitch - WidgetLayout.spacing + 2 * origin.y)
        for index in order {
            let widget = widgets[index]
            let wanted = CGPoint(x: widget.offset.x + shift.x, y: widget.offset.y + shift.y)
            if let cell = taken.nearestFree(widget.size, to: wanted) {
                taken.claim(cell, span: Self.span(of: widget.size))
                result[index].offset = offset(of: cell)
            } else {
                result[index].offset = WidgetLayout.clamp(widget.offset, size: widget.size.dimensions, within: bounds)
            }
        }
        return result
    }

    /// Which cells are taken.
    private struct Occupancy {
        let grid: WidgetGrid
        var taken: Set<Cell> = []

        init(_ grid: WidgetGrid) {
            self.grid = grid
        }

        /// Marks every cell a rect reaches into, gaps included, so a widget
        /// off the grid still keeps others clear of it.
        mutating func mark(_ rect: CGRect) {
            let inner = rect.insetBy(dx: 1, dy: 1)
            guard !inner.isNull, !inner.isEmpty else { return }
            let half = WidgetLayout.spacing / 2
            for column in 0..<grid.columns {
                for row in 0..<grid.rows {
                    let cell = Cell(column: column, row: row)
                    let corner = grid.offset(of: cell)
                    let square = CGRect(x: corner.x - half, y: corner.y - half, width: WidgetGrid.pitch, height: WidgetGrid.pitch)
                    if square.intersects(inner) { taken.insert(cell) }
                }
            }
        }

        mutating func claim(_ cell: Cell, span: (columns: Int, rows: Int)) {
            for column in cell.column..<(cell.column + span.columns) {
                for row in cell.row..<(cell.row + span.rows) {
                    taken.insert(Cell(column: column, row: row))
                }
            }
        }

        func isFree(_ cell: Cell, span: (columns: Int, rows: Int)) -> Bool {
            for column in cell.column..<(cell.column + span.columns) {
                for row in cell.row..<(cell.row + span.rows) where taken.contains(Cell(column: column, row: row)) {
                    return false
                }
            }
            return true
        }

        func nearestFree(_ size: WidgetSize, to offset: CGPoint) -> Cell? {
            guard grid.fits(size) else { return nil }
            let span = WidgetGrid.span(of: size)
            var best: (cell: Cell, distance: CGFloat)?
            for row in 0...(grid.rows - span.rows) {
                for column in 0...(grid.columns - span.columns) {
                    let cell = Cell(column: column, row: row)
                    guard isFree(cell, span: span) else { continue }
                    let corner = grid.offset(of: cell)
                    let distance = (corner.x - offset.x) * (corner.x - offset.x) + (corner.y - offset.y) * (corner.y - offset.y)
                    if let current = best, distance >= current.distance - 0.5 { continue }
                    best = (cell, distance)
                }
            }
            return best?.cell
        }
    }
}
