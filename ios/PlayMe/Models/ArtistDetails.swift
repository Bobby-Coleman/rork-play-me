import Foundation

/// Aggregated artist data returned by `ArtistLookupService`.
nonisolated struct ArtistDetails: Hashable, Sendable {
    let artistId: String
    let artistName: String
    let topTracks: [Song]
    let albums: [Album]
}
