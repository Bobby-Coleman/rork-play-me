import SwiftUI
import NukeUI
import Nuke

/// Pinterest-style square cell for a mixtape on the Home Discover grid:
/// full-bleed cover, bottom 15% black→clear gradient, white title on the
/// gradient.
struct MixtapeGridCell: View {
    let mixtape: Mixtape
    var cornerRadius: CGFloat = 14

    private var coverURL: String? {
        let u = mixtape.coverImageURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !u.isEmpty { return u }
        return mixtape.coverArtURLs.first
    }

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                ZStack(alignment: .bottomLeading) {
                    if let urlString = coverURL, let url = URL(string: urlString) {
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

                    // Bottom ~15%: opaque black at bottom edge → transparent
                    // at 85% from top of the cell.
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .clear, location: 0.85),
                            .init(color: .black, location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    Text(mixtape.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .clipShape(.rect(cornerRadius: cornerRadius))
    }
}
