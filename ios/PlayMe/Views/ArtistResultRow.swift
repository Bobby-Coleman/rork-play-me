import SwiftUI

/// Spotify-style "Top result" row shown above song rows when the current
/// search is artist-intent. Tapping it opens `ArtistView`. The Deezer
/// image resolves lazily — the row renders immediately with a monogram
/// initials fallback and swaps in the photo once the URL arrives.
struct ArtistResultRow: View {
    let artist: ArtistSummary
    let onTap: () -> Void

    @State private var imageURL: String?
    @State private var didResolve: Bool = false

    private var initials: String {
        let tokens = artist.name
            .split(separator: " ")
            .filter { !$0.isEmpty }
            .prefix(2)
        let letters = tokens.compactMap { $0.first.map(String.init) }
        return letters.joined().uppercased()
    }

    private var subtitle: String {
        if let genre = artist.primaryGenre, !genre.isEmpty {
            return "ARTIST · \(genre.uppercased())"
        }
        return "ARTIST"
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                artwork
                VStack(alignment: .leading, spacing: 3) {
                    Text(artist.name)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                        .tracking(0.5)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.35))
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .task(id: artist.id) {
            // Guard against re-runs while the row is reused across keystrokes.
            guard !didResolve else { return }
            didResolve = true
            imageURL = await ArtistImageService.shared.imageURL(forName: artist.name)
        }
    }

    /// Round artwork to visually differentiate the artist row from song
    /// rows (which use a square album thumbnail).
    private var artwork: some View {
        ZStack {
            Circle().fill(Color(.systemGray5))

            if let url = imageURL, let parsed = URL(string: url) {
                AsyncImage(url: parsed) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    }
                }
                .clipShape(Circle())
            } else {
                Text(initials.isEmpty ? "?" : initials)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(Circle())
    }
}

/// "Top result" eyebrow rendered above `ArtistResultRow`. Kept as its own
/// view so both `SendSongSheet` and `QuickSendSongSheet` can reuse the
/// exact same pixel layout.
struct ArtistResultHeader: View {
    var body: some View {
        Text("TOP RESULT")
            .font(.system(size: 11, weight: .bold))
            .tracking(1.5)
            .foregroundStyle(.white.opacity(0.5))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
            .padding(.bottom, 6)
    }
}
