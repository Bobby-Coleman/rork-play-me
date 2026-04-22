import SwiftUI
import NukeUI
import Nuke

/// Shared square album-art container used by `SongCardView`, the Discovery
/// grid, and any future surface that wants the same corner radius, aspect
/// ratio, placeholder treatment, and shadow.
///
/// Backed by `NukeUI.LazyImage` so:
///   * decoded bitmaps are served from the shared `ImageCache`
///   * disk cache absorbs app-launch churn
///   * concurrent requests for the same URL are coalesced
///   * re-binding the same URL never clears the previously displayed
///     image, which kills the slot-recycle flicker `AsyncImage` suffers
///     from in the Discovery grid.
struct AlbumArtSquare: View {
    let url: String?
    var cornerRadius: CGFloat = 16
    var showsPlaceholderProgress: Bool = true
    var showsShadow: Bool = true
    /// Optional target decoded size. Set this to the actual pixel side (pt
    /// * scale) when the square is small — e.g. grid tiles — so the
    /// pipeline downsamples rather than decoding a 1200x1200 jpeg.
    var targetDecodeSide: CGFloat? = nil

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let urlString = url, let parsed = URL(string: urlString) {
                    LazyImage(request: imageRequest(for: parsed)) { state in
                        if let image = state.image {
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } else if state.error != nil {
                            Color(.systemGray5)
                        } else {
                            Color(.systemGray6)
                                .overlay {
                                    if showsPlaceholderProgress {
                                        ProgressView().tint(.white)
                                    }
                                }
                        }
                    }
                    .pipeline(.shared)
                    .priority(.normal)
                    .allowsHitTesting(false)
                } else {
                    Color(.systemGray6)
                }
            }
            .clipShape(.rect(cornerRadius: cornerRadius))
            .shadow(color: showsShadow ? .white.opacity(0.05) : .clear, radius: 20, y: 10)
    }

    private func imageRequest(for url: URL) -> ImageRequest {
        if let side = targetDecodeSide, side > 0 {
            let pixelSide = side * UIScreen.main.scale
            return ImageRequest(
                url: url,
                processors: [.resize(size: CGSize(width: pixelSide, height: pixelSide), contentMode: .aspectFill)],
                priority: .normal
            )
        }
        return ImageRequest(url: url, priority: .normal)
    }
}
