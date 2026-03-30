import Foundation

nonisolated struct Song: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let artist: String
    let albumArtURL: String
    let duration: String
    let previewURL: String?
    let spotifyURI: String?
    let spotifyID: String?

    init(id: String, title: String, artist: String, albumArtURL: String, duration: String, previewURL: String? = nil, spotifyURI: String? = nil, spotifyID: String? = nil) {
        self.id = id
        self.title = title
        self.artist = artist
        self.albumArtURL = albumArtURL
        self.duration = duration
        self.previewURL = previewURL
        self.spotifyURI = spotifyURI
        self.spotifyID = spotifyID
    }

    var spotifyDeepLink: URL? {
        guard let uri = spotifyURI else { return nil }
        return URL(string: "spotify:track:\(uri.replacingOccurrences(of: "spotify:track:", with: ""))")
    }

    var spotifyWebURL: URL? {
        guard let spotifyID else { return nil }
        return URL(string: "https://open.spotify.com/track/\(spotifyID)")
    }
}
