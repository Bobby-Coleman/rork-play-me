import SwiftUI

/// Spotify-style "Top result" row shown above song rows when the current
/// search is artist-intent. Tapping it opens `ArtistView`. The Deezer
/// image resolves lazily — the row renders immediately with a monogram
/// initials fallback and swaps in the photo once the URL arrives.
struct ArtistResultRow: View {
    let artist: ArtistSummary
    let onTap: () -> Void

    /// Image state keyed by the *resolved* artist id so we can prove that
    /// whatever URL is on screen corresponds to the currently-bound artist.
    /// If `forArtistId` no longer matches `artist.id` we treat the URL as
    /// stale and render the monogram until the current request lands.
    @State private var resolvedImage: (forArtistId: String, url: String?)?

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
            // Critical for rapid-typing scenarios (Olivia Rodrigo → Olivia
            // Dean): if the previous task already wrote a URL, that URL
            // belonged to the old artist. Until the new request resolves we
            // must not display it. Clear the state whenever identity flips
            // so the monogram fills in deterministically in the meantime.
            if resolvedImage?.forArtistId != artist.id {
                resolvedImage = nil
            }
            let targetId = artist.id

            // MusicKit search embeds an artist artwork URL directly on
            // the Artist entity — no second network hop needed. When we
            // have it, prefer it (this is the common path now) and skip
            // Deezer entirely.
            if let embedded = artist.imageURL, !embedded.isEmpty {
                resolvedImage = (forArtistId: targetId, url: embedded)
                return
            }

            // Legacy / fallback path: artists without a MusicKit-provided
            // image (e.g. a tappable byline constructed from a Firestore
            // share that predates this schema) still resolve via Deezer.
            let resolved = await ArtistImageService.shared.imageURL(forName: artist.name)
            // `.task(id:)` cancels the prior task on identity change, so a
            // late-landing response from the previous keystroke will observe
            // `Task.isCancelled` here and bail without touching state.
            guard !Task.isCancelled, targetId == artist.id else { return }
            resolvedImage = (forArtistId: targetId, url: resolved)
        }
    }

    /// Only exposes the image URL when it was resolved for the artist
    /// currently bound to this row. Guards against stale URL → new text
    /// pairings during the resolution window.
    private var displayedImageURL: String? {
        guard let resolved = resolvedImage, resolved.forArtistId == artist.id else {
            return nil
        }
        return resolved.url
    }

    /// Round artwork to visually differentiate the artist row from song
    /// rows (which use a square album thumbnail).
    private var artwork: some View {
        ZStack {
            Circle().fill(Color(.systemGray5))

            if let url = displayedImageURL, let parsed = URL(string: url) {
                AsyncImage(url: parsed) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        // While AsyncImage is fetching the new URL, fall
                        // back to the monogram rather than holding onto a
                        // previously displayed image from the reused cell.
                        Text(initials.isEmpty ? "?" : initials)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                // Tying AsyncImage's identity to the URL forces SwiftUI to
                // tear down and re-instantiate the loader when the URL
                // flips — no way for a late completion on the prior URL to
                // paint the wrong image into the new view.
                .id(parsed)
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
