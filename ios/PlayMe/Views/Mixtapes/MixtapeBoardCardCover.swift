import SwiftUI
import NukeUI
import Nuke

/// Pinterest-style board preview: **3:2** mosaic — wide hero on the left,
/// two **square** album tiles stacked on the right (`R = H/2` so each
/// small cell is `R × R`). Thin separators between panes.
struct MixtapeBoardCardCover: View {
    let mixtape: Mixtape
    var cornerRadius: CGFloat = 14

    private var mainCoverURL: String? {
        let u = mixtape.coverImageURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !u.isEmpty { return u }
        return nil
    }

    private var smallURLs: [String] {
        Array(mixtape.songs.prefix(2)).map(\.albumArtURL).filter { !$0.isEmpty }
    }

    var body: some View {
        GeometryReader { geo in
            let W = geo.size.width
            let H = geo.size.height
            let gutter: CGFloat = 1
            // Two stacked squares plus the inter-tile gutter fill height `H`.
            let R = (H - gutter) / 2
            let rightW = R
            let leftW = max(0, W - rightW - gutter)
            HStack(spacing: gutter) {
                mainTile(width: leftW, height: H)
                VStack(spacing: gutter) {
                    smallTile(url: smallURLs.indices.contains(0) ? smallURLs[0] : nil, side: R)
                    smallTile(url: smallURLs.indices.contains(1) ? smallURLs[1] : nil, side: R)
                }
                .frame(width: rightW, height: H)
            }
            .frame(width: W, height: H)
        }
        .aspectRatio(Self.mosaicAspect, contentMode: .fit)
        .clipShape(.rect(cornerRadius: cornerRadius))
    }

    /// Width : height of the mosaic region (Pinterest boards).
    static let mosaicAspect: CGFloat = 3.0 / 2.0

    @ViewBuilder
    private func mainTile(width: CGFloat, height: CGFloat) -> some View {
        Group {
            if let s = mainCoverURL, let url = URL(string: s) {
                LazyImage(url: url) { state in
                    if let image = state.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Color(.systemGray5)
                    }
                }
                .pipeline(.shared)
            } else {
                MixtapeCoverView(mixtape: mixtape, cornerRadius: 0, showsShadow: false)
            }
        }
        .frame(width: width, height: height)
        .clipped()
    }

    @ViewBuilder
    private func smallTile(url: String?, side: CGFloat) -> some View {
        ZStack {
            Color(.systemGray5)
            if let url, let u = URL(string: url) {
                LazyImage(url: u) { state in
                    if let image = state.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    }
                }
                .pipeline(.shared)
            }
        }
        .frame(width: side, height: side)
        .clipped()
    }
}
