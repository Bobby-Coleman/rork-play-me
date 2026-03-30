import Foundation

nonisolated struct Song: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let artist: String
    let albumArtURL: String
    let duration: String
    let spotifyURI: String?

    init(id: String, title: String, artist: String, albumArtURL: String, duration: String, spotifyURI: String? = nil) {
        self.id = id
        self.title = title
        self.artist = artist
        self.albumArtURL = albumArtURL
        self.duration = duration
        self.spotifyURI = spotifyURI
    }
}
