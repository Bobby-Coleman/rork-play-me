import Foundation

/// Bridge to [song.link](https://song.link) used to turn an Apple Music
/// URL (returned by MusicKit search) into the equivalent Spotify URL so
/// Spotify-preferring users can open a shared song in their app of
/// choice. Catalog search itself lives in `AppleMusicSearchService`.
nonisolated struct SonglinkResponse: Codable, Sendable {
    let linksByPlatform: [String: SonglinkPlatformLink]?
}

nonisolated struct SonglinkPlatformLink: Codable, Sendable {
    let url: String?
}

actor MusicSearchService {
    static let shared = MusicSearchService()

    private var songlinkCache: [String: String] = [:]

    /// Resolves the Apple Music song URL to a Spotify URL via song.link.
    /// Cached per-URL for the session. Returns `nil` when song.link has
    /// no Spotify match or the request fails.
    func resolveSpotifyURL(appleMusicURL: String) async -> String? {
        if let cached = songlinkCache[appleMusicURL] {
            return cached
        }

        guard var components = URLComponents(string: "https://api.song.link/v1-alpha.1/links") else { return nil }
        components.queryItems = [URLQueryItem(name: "url", value: appleMusicURL)]
        guard let url = components.url else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse else {
                print("[SongLink] No HTTP response for \(appleMusicURL)")
                return nil
            }
            guard (200...299).contains(http.statusCode) else {
                print("[SongLink] HTTP \(http.statusCode) for \(appleMusicURL)")
                return nil
            }
            let decoded = try JSONDecoder().decode(SonglinkResponse.self, from: data)
            if let spotifyURL = decoded.linksByPlatform?["spotify"]?.url {
                songlinkCache[appleMusicURL] = spotifyURL
                print("[SongLink] Resolved \(appleMusicURL) -> \(spotifyURL)")
                return spotifyURL
            }
            print("[SongLink] No Spotify platform in response for \(appleMusicURL)")
        } catch {
            print("[SongLink] Error resolving \(appleMusicURL): \(error)")
        }

        return nil
    }
}
