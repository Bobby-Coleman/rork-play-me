import SwiftUI
import Nuke

/// Square-contained ambient album-art grid used on the Discovery hero page.
/// Renders three columns of tiles scrolling slowly upward, with the middle
/// column shifted half a row to create the staggered masonry look in the
/// target mockup. The entire grid is clipped to a rounded square matching
/// the shared card container styling.
///
/// Design goals, all enforced by this implementation:
///   * No full-screen bleed — parent sets `side` explicitly and we never
///     exceed that bound.
///   * Zero per-frame state updates. `TimelineView.animation` rebuilds the
///     body cheaply; the scroll effect is purely `.offset(y:)` on each
///     column, which SwiftUI translates to a GPU transform.
///   * Stable tile identity per *slot* rather than per virtual row. Slots
///     rebind their URL only when the column advances a whole tile, so Nuke
///     sees the same `LazyImage` coming back with a new URL and reuses the
///     decoded bitmap from its memory cache — no flash.
///   * `ImagePrefetcher` warms every URL in the dataset on appear, so by
///     the time a slot rebinds to a new tile the image is already resident.
///   * No `GeometryReader` per cell. Tile size is derived once from `side`
///     and passed down as a constant.
struct AlbumArtGridBackgroundView: View {
    let items: [GridSong]
    /// Square side length the grid renders into. Caller is responsible for
    /// sizing this to match the adjacent song-card styling (e.g.
    /// `UIScreen.main.bounds.width - 48`).
    let side: CGFloat

    /// Points per second the grid drifts upward. Slow enough to feel
    /// ambient, fast enough to be visible inside a second or two.
    var scrollSpeed: CGFloat = 14
    /// Spacing between columns and between tiles within a column.
    var spacing: CGFloat = 8
    /// Corner radius of the outer square mask.
    var outerCornerRadius: CGFloat = 20
    /// Corner radius of each individual tile.
    var tileCornerRadius: CGFloat = 10
    /// Opacity of the black wash applied over the grid so the foreground
    /// CTA remains legible.
    var dimOpacity: CGFloat = 0.35

    @State private var prefetcher: ImagePrefetcher? = nil

    private var columnCount: Int { 3 }

    /// Square tile side derived from the container size. Fixed for the life
    /// of the view so no cell needs a GeometryReader.
    private var tileSize: CGFloat {
        max(24, (side - spacing * CGFloat(columnCount - 1)) / CGFloat(columnCount))
    }

    private var rowHeight: CGFloat { tileSize + spacing }

    /// Number of virtual slots per column. Must be at least enough to cover
    /// `side + 1 row` of viewport so the wrap point is never visible. A few
    /// extra rows above/below give the image pipeline time to decode.
    private var slotsPerColumn: Int {
        max(6, Int(ceil(side / rowHeight)) + 4)
    }

    private var displayItems: [GridSong] {
        items.isEmpty ? MockSongGridProvider.samples : items
    }

    var body: some View {
        ZStack {
            Color.black

            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { timeline in
                let elapsed = timeline.date.timeIntervalSinceReferenceDate
                let baseY = CGFloat(elapsed) * scrollSpeed

                HStack(alignment: .top, spacing: spacing) {
                    ForEach(0..<columnCount, id: \.self) { col in
                        column(
                            column: col,
                            // Middle column (col == 1) is pre-shifted so the
                            // staggered masonry look is preserved independent
                            // of current scroll time.
                            startOffset: (col == 1) ? rowHeight / 2 : 0,
                            baseY: baseY
                        )
                    }
                }
            }

            Color.black.opacity(dimOpacity)
                .allowsHitTesting(false)
        }
        .frame(width: side, height: side)
        .clipShape(.rect(cornerRadius: outerCornerRadius))
        .allowsHitTesting(false)
        .onAppear { startPrefetch() }
        .onChange(of: items.map(\.albumArtURL)) { _, _ in
            startPrefetch()
        }
        .onDisappear {
            prefetcher?.stopPrefetching()
            prefetcher = nil
        }
    }

    /// Builds one column of tiles. Each tile lives at a stable screen slot
    /// and its backing `items` index advances discretely as the column
    /// scrolls, so we bind a new URL to the same view at most once per row
    /// of travel.
    private func column(column col: Int, startOffset: CGFloat, baseY: CGFloat) -> some View {
        let tile = tileSize
        let h = rowHeight
        let slots = slotsPerColumn
        let count = displayItems.count

        // Virtual row of the topmost slot in this column.
        let firstVirtualRow = Int(floor((baseY - startOffset) / h)) - 1
        // Column phase shift so each column starts on a different item,
        // which avoids horizontal bands of identical covers.
        let columnPhase = col * 7

        return ZStack(alignment: .top) {
            ForEach(0..<slots, id: \.self) { slot in
                let virtualIdx = firstVirtualRow + slot
                let wrappedItemIdx = ((virtualIdx + columnPhase) % count + count) % count
                let item = displayItems[wrappedItemIdx]
                let y = CGFloat(virtualIdx) * h + startOffset - baseY

                AlbumArtSquare(
                    url: item.albumArtURL,
                    cornerRadius: tileCornerRadius,
                    showsPlaceholderProgress: false,
                    showsShadow: false,
                    targetDecodeSide: tile
                )
                .frame(width: tile, height: tile)
                .offset(y: y)
            }
        }
        .frame(width: tile, height: side, alignment: .top)
    }

    // MARK: - Prefetching

    /// Kicks off (or restarts) a prefetch pass for every URL in the current
    /// dataset. Nuke will decode each image into the shared memory cache so
    /// the grid never waits on network during scroll.
    private func startPrefetch() {
        prefetcher?.stopPrefetching()
        let requests = displayItems.compactMap { song -> ImageRequest? in
            guard let url = URL(string: song.albumArtURL) else { return nil }
            let pixelSide = tileSize * UIScreen.main.scale
            return ImageRequest(
                url: url,
                processors: [.resize(size: CGSize(width: pixelSide, height: pixelSide), contentMode: .aspectFill)],
                priority: .low
            )
        }
        let p = ImagePrefetcher(pipeline: .shared, destination: .memoryCache, maxConcurrentRequestCount: 4)
        p.startPrefetching(with: requests)
        prefetcher = p
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        AlbumArtGridBackgroundView(items: MockSongGridProvider.samples, side: 320)
    }
}
