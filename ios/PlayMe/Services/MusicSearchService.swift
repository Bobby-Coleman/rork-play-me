import Foundation

nonisolated struct iTunesSearchResponse: Codable, Sendable {
    let resultCount: Int
    let results: [iTunesTrack]
}

nonisolated struct iTunesTrack: Codable, Sendable {
    let trackId: Int
    let trackName: String
    let artistName: String
    let artistId: Int?
    let collectionId: Int?
    let collectionName: String?
    let artworkUrl100: String
    let trackTimeMillis: Int?
    let previewUrl: String?
    let trackViewUrl: String?

    var artworkUrl600: String {
        artworkUrl100.replacingOccurrences(of: "100x100", with: "600x600")
    }

    var formattedDuration: String {
        guard let millis = trackTimeMillis else { return "" }
        let totalSeconds = millis / 1000
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "\(minutes):\(String(format: "%02d", seconds))"
    }

    func toSong() -> Song {
        Song(
            id: String(trackId),
            title: trackName,
            artist: artistName,
            albumArtURL: artworkUrl600,
            duration: formattedDuration,
            previewURL: previewUrl,
            appleMusicURL: trackViewUrl,
            artistId: artistId.map(String.init),
            albumId: collectionId.map(String.init)
        )
    }
}

nonisolated struct iTunesArtistSearchResponse: Codable, Sendable {
    let resultCount: Int
    let results: [iTunesArtistHit]
}

nonisolated struct iTunesArtistHit: Codable, Sendable {
    let artistId: Int
    let artistName: String
    let primaryGenreName: String?
}

nonisolated struct SonglinkResponse: Codable, Sendable {
    let linksByPlatform: [String: SonglinkPlatformLink]?
}

nonisolated struct SonglinkPlatformLink: Codable, Sendable {
    let url: String?
}

actor MusicSearchService {
    static let shared = MusicSearchService()

    private let baseURL = "https://itunes.apple.com/search"
    private var songlinkCache: [String: String] = [:]

    func search(term: String, limit: Int = 25) async throws -> [Song] {
        guard !term.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }

        guard let encoded = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(baseURL)?term=\(encoded)&media=music&entity=song&limit=\(limit)") else {
            return []
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return []
        }

        let decoded = try JSONDecoder().decode(iTunesSearchResponse.self, from: data)
        return decoded.results.map { $0.toSong() }
    }

    /// Returns the top iTunes artist match for `term`, but only when the
    /// artist's name is a plausible match for the query (normalized prefix or
    /// token containment). This keeps song-intent queries like "bohemian
    /// rhapsody" from pinning a random artist at the top of the results.
    func searchArtist(term: String) async throws -> ArtistSummary? {
        let trimmed = term.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(baseURL)?term=\(encoded)&media=music&entity=musicArtist&limit=1") else {
            return nil
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return nil
        }

        let decoded = try JSONDecoder().decode(iTunesArtistSearchResponse.self, from: data)
        guard let hit = decoded.results.first else { return nil }
        guard Self.queryLooksLikeArtist(query: trimmed, artistName: hit.artistName) else { return nil }

        return ArtistSummary(
            id: String(hit.artistId),
            name: hit.artistName,
            primaryGenre: hit.primaryGenreName
        )
    }

    /// Normalized heuristic: show the artist row only when the query is a
    /// prefix of the artist name OR every query token is a prefix of some
    /// artist token. "kendrick" → "Kendrick Lamar" passes; "damn" → same
    /// artist doesn't.
    private static func queryLooksLikeArtist(query: String, artistName: String) -> Bool {
        let q = normalize(query)
        let a = normalize(artistName)
        guard !q.isEmpty, !a.isEmpty else { return false }
        if a.hasPrefix(q) { return true }

        let qTokens = q.split(separator: " ").map(String.init)
        let aTokens = a.split(separator: " ").map(String.init)
        guard !qTokens.isEmpty else { return false }
        return qTokens.allSatisfy { qt in
            aTokens.contains(where: { $0.hasPrefix(qt) })
        }
    }

    private static func normalize(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
         .folding(options: .diacriticInsensitive, locale: .current)
         .lowercased()
    }

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
