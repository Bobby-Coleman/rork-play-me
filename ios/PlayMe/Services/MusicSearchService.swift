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

    func resolveSpotifyURL(appleMusicURL: String) async -> String? {
        if let cached = songlinkCache[appleMusicURL] {
            return cached
        }

        guard let encoded = appleMusicURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.song.link/v1-alpha.1/links?url=\(encoded)") else {
            return nil
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }
            let decoded = try JSONDecoder().decode(SonglinkResponse.self, from: data)
            if let spotifyURL = decoded.linksByPlatform?["spotify"]?.url {
                songlinkCache[appleMusicURL] = spotifyURL
                return spotifyURL
            }
        } catch {}

        return nil
    }
}
