import Foundation

nonisolated struct Song: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let artist: String
    let albumArtURL: String
    let duration: String
    let spotifyURI: String?
    let previewURL: String?
    let appleMusicURL: String?

    init(id: String, title: String, artist: String, albumArtURL: String, duration: String, spotifyURI: String? = nil, previewURL: String? = nil, appleMusicURL: String? = nil) {
        self.id = id
        self.title = title
        self.artist = artist
        self.albumArtURL = albumArtURL
        self.duration = duration
        self.spotifyURI = spotifyURI
        self.previewURL = previewURL
        self.appleMusicURL = appleMusicURL
    }
}
