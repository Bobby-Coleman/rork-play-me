import SwiftUI

/// Album row for search results. Square artwork + title + artist byline +
/// an optional share button on the right. Tapping the row opens the
/// album in `AlbumDetailView` via the caller's sheet state. Kept
/// stateless so cell reuse never paints a stale album's artwork over a
/// new binding — see `ArtistResultRow` for the full identity-safety
/// write-up that this row also follows (via the `.id(album.id)` applied
/// at the call site and `AsyncImage(url:)` being pure).
///
/// Search results intentionally do not surface a "save album to mixtape"
/// affordance here. Saving an album is reachable from the unified share
/// view's bookmark icon (or by opening the album and saving its tracks
/// individually), so showing a `+` next to every search hit just adds
/// visual noise on a row whose primary intent is "open or share".
struct AlbumResultRow: View {
    let album: Album
    let onTap: () -> Void
    var onShareTap: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onTap) {
                HStack(spacing: 12) {
                    artwork
                    VStack(alignment: .leading, spacing: 3) {
                        Text(album.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(subtitle)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let onShareTap {
                Button(action: onShareTap) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Share album")
            }
        }
        .padding(.vertical, 6)
    }

    private var subtitle: String {
        var parts: [String] = ["ALBUM"]
        if let artist = album.artistName, !artist.isEmpty {
            parts.append(artist)
        }
        if let year = album.releaseYear, !year.isEmpty {
            parts.append(year)
        }
        return parts.joined(separator: " · ")
    }

    private var artwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(0.08))

            if let url = URL(string: album.artworkURL) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: "square.stack")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
                .id(album.artworkURL)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
        .frame(width: 48, height: 48)
    }
}
