import SwiftUI
import NukeUI
import Nuke

/// 2x2 mosaic of the first four song album-art URLs, with sensible
/// fallbacks for shorter mixtapes:
///   * 0 songs → tinted placeholder using the mixtape name's first
///     letter.
///   * 1 song  → 1-up cover (full square).
///   * 2 songs → vertical split.
///   * 3 songs → 1 large + 2 small (top-left big, right column split).
///   * 4+ songs → standard 2x2 grid.
///
/// Renders inside an `AlbumArtSquare`-shaped container (same corner
/// radius / shadow) so mixtape covers visually match song artwork in the
/// Pinterest grids.
struct MixtapeCoverView: View {
    let mixtape: Mixtape
    var cornerRadius: CGFloat = 16
    var showsShadow: Bool = true

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                let urls = mixtape.coverArtURLs
                switch urls.count {
                case 0:
                    placeholder
                case 1:
                    image(urls[0])
                case 2:
                    HStack(spacing: 0) {
                        image(urls[0]).clipped()
                        image(urls[1]).clipped()
                    }
                case 3:
                    HStack(spacing: 0) {
                        image(urls[0]).clipped()
                        VStack(spacing: 0) {
                            image(urls[1]).clipped()
                            image(urls[2]).clipped()
                        }
                    }
                default:
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            image(urls[0]).clipped()
                            image(urls[1]).clipped()
                        }
                        HStack(spacing: 0) {
                            image(urls[2]).clipped()
                            image(urls[3]).clipped()
                        }
                    }
                }
            }
            .clipShape(.rect(cornerRadius: cornerRadius))
            .overlay(alignment: .topLeading) {
                if mixtape.isSystemLiked {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.pink)
                        .padding(8)
                        .background(.ultraThinMaterial, in: Circle())
                        .padding(8)
                }
            }
            .shadow(color: showsShadow ? .white.opacity(0.05) : .clear, radius: 20, y: 10)
    }

    @ViewBuilder
    private func image(_ urlString: String) -> some View {
        if let url = URL(string: urlString) {
            LazyImage(url: url) { state in
                if let image = state.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    Color(.systemGray6)
                }
            }
            .pipeline(.shared)
        } else {
            Color(.systemGray6)
        }
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [Color(white: 0.12), Color(white: 0.06)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Text(String(mixtape.name.prefix(1)).uppercased())
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(.white.opacity(0.7))
        }
    }
}
