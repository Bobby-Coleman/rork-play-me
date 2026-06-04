import Foundation

enum SpotifyDeepLinkResolver {

    static func trackURL(for song: Song, resolvedSpotifyURL: String?) -> URL? {
        guard let trackID = spotifyTrackID(for: song, resolvedSpotifyURL: resolvedSpotifyURL) else {
            return nil
        }
        return URL(string: "https://open.spotify.com/track/\(trackID)")
    }

    /// Spotify's URI scheme supports a `:play` suffix that tells the app
    /// to start playback immediately after opening the track page. This
    /// mirrors the behavior of shared-from-Spotify links handed off by
    /// iOS universal-link dispatch and is the piece our previous
    /// `spotify:track:<id>` URI was missing. Documented at
    /// developer.spotify.com/documentation/ios/tutorials/content-linking.
    static func trackURI(for song: Song, resolvedSpotifyURL: String?) -> URL? {
        guard let trackID = spotifyTrackID(for: song, resolvedSpotifyURL: resolvedSpotifyURL) else {
            return nil
        }
        return URL(string: "spotify:track:\(trackID):play")
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

    /// Extracts the Apple Music catalog **track** id from a shared Apple
    /// Music URL. Apple's "Share Song" produces an album URL with the track
    /// selected via a `?i=<trackId>` query item, e.g.
    /// `https://music.apple.com/us/album/name/1440841363?i=1440841376`.
    /// Some links instead use a `/song/<id>` path. We prefer `i=` (the
    /// track), then fall back to a `song` path segment, then a trailing
    /// numeric path component. Returns `nil` for album-only links with no
    /// track selector, since those don't identify a single song.
    static func appleMusicTrackID(fromAppleMusicURL urlString: String?) -> String? {
        guard let urlString,
              let components = URLComponents(string: urlString) else { return nil }

        // Preferred: `?i=<trackId>` selects the track inside an album link.
        if let i = components.queryItems?.first(where: { $0.name == "i" })?.value,
           !i.isEmpty {
            return i
        }

        let parts = components.path.split(separator: "/").map(String.init)
        // `/song/<id>` form.
        if let songIndex = parts.firstIndex(of: "song"),
           songIndex + 1 < parts.count {
            let id = parts[songIndex + 1]
            if !id.isEmpty { return id }
        }
        // Trailing numeric component as a last resort (only when it isn't an
        // album path, which would be a collection id, not a track id).
        if parts.contains("album") == false,
           let last = parts.last,
           last.allSatisfy(\.isNumber), !last.isEmpty {
            return last
        }
        return nil
    }
}
