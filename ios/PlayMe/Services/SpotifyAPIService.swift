import Foundation

nonisolated struct SpotifySearchResponse: Codable, Sendable {
    let tracks: SpotifyTrackResults?
}

nonisolated struct SpotifyTrackResults: Codable, Sendable {
    let items: [SpotifyTrack]
}

nonisolated struct SpotifyTrack: Codable, Sendable {
    let id: String
    let name: String
    let uri: String
    let duration_ms: Int
    let preview_url: String?
    let artists: [SpotifyArtist]
    let album: SpotifyAlbum
    let external_urls: SpotifyExternalURLs

    func toSong() -> Song {
        let artistName = artists.map(\.name).joined(separator: ", ")
        let totalSeconds = duration_ms / 1000
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        let duration = "\(minutes):\(String(format: "%02d", seconds))"
        let artURL = album.images.first?.url ?? ""

        return Song(
            id: id,
            title: name,
            artist: artistName,
            albumArtURL: artURL,
            duration: duration,
            previewURL: preview_url,
            spotifyURI: uri,
            spotifyID: id
        )
    }
}

nonisolated struct SpotifyArtist: Codable, Sendable {
    let id: String
    let name: String
}

nonisolated struct SpotifyAlbum: Codable, Sendable {
    let name: String
    let images: [SpotifyImage]
}

nonisolated struct SpotifyImage: Codable, Sendable {
    let url: String
    let height: Int?
    let width: Int?
}

nonisolated struct SpotifyExternalURLs: Codable, Sendable {
    let spotify: String?
}

@MainActor
class SpotifyAPIService {
    static let shared = SpotifyAPIService()

    private let baseURL = "https://api.spotify.com/v1"

    func search(term: String, accessToken: String, limit: Int = 25) async throws -> [Song] {
        guard !term.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }

        guard let encoded = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(baseURL)/search?q=\(encoded)&type=track&limit=\(limit)") else {
            return []
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return []
        }

        let decoded = try JSONDecoder().decode(SpotifySearchResponse.self, from: data)
        return decoded.tracks?.items.map { $0.toSong() } ?? []
    }
}
