import SwiftUI

/// Shared geometry for the main song feed so the hero grid and the first
/// `SongCardView` keep identical on-screen dimensions across every iPhone.
///
/// Previous iterations hard-coded per-device magic numbers (`nonArtReserve:
/// 180`, `padding(.bottom, 72)`, `UIScreen.main.bounds`) which only looked
/// centered on a narrow band of devices. This helper derives everything
/// from the live page size so SE through Pro Max all center cleanly.
enum FeedLayout {
    struct DiscoveryArtFrame {
        let side: CGFloat
        let top: CGFloat

        var centerY: CGFloat { top + side / 2 }
        var bottom: CGFloat { top + side }
    }

    /// Horizontal breathing room on both sides of the album art.
    static let horizontalInset: CGFloat = 24

    /// Vertical cushion reserved between the artwork and its surrounding
    /// non-art content. Kept here so hero and card layouts agree.
    static let artVerticalCushion: CGFloat = 40

    /// Floor so artwork never collapses below a usable size on very short
    /// viewports (e.g. iPhone SE with a lot of dynamic-type chrome).
    static let minArtSide: CGFloat = 180

    /// Fixed height reserved at the bottom of the feed ScrollView for the
    /// reply pill. Matches the pill's normal-state height (TextField 1
    /// line + 12pt vertical padding = 46pt) + `restingBottom` (8pt) with
    /// a small buffer so paging math is stable across devices without
    /// a measurement round-trip. The pill itself is allowed to overflow
    /// this slot when the TextField grows to multiple lines — that's
    /// intentional, matching iMessage/Instagram composer behavior.
    static let replyBarReservedHeight: CGFloat = 64

    /// Discovery reserves this lane below the pager content for the reply
    /// composer. Keeping it outside the page's art/control math prevents
    /// the keyboard or composer from re-centering the card. When no
    /// reply bar is showing (e.g. the hero), the lane is intentionally
    /// empty space — the layout above it does not reflow.
    static let discoveryReplyLaneHeight: CGFloat = 96

    /// Compact non-art lanes around the fixed artwork frame. Used by both
    /// the hero grid and `SongCardView` so the artwork center is identical
    /// across every Discovery page.
    static let discoveryHeaderLaneHeight: CGFloat = 96
    static let discoveryControlsLaneHeight: CGFloat = 108

    /// Computes the artwork side length for a given page size, leaving
    /// `nonArtHeight` of vertical room for the surrounding non-art
    /// content (header, sender row, player controls — or, on the hero
    /// page, the search CTA + history chevron).
    ///
    /// Picks the smaller of the width-bounded side and the height-bounded
    /// side so the square always fits, then clamps to `minArtSide` so
    /// extremely short viewports don't produce a degenerate thumbnail.
    static func artSize(forPageSize size: CGSize, nonArtHeight: CGFloat) -> CGFloat {
        let byWidth = max(0, size.width - horizontalInset * 2)
        let byHeight = max(minArtSide, size.height - nonArtHeight - artVerticalCushion)
        return min(byWidth, byHeight)
    }

    /// Shared anchor for the Discovery hero grid and history card artwork.
    /// The art itself stays fixed; titles, metadata, controls, and reply
    /// chrome flex around this frame so vertical paging doesn't feel like
    /// each card has a different center of gravity.
    ///
    /// The artwork top is anchored deterministically to the header lane
    /// so every Discovery page (hero + every `SongCardView`) places its
    /// art at the same y — no device-dependent fractions, no magic
    /// offsets to keep in sync across files.
    static func discoveryArtFrame(forPageSize size: CGSize) -> DiscoveryArtFrame {
        let availableForArt = size.height
            - discoveryHeaderLaneHeight
            - discoveryControlsLaneHeight
            - artVerticalCushion
        let byWidth = max(0, size.width - horizontalInset * 2)
        let byHeight = max(minArtSide, availableForArt)
        let side = min(byWidth, byHeight)
        return DiscoveryArtFrame(side: side, top: discoveryHeaderLaneHeight)
    }
}
