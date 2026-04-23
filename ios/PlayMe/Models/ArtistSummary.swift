import Foundation

/// Lightweight artist result returned by `MusicSearchService.searchArtist`.
/// Image URL is intentionally absent — it's resolved lazily at the view
/// layer via `ArtistImageService` so every keystroke doesn't pay the cost
/// of a second network hop.
nonisolated struct ArtistSummary: Identifiable, Hashable, Sendable {
    /// Apple Music (MusicKit) `artistID` as a string. For legacy call sites
    /// and backwards compatibility this also matches the shape of an iTunes
    /// `artistId`.
    let id: String
    let name: String
    let primaryGenre: String?
    /// Pre-resolved artist image URL — populated when we got one from the
    /// same MusicKit search response that produced this row. When nil, the
    /// UI falls back to Deezer via `ArtistImageService`.
    let imageURL: String?

    init(
        id: String,
        name: String,
        primaryGenre: String? = nil,
        imageURL: String? = nil
    ) {
        self.id = id
        self.name = name
        self.primaryGenre = primaryGenre
        self.imageURL = imageURL
    }
}
