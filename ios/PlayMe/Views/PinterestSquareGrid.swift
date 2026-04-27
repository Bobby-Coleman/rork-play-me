import SwiftUI

/// Reusable Pinterest-style staggered grid of uniform 1:1 squares. Two
/// columns on iPhone widths; the right column gets a top inset of
/// `cellSize / 2` so consecutive items don't sit on the same horizontal
/// baseline — that's the Pinterest "offset" look. Every cell is the same
/// size, so this is NOT a variable-height masonry; it just shifts one
/// column.
///
/// Implementation notes:
/// * Items are split into `evens` (column 0) and `odds` (column 1) using
///   their absolute index. The split is deterministic, so appending more
///   items via `loadMore` never reflows the existing layout — new entries
///   just append to whichever column they belong to.
/// * Built on two parallel `LazyVStack`s inside an `HStack` rather than
///   `LazyVGrid` because `LazyVGrid` lays cells out row-by-row, which
///   makes the "right column offset" trick produce a visible gap above
///   the first row that toggles when items animate in. Two stacks lets
///   each column scroll its own lazy window cleanly.
/// * Cells delegate art rendering to `AlbumArtSquare` so corner radius
///   and shadow match the rest of the app.
struct PinterestSquareGrid<Item: Identifiable, Cell: View>: View {
    let items: [Item]
    /// Per-cell side length in points. Caller chooses based on the
    /// container width so the grid plays nicely with safe-area insets and
    /// custom margins.
    let cellSize: CGFloat
    /// Inter-cell spacing applied both horizontally and vertically.
    let spacing: CGFloat
    /// Renders one cell. Receives both the item and its cell side so the
    /// caller can pass the right `targetDecodeSide` to image pipelines.
    let cell: (Item, CGFloat) -> Cell

    init(
        items: [Item],
        cellSize: CGFloat,
        spacing: CGFloat = 10,
        @ViewBuilder cell: @escaping (Item, CGFloat) -> Cell
    ) {
        self.items = items
        self.cellSize = cellSize
        self.spacing = spacing
        self.cell = cell
    }

    private var leftColumn: [(offset: Int, item: Item)] {
        items.enumerated().compactMap { idx, item in
            idx.isMultiple(of: 2) ? (idx, item) : nil
        }
    }

    private var rightColumn: [(offset: Int, item: Item)] {
        items.enumerated().compactMap { idx, item in
            idx.isMultiple(of: 2) ? nil : (idx, item)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: spacing) {
            LazyVStack(spacing: spacing) {
                ForEach(leftColumn, id: \.item.id) { _, item in
                    cell(item, cellSize)
                        .frame(width: cellSize, height: cellSize)
                }
            }

            LazyVStack(spacing: spacing) {
                // Right column starts half a cell lower so paired rows
                // never align horizontally. Match Pinterest by leading
                // with a transparent spacer rather than a `.padding(.top)`
                // so cell hit-testing stays exact at the top of the
                // column.
                Color.clear
                    .frame(width: cellSize, height: cellSize / 2)
                ForEach(rightColumn, id: \.item.id) { _, item in
                    cell(item, cellSize)
                        .frame(width: cellSize, height: cellSize)
                }
            }
        }
    }
}

/// Computes a per-cell side length for a 2-column Pinterest grid given a
/// container width and the desired horizontal padding/spacing. Centralized
/// so call sites always use the same formula.
enum PinterestGridLayout {
    static let columns: Int = 2

    static func cellSize(
        containerWidth: CGFloat,
        horizontalPadding: CGFloat,
        spacing: CGFloat
    ) -> CGFloat {
        let usable = max(0, containerWidth - horizontalPadding * 2 - spacing)
        return floor(usable / CGFloat(columns))
    }
}
