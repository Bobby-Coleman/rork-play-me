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
///
/// Curated Discover feed mixtapes use `ownerId == featuredOwnerId` and live
/// in the top-level `featured_mixtapes` collection — same struct so detail
/// and share views stay unified.
nonisolated struct Mixtape: Identifiable, Hashable, Sendable {
    let id: String
    let ownerId: String
    var name: String
    /// Optional short paragraph the owner can write under the title — a
    /// "what is this mixtape about" blurb. Nil until the owner adds one;
    /// rendered under the song count on `MixtapeDetailView` and travels
    /// alongside the mixtape in any mixtape-share snapshot. Capped at
    /// 300 chars at the edit-sheet entry point so we never need to
    /// truncate at render time.
    var description: String?
    /// Firebase Storage download URL for the board cover. Required for
    /// every newly created user mixtape; nil on legacy docs and the
    /// synthetic Liked mixtape (mosaic fallback from songs).
    var coverImageURL: String?
    /// When community Discover ships, only `isPrivate == false` mixtapes
    /// surface publicly. Not shown in UI yet — defaults to false.
    var isPrivate: Bool
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
        description: String? = nil,
        coverImageURL: String? = nil,
        isPrivate: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        songs: [Song] = [],
        isSystemLiked: Bool = false
    ) {
        self.id = id
        self.ownerId = ownerId
        self.name = name
        self.description = description
        self.coverImageURL = coverImageURL
        self.isPrivate = isPrivate
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

    /// Sentinel `ownerId` for documents in `featured_mixtapes/`. Never a
    /// real Firebase Auth uid — used so `MixtapeDetailView` can hide owner
    /// chrome without a separate view type.
    static let featuredOwnerId = "__featured__"
}
