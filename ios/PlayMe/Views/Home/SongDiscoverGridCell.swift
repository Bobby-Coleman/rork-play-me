import SwiftUI

/// Minimal square album-art tile for the left Discover/Home song feed.
/// Corners stay sharp to match the visual reference.
struct SongDiscoverGridCell: View {
    let song: Song
    let side: CGFloat

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            AlbumArtSquare(
                url: song.albumArtURL,
                cornerRadius: 0,
                showsPlaceholderProgress: false,
                showsShadow: false,
                targetDecodeSide: side
            )

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .clear, location: 0.72),
                    .init(color: .black.opacity(0.52), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
        }
        .aspectRatio(1, contentMode: .fit)
        .contentShape(Rectangle())
        .accessibilityLabel("\(song.title) by \(song.artist)")
    }
}
