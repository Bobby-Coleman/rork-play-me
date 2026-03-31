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
            previewURL: previewUrl
        )
    }
}

nonisolated struct SpotifySearchResponse: Codable, Sendable {
    let tracks: SpotifySearchTrackResults
}

nonisolated struct SpotifySearchTrackResults: Codable, Sendable {
    let items: [SpotifyTrack]
}

actor MusicSearchService {
    static let shared = MusicSearchService()

    private let baseURL = "https://itunes.apple.com/search"
    private let spotifySearchURL = "https://api.spotify.com/v1/search"

    func searchSpotify(term: String, token: String, limit: Int = 25) async throws -> [Song] {
        guard !term.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }

        guard let encoded = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(spotifySearchURL)?q=\(encoded)&type=track&limit=\(limit)") else {
            return []
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return []
        }

        let decoded = try JSONDecoder().decode(SpotifySearchResponse.self, from: data)
        return decoded.tracks.items.map { track in
            let artURL = track.album.images.first?.url ?? ""
            let durationSec = track.duration_ms / 1000
            let mins = durationSec / 60
            let secs = durationSec % 60
            let duration = "\(mins):\(String(format: "%02d", secs))"
            return Song(
                id: track.id,
                title: track.name,
                artist: track.artists.map(\.name).joined(separator: ", "),
                albumArtURL: artURL,
                duration: duration,
                spotifyURI: track.uri
            )
        }
    }

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
}
