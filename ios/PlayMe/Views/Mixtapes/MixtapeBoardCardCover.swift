import SwiftUI
import NukeUI
import Nuke

/// Pinterest "board" preview: one large cover (custom image or mosaic)
/// on the left (~62%), two stacked song art tiles on the right, thin
/// black separators — matches the Mixtapes tab reference layout.
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
            let w = geo.size.width
            let h = geo.size.height
            let leftW = w * 0.62
            let rightW = w - leftW - 1
            HStack(spacing: 1) {
                mainTile(width: leftW, height: h)
                VStack(spacing: 1) {
                    smallTile(url: smallURLs.indices.contains(0) ? smallURLs[0] : nil, width: rightW, height: h / 2 - 0.5)
                    smallTile(url: smallURLs.indices.contains(1) ? smallURLs[1] : nil, width: rightW, height: h / 2 - 0.5)
                }
                .frame(width: rightW, height: h)
            }
            .frame(width: w, height: h)
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(.rect(cornerRadius: cornerRadius))
    }

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
    private func smallTile(url: String?, width: CGFloat, height: CGFloat) -> some View {
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
        .frame(width: width, height: height)
        .clipped()
    }
}
