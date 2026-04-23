import Foundation

/// iTunes album summary used on `ArtistView` and as the entry point into
/// `AlbumDetailView`. iTunes refers to albums as "collections"; we keep the
/// UI-facing name `Album` because that's what users understand.
nonisolated struct Album: Identifiable, Hashable, Sendable {
    /// iTunes `collectionId` as a String (matches `Song.albumId`).
    let id: String
    let name: String
    let artworkURL: String
    let releaseYear: String?
    let trackCount: Int?
    let primaryGenre: String?

    init(
        id: String,
        name: String,
        artworkURL: String,
        releaseYear: String? = nil,
        trackCount: Int? = nil,
        primaryGenre: String? = nil
    ) {
        self.id = id
        self.name = name
        self.artworkURL = artworkURL
        self.releaseYear = releaseYear
        self.trackCount = trackCount
        self.primaryGenre = primaryGenre
    }
}
