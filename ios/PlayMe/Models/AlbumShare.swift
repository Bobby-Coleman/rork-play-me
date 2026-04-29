import Foundation

/// A snapshot of an album sent from one user to another. The album
/// metadata (name, artwork, year) and full track list are frozen into
/// the share doc — same snapshot semantics as `SongShare` and
/// `MixtapeShare`, so the recipient view never needs a follow-up
/// `ArtistLookupService.fetchAlbumTracks` call.
nonisolated struct AlbumShare: Identifiable, Hashable, Sendable {
    let id: String
    let album: Album
    /// Tracks at send time, embedded directly. Ordered by the
    /// catalog's natural track number — matches what
    /// `ArtistLookupService.fetchAlbumTracks` returns.
    let songs: [Song]
    let sender: AppUser
    let recipient: AppUser
    let note: String?
    let timestamp: Date

    init(
        id: String = UUID().uuidString,
        album: Album,
        songs: [Song],
        sender: AppUser,
        recipient: AppUser,
        note: String? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.album = album
        self.songs = songs
        self.sender = sender
        self.recipient = recipient
        self.note = note
        self.timestamp = timestamp
    }
}
