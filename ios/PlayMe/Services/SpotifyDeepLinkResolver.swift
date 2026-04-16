import Foundation

enum SpotifyDeepLinkResolver {

    static func trackURL(for song: Song, resolvedSpotifyURL: String?) -> URL? {
        guard let trackID = spotifyTrackID(for: song, resolvedSpotifyURL: resolvedSpotifyURL) else {
            return nil
        }
        return URL(string: "https://open.spotify.com/track/\(trackID)")
    }

    static func trackURI(for song: Song, resolvedSpotifyURL: String?) -> URL? {
        guard let trackID = spotifyTrackID(for: song, resolvedSpotifyURL: resolvedSpotifyURL) else {
            return nil
        }
        return URL(string: "spotify:track:\(trackID)")
    }

    static func spotifyTrackID(for song: Song, resolvedSpotifyURL: String?) -> String? {
        if let trackID = spotifyTrackID(fromSpotifyURI: song.spotifyURI) {
            return trackID
        }
        return spotifyTrackID(fromSpotifyURL: resolvedSpotifyURL)
    }

    static func spotifySearchURL(for song: Song) -> URL? {
        let query = "\(song.title) \(song.artist)"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "https://open.spotify.com/search/\(query)")
    }

    private static func spotifyTrackID(fromSpotifyURI spotifyURI: String?) -> String? {
        guard let spotifyURI else { return nil }
        let components = spotifyURI.split(separator: ":")
        guard components.count >= 3 else { return nil }
        guard components[0] == "spotify", components[1] == "track" else { return nil }
        let trackID = String(components[2])
        return trackID.isEmpty ? nil : trackID
    }

    static func spotifyTrackID(fromSpotifyURL urlString: String?) -> String? {
        guard let urlString, let url = URL(string: urlString) else { return nil }
        let parts = url.pathComponents
        guard let trackIndex = parts.firstIndex(of: "track"),
              trackIndex + 1 < parts.count else { return nil }
        let trackID = parts[trackIndex + 1]
        return trackID.isEmpty ? nil : trackID
    }
}
