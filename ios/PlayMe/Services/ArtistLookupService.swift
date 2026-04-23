import Foundation

/// Raw wrapper for iTunes `/lookup` responses. The endpoint returns a
/// heterogenous result array (the artist itself followed by songs or albums),
/// so we decode with permissive optionals and partition at the call site.
nonisolated struct iTunesLookupResponse: Codable, Sendable {
    let resultCount: Int
    let results: [iTunesLookupItem]
}

nonisolated struct iTunesLookupItem: Codable, Sendable {
    let wrapperType: String?
    // Artist row
    let artistId: Int?
    let artistName: String?
    // Collection (album) row
    let collectionId: Int?
    let collectionName: String?
    let artworkUrl100: String?
    let releaseDate: String?
    let trackCount: Int?
    let primaryGenreName: String?
    let collectionType: String?
    // Track row (we reuse this for album tracks too)
    let trackId: Int?
    let trackName: String?
    let trackTimeMillis: Int?
    let previewUrl: String?
    let trackViewUrl: String?
    let collectionArtworkUrl100: String?

    func toAlbum() -> Album? {
        guard let id = collectionId, let name = collectionName else { return nil }
        let art = (artworkUrl100 ?? "").replacingOccurrences(of: "100x100", with: "600x600")
        return Album(
            id: String(id),
            name: name,
            artworkURL: art,
            releaseYear: releaseDate.flatMap { String($0.prefix(4)) },
            trackCount: trackCount,
            primaryGenre: primaryGenreName
        )
    }

    func toSong(overrideArtistId: String? = nil, overrideAlbumId: String? = nil) -> Song? {
        guard let tid = trackId, let title = trackName, let name = artistName else { return nil }
        let art100 = artworkUrl100 ?? collectionArtworkUrl100 ?? ""
        let art = art100.replacingOccurrences(of: "100x100", with: "600x600")
        let minutes = (trackTimeMillis ?? 0) / 1000 / 60
        let seconds = ((trackTimeMillis ?? 0) / 1000) % 60
        let duration = trackTimeMillis == nil ? "" : "\(minutes):\(String(format: "%02d", seconds))"
        return Song(
            id: String(tid),
            title: title,
            artist: name,
            albumArtURL: art,
            duration: duration,
            previewURL: previewUrl,
            appleMusicURL: trackViewUrl,
            artistId: overrideArtistId ?? artistId.map(String.init),
            albumId: overrideAlbumId ?? collectionId.map(String.init)
        )
    }
}

/// Thin iTunes `lookup` wrapper used to power the artist page.
///
/// iTunes doesn't expose a true "top tracks" endpoint, but
/// `lookup?id={artistId}&entity=song&limit=N` returns an order that's close
/// enough for a minimalist popular list (iTunes ranks by popularity within
/// an artist's catalog). We cache per-artist so re-opening the page is
/// instant, and dedupe albums by collectionId.
actor ArtistLookupService {
    static let shared = ArtistLookupService()

    private let baseURL = "https://itunes.apple.com/lookup"
    private var detailsCache: [String: ArtistDetails] = [:]
    private var albumTrackCache: [String: [Song]] = [:]

    /// Fetch popular tracks + albums for an artist. Results are cached in
    /// memory. Pass `forceRefresh: true` to bypass.
    func fetchArtistDetails(artistId: String, forceRefresh: Bool = false) async throws -> ArtistDetails {
        if !forceRefresh, let cached = detailsCache[artistId] {
            return cached
        }

        async let tracks = fetchTopTracks(artistId: artistId)
        async let albums = fetchAlbums(artistId: artistId)

        let (topTracks, albumList) = try await (tracks, albums)
        let name = topTracks.first?.artist ?? albumList.first.map { _ in "" } ?? ""

        let details = ArtistDetails(
            artistId: artistId,
            artistName: name,
            topTracks: topTracks,
            albums: albumList
        )
        detailsCache[artistId] = details
        return details
    }

    /// Track list for a single album (iTunes "collection"). Cached per album.
    func fetchAlbumTracks(albumId: String, forceRefresh: Bool = false) async throws -> [Song] {
        if !forceRefresh, let cached = albumTrackCache[albumId] {
            return cached
        }
        guard let url = URL(string: "\(baseURL)?id=\(albumId)&entity=song&limit=200") else {
            return []
        }
        let items = try await fetch(url: url)
        let tracks = items
            .filter { $0.wrapperType == "track" && $0.trackId != nil }
            .compactMap { $0.toSong(overrideAlbumId: albumId) }
        albumTrackCache[albumId] = tracks
        return tracks
    }

    private func fetchTopTracks(artistId: String) async throws -> [Song] {
        guard let url = URL(string: "\(baseURL)?id=\(artistId)&entity=song&limit=20") else {
            return []
        }
        let items = try await fetch(url: url)
        return items
            .filter { $0.wrapperType == "track" && $0.trackId != nil }
            .compactMap { $0.toSong(overrideArtistId: artistId) }
    }

    private func fetchAlbums(artistId: String) async throws -> [Album] {
        guard let url = URL(string: "\(baseURL)?id=\(artistId)&entity=album&limit=50") else {
            return []
        }
        let items = try await fetch(url: url)
        var seen = Set<String>()
        let albums: [Album] = items
            .filter { $0.wrapperType == "collection" }
            .compactMap { $0.toAlbum() }
            .filter { seen.insert($0.id).inserted }
        // Newest first. iTunes returns ISO-ish strings ("2017-04-14T07:00:00Z");
        // lexicographic sort on the original `releaseDate` field would be ideal
        // but we don't keep it here, so fall back to year-desc which is close enough.
        return albums.sorted { (a, b) in
            (a.releaseYear ?? "") > (b.releaseYear ?? "")
        }
    }

    private func fetch(url: URL) async throws -> [iTunesLookupItem] {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return []
        }
        let decoded = try JSONDecoder().decode(iTunesLookupResponse.self, from: data)
        return decoded.results
    }
}
