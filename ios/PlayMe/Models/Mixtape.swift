import Foundation

/// A user-curated collection of saved songs (Pinterest-style "board"). Stored
/// at `users/{ownerId}/mixtapes/{id}` with an inner `songs/{songId}`
/// subcollection that mirrors the same `Song` shape used everywhere else in
/// the app (shares, chat messages) so cover-mosaic loads don't pay an N+1
/// fetch cost.
///
/// The system-managed "Liked" mixtape is the one exception: it is never
/// persisted as a real Firestore document. `MixtapeStore` injects a synthetic
/// instance with `isSystemLiked = true` whose `songs` are derived from the
/// user's existing `likedShareIds` set. That keeps the existing per-share
/// like model intact while giving the Mixtapes UI a unified surface.
nonisolated struct Mixtape: Identifiable, Hashable, Sendable {
    let id: String
    let ownerId: String
    var name: String
    var createdAt: Date
    var updatedAt: Date
    /// Ordered list of songs in this mixtape, newest-added-first. Always
    /// contains the embedded `Song` (mirrored on disk) so the cover mosaic
    /// and grid cells render without follow-up reads.
    var songs: [Song]
    /// True only for the synthetic "Liked" mixtape. System-managed mixtapes
    /// cannot be renamed or deleted by the user; the Save sheet special-cases
    /// them so the user keeps the per-share Like as the source of truth.
    var isSystemLiked: Bool

    init(
        id: String,
        ownerId: String,
        name: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        songs: [Song] = [],
        isSystemLiked: Bool = false
    ) {
        self.id = id
        self.ownerId = ownerId
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.songs = songs
        self.isSystemLiked = isSystemLiked
    }

    var songCount: Int { songs.count }

    /// First four album-art URLs used to build the 2x2 cover mosaic. May
    /// contain fewer than 4 entries; the cover view collapses to a 1-up
    /// presentation in that case.
    var coverArtURLs: [String] {
        Array(songs.prefix(4)).map(\.albumArtURL).filter { !$0.isEmpty }
    }

    /// Stable doc-ID prefix for the system Liked mixtape. Never collides with
    /// Firestore-generated IDs (which are lowercase alphanumeric, 20 chars).
    static let systemLikedId = "__system_liked__"
}
