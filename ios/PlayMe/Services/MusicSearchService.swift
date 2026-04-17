import Foundation

nonisolated struct iTunesSearchResponse: Codable, Sendable {
    let resultCount: Int
    let results: [iTunesTrack]
}

nonisolated struct iTunesTrack: Codable, Sendable {
    let trackId: Int
    let trackName: String
    let artistName: String
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
            appleMusicURL: trackViewUrl
        )
    }
}

nonisolated struct SonglinkResponse: Codable, Sendable {
    let linksByPlatform: [String: SonglinkPlatformLink]?
}

nonisolated struct SonglinkPlatformLink: Codable, Sendable {
    let url: String?
}

nonisolated struct iTunesArtistSearchResponse: Codable, Sendable {
    let resultCount: Int
    let results: [iTunesArtist]
}

nonisolated struct iTunesArtist: Codable, Sendable {
    let artistId: Int
    let artistName: String
    let primaryGenreName: String?
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

    /// Search for artists only, used by the onboarding favorite-artists picker.
    func searchArtists(term: String, limit: Int = 10) async throws -> [iTunesArtist] {
        guard !term.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }

        guard let encoded = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(baseURL)?term=\(encoded)&media=music&entity=musicArtist&limit=\(limit)") else {
            return []
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return []
        }

        let decoded = try JSONDecoder().decode(iTunesArtistSearchResponse.self, from: data)
        // Deduplicate by artistName; iTunes sometimes returns the same artist multiple times.
        var seen = Set<String>()
        var out: [iTunesArtist] = []
        for artist in decoded.results {
            let key = artist.artistName.lowercased()
            if seen.insert(key).inserted {
                out.append(artist)
            }
        }
        return out
    }

    /// Fetch top tracks for a specific artist via iTunes `attribute=artistTerm`.
    /// Used by SongSuggestionsService to assemble the first-send song carousel.
    func topTracks(forArtist artist: String, limit: Int = 6) async throws -> [Song] {
        let trimmed = artist.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }

        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(baseURL)?term=\(encoded)&media=music&entity=song&attribute=artistTerm&limit=\(limit)") else {
            return []
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return []
        }

        let decoded = try JSONDecoder().decode(iTunesSearchResponse.self, from: data)
        return decoded.results.map { $0.toSong() }
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
