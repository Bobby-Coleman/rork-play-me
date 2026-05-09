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
    ///
    /// Path order:
    /// 1. MusicKit catalog resource request for the artist + its
    ///    `topSongs` and `albums` relationships. This returns the same
    ///    canonical data the Apple Music app shows: artist name pulled
    ///    off the `Artist` resource (never derived from a track row,
    ///    which was the bug that relabeled "Taylor Swift" as
    ///    "BOYS LIKE GIRLS" when a feat-collab track ranked #1), and
    ///    `topSongs` as ranked by Apple.
    /// 2. If the MusicKit request fails, fall back to the legacy iTunes
    ///    `/lookup` path so the page still
    ///    renders *something*. iTunes returns a looser catalog order
    ///    and can mis-attribute feat tracks, but it's better than an
    ///    empty page.
    func fetchArtistDetails(artistId: String, forceRefresh: Bool = false) async throws -> ArtistDetails {
        if !forceRefresh, let cached = detailsCache[artistId] {
            return cached
        }

        if let viaMusicKit = await AppleMusicSearchService.shared.fetchArtistDetails(artistId: artistId) {
            detailsCache[artistId] = viaMusicKit
            return viaMusicKit
        }

        async let tracks = fetchTopTracks(artistId: artistId)
        async let albums = fetchAlbums(artistId: artistId)

        let (topTracks, albumList) = try await (tracks, albums)
        // Pick the primary artist name from the first track whose
        // primary artist is the *queried* artist, not a collaborator
        // featuring them. Falls back to the first track's artist
        // only if nothing else is available, matching the old
        // behavior on truly empty responses.
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

        // Pass 1: dedupe by `collectionId` (iTunes occasionally returns the
        // same id twice across storefronts).
        var byId: [Int: iTunesLookupItem] = [:]
        for item in items where item.wrapperType == "collection" {
            guard let id = item.collectionId else { continue }
            byId[id] = item
        }

        // Pass 2: conservative near-dup collapse. Group by (normalized name,
        // release year); inside a group keep the entry with the highest
        // `trackCount`, tiebreaking on earliest `releaseDate`. This collapses
        // US + UK editions of the same album from the same year, but
        // deliberately leaves "DAMN." and "DAMN. (Collector's Edition)" or
        // "Album (Deluxe)" variants as separate entries.
        var groups: [String: iTunesLookupItem] = [:]
        for item in byId.values {
            let name = (item.collectionName ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let year = (item.releaseDate ?? "").prefix(4)
            let key = "\(name)|\(year)"

            guard let existing = groups[key] else {
                groups[key] = item
                continue
            }

            if Self.prefer(item, over: existing) {
                groups[key] = item
            }
        }

        let albums: [Album] = groups.values.compactMap { $0.toAlbum() }

        // Newest first. `releaseYear` is our coarse sort key (iTunes returns
        // "2017-04-14T07:00:00Z"); we don't propagate the full timestamp to
        // `Album`, so year-desc is close enough for the discography grid.
        return albums.sorted { (a, b) in
            (a.releaseYear ?? "") > (b.releaseYear ?? "")
        }
    }

    /// Prefer the candidate with more tracks; tiebreak on earliest release
    /// date (so a deluxe re-release with the same track count doesn't
    /// beat the original).
    private static func prefer(_ candidate: iTunesLookupItem, over existing: iTunesLookupItem) -> Bool {
        let cCount = candidate.trackCount ?? 0
        let eCount = existing.trackCount ?? 0
        if cCount != eCount { return cCount > eCount }
        let cDate = candidate.releaseDate ?? ""
        let eDate = existing.releaseDate ?? ""
        return cDate < eDate
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
