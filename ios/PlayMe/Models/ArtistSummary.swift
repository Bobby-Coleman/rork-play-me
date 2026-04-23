import Foundation

/// Lightweight artist result returned by `MusicSearchService.searchArtist`.
/// Image URL is intentionally absent — it's resolved lazily at the view
/// layer via `ArtistImageService` so every keystroke doesn't pay the cost
/// of a second network hop.
nonisolated struct ArtistSummary: Identifiable, Hashable, Sendable {
    /// iTunes `artistId` as a string (matches `Song.artistId`).
    let id: String
    let name: String
    let primaryGenre: String?
}
