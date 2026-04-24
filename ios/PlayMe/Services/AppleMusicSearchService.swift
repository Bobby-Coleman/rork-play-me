import Foundation
import MusicKit

/// Apple Music (MusicKit) catalog search. Returns songs/artists/albums
/// pre-ranked by Apple's own relevance model — the same ordering you'd
/// get in the Apple Music app. Used for in-app typeahead regardless of
/// the user's preferred streaming service; for playback we still route
/// through `AudioPlayerService` (30s previews) and deep-link into the
/// user's preferred service via `resolveSpotifyURL`.
///
/// Two things are required for this to work on-device:
/// 1. The App ID at developer.apple.com must have the **MusicKit** App
///    Service enabled.
/// 2. Info.plist must declare `NSAppleMusicUsageDescription`.
///
/// An active Apple Music subscription is *not* required — catalog search
/// and 30-second previews work for every user who grants authorization.
actor AppleMusicSearchService {
    static let shared = AppleMusicSearchService()

    /// Cached authorization status. Read via `currentAuthorizationStatus()`
    /// so the UI can gate noResultsView on `.denied` without every
    /// keystroke hitting MusicKit.
    private var cachedAuthStatus: MusicAuthorization.Status?

    /// Returns the current authorization status, requesting permission if
    /// the user hasn't been prompted yet. Safe to call on every search —
    /// MusicKit itself deduplicates the prompt.
    func currentAuthorizationStatus() async -> MusicAuthorization.Status {
        if let cached = cachedAuthStatus, cached != .notDetermined {
            return cached
        }
        let current = MusicAuthorization.currentStatus
        if current == .notDetermined {
            let requested = await MusicAuthorization.request()
            cachedAuthStatus = requested
            return requested
        }
        cachedAuthStatus = current
        return current
    }

    /// Performs a catalog search for the given term and maps MusicKit
    /// models onto the app's internal `Song` / `ArtistSummary` / `Album`
    /// types. Honors cancellation — if the caller's `Task` is cancelled
    /// mid-flight (typical with typeahead), we return an empty result
    /// without touching the cache.
    ///
    /// Fans out two requests in parallel:
    /// 1. `MusicCatalogSearchSuggestionsRequest` — Apple's typeahead
    ///    endpoint. Handles prefix completion ("suf" → Sufjan Stevens)
    ///    the same way the Apple Music app does. Drives the top hit and
    ///    leads every per-type bucket.
    /// 2. `MusicCatalogSearchRequest` — the full catalog search. Pads
    ///    the tail of each bucket with extra items so per-tab filter
    ///    lists ("Songs", "Albums", "Artists") feel full even when
    ///    suggestions only returned a handful of items.
    ///
    /// Merge rule: suggestions items take priority and keep their order;
    /// full-search items are appended only when their `id` hasn't already
    /// appeared from suggestions.
    ///
    /// - Parameter term: User-typed search text. Whitespace-trimmed here.
    /// - Parameter limit: Max items per bucket for the full search.
    func search(term: String, limit: Int = 20) async -> AppleMusicSearchResults {
        let trimmed = term.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return .empty }

        let status = await currentAuthorizationStatus()
        guard status == .authorized else {
            return AppleMusicSearchResults(
                songs: [], artists: [], albums: [],
                topHit: nil, authStatus: status
            )
        }

        async let suggestionsTask = Self.fetchSuggestions(term: trimmed, limit: 10)
        async let fullTask = Self.fetchFullSearch(term: trimmed, limit: min(max(limit, 1), 25))
        let (suggestionsResp, fullResp) = await (suggestionsTask, fullTask)

        if Task.isCancelled { return .empty }

        // Union artist-name → id map across both responses so song rows
        // get a tappable artist byline whether the matching artist came
        // from suggestions or the fuller search.
        var artistIdByName: [String: String] = [:]
        if let s = suggestionsResp {
            for top in s.topResults {
                if case .artist(let a) = top {
                    let key = Self.normalize(a.name)
                    if artistIdByName[key] == nil { artistIdByName[key] = a.id.rawValue }
                }
            }
        }
        if let f = fullResp {
            for artist in f.artists {
                let key = Self.normalize(artist.name)
                if artistIdByName[key] == nil { artistIdByName[key] = artist.id.rawValue }
            }
        }

        // Collect suggestions top results into our three buckets in the
        // order Apple returned them.
        var suggSongs: [Song] = []
        var suggArtists: [ArtistSummary] = []
        var suggAlbums: [Album] = []
        var suggTopHit: SearchResults.TopHit?

        if let s = suggestionsResp {
            for top in s.topResults {
                switch top {
                case .song(let mkSong):
                    let mapped = Self.mapSong(mkSong, artistIdByName: artistIdByName)
                    suggSongs.append(mapped)
                    if suggTopHit == nil { suggTopHit = .song(mapped) }
                case .artist(let mkArtist):
                    let mapped = Self.mapArtist(mkArtist)
                    suggArtists.append(mapped)
                    if suggTopHit == nil { suggTopHit = .artist(mapped) }
                case .album(let mkAlbum):
                    let mapped = Self.mapAlbum(mkAlbum)
                    suggAlbums.append(mapped)
                    if suggTopHit == nil { suggTopHit = .album(mapped) }
                @unknown default:
                    continue
                }
            }
        }

        // Map full-search buckets, then pad onto suggestions with dedupe
        // by id. Preserves typeahead ordering while giving the per-tab
        // lists enough depth to feel complete.
        let fullSongs: [Song] = fullResp?.songs.map { Self.mapSong($0, artistIdByName: artistIdByName) } ?? []
        let fullArtists: [ArtistSummary] = fullResp?.artists.map(Self.mapArtist(_:)) ?? []
        let fullAlbums: [Album] = fullResp?.albums.map(Self.mapAlbum(_:)) ?? []

        let mergedSongs = Self.mergeDedupe(primary: suggSongs, fallback: fullSongs, id: \Song.id)
        let mergedArtists = Self.mergeDedupe(primary: suggArtists, fallback: fullArtists, id: \ArtistSummary.id)
        let mergedAlbums = Self.mergeDedupe(primary: suggAlbums, fallback: fullAlbums, id: \Album.id)

        // topHit: suggestions wins — that's exactly what the Apple Music
        // app surfaces above the autocomplete list. Only fall back to
        // the name-match heuristic when suggestions returned nothing
        // (rare: gibberish queries).
        let topHit: SearchResults.TopHit? = {
            if let hit = suggTopHit { return hit }
            if let artist = mergedArtists.first,
               Self.queryMatchesArtistName(trimmed, artist: artist) {
                return .artist(artist)
            }
            if let song = mergedSongs.first { return .song(song) }
            if let artist = mergedArtists.first { return .artist(artist) }
            if let album = mergedAlbums.first { return .album(album) }
            return nil
        }()

        return AppleMusicSearchResults(
            songs: mergedSongs,
            artists: mergedArtists,
            albums: mergedAlbums,
            topHit: topHit,
            authStatus: .authorized
        )
    }

    // MARK: - Request fan-out

    /// Apple's typeahead endpoint. Returns prefix-aware top results
    /// (Sufjan Stevens for "suf", Olivia Rodrigo/Dean for "olivia") —
    /// the exact same data the Apple Music app uses while typing.
    /// Failures and cancellations collapse to `nil` so the caller can
    /// still present the full-search tail.
    private static func fetchSuggestions(term: String, limit: Int) async -> MusicCatalogSearchSuggestionsResponse? {
        var request = MusicCatalogSearchSuggestionsRequest(
            term: term,
            includingTopResultsOfTypes: [MusicKit.Song.self, MusicKit.Artist.self, MusicKit.Album.self]
        )
        request.limit = limit
        do {
            return try await request.response()
        } catch is CancellationError {
            return nil
        } catch {
            if (error as NSError).code == NSURLErrorCancelled { return nil }
            print("[AppleMusicSearch] suggestions error for '\(term)': \(error)")
            return nil
        }
    }

    /// The deeper, literal-match catalog search — same endpoint we've
    /// been using. Used here only to pad the per-tab lists below the
    /// typeahead results. Same failure/cancellation contract as
    /// `fetchSuggestions`.
    private static func fetchFullSearch(term: String, limit: Int) async -> MusicCatalogSearchResponse? {
        var request = MusicCatalogSearchRequest(
            term: term,
            types: [MusicKit.Song.self, MusicKit.Artist.self, MusicKit.Album.self]
        )
        request.limit = limit
        do {
            return try await request.response()
        } catch is CancellationError {
            return nil
        } catch {
            if (error as NSError).code == NSURLErrorCancelled { return nil }
            print("[AppleMusicSearch] full search error for '\(term)': \(error)")
            return nil
        }
    }

    /// Concatenates `primary` with the items from `fallback` whose id
    /// isn't already present in `primary`. Preserves primary ordering —
    /// Apple's typeahead ranking wins on overlaps.
    private static func mergeDedupe<T>(
        primary: [T],
        fallback: [T],
        id: KeyPath<T, String>
    ) -> [T] {
        var seen = Set<String>(primary.map { $0[keyPath: id] })
        var merged = primary
        for item in fallback {
            let key = item[keyPath: id]
            if seen.insert(key).inserted {
                merged.append(item)
            }
        }
        return merged
    }

    // MARK: - Artist details

    /// MusicKit-backed artist page data: canonical `artistName` (pulled
    /// straight off the Artist resource — no deriving from a track row),
    /// `topSongs` as ranked by Apple Music itself, and the full album
    /// discography. This is the same data the Apple Music app shows
    /// when you open an artist page.
    ///
    /// Returns `nil` when MusicKit isn't authorized or the resource
    /// request fails, so the caller can fall back to iTunes `/lookup`.
    ///
    /// - Parameter artistId: MusicKit `Artist.id.rawValue` (identical to
    ///   the iTunes `artistId` numeric string for the vast majority of
    ///   catalog artists; MusicKit search already hands us this value).
    func fetchArtistDetails(artistId: String) async -> ArtistDetails? {
        let status = await currentAuthorizationStatus()
        guard status == .authorized else { return nil }

        do {
            let request = MusicCatalogResourceRequest<MusicKit.Artist>(
                matching: \.id,
                equalTo: MusicItemID(artistId)
            )
            let response = try await request.response()
            guard let baseArtist = response.items.first else { return nil }
            // `.with([.topSongs, .albums])` triggers the relationship
            // fetch so `baseArtist.topSongs` / `baseArtist.albums` are
            // populated. Without this both come back nil.
            let detailed = try await baseArtist.with([.topSongs, .albums])

            let topSongs: [Song] = (detailed.topSongs ?? []).map { Self.mapArtistTopSong($0, fallbackArtistId: artistId) }
            let albumsRaw: [Album] = (detailed.albums ?? []).map(Self.mapAlbum(_:))
            let albums = Self.dedupeAlbums(albumsRaw)

            return ArtistDetails(
                artistId: artistId,
                artistName: detailed.name,
                topTracks: topSongs,
                albums: albums
            )
        } catch is CancellationError {
            return nil
        } catch {
            if (error as NSError).code == NSURLErrorCancelled { return nil }
            print("[AppleMusicSearch] artist details error for '\(artistId)': \(error)")
            return nil
        }
    }

    // MARK: - Mapping

    /// Variant of `mapSong` used for the top-songs list on the artist
    /// page. Unlike the search variant, there's no cross-result
    /// `artistIdByName` table to consult, so we pin the song to the
    /// page's artistId — good enough for the only tap target inside
    /// the Popular list (the row itself opens `SongActionSheet`).
    private static func mapArtistTopSong(_ song: MusicKit.Song, fallbackArtistId: String) -> Song {
        let artwork600 = song.artwork?.url(width: 600, height: 600)?.absoluteString ?? ""
        let durationString: String = {
            guard let seconds = song.duration, seconds.isFinite, seconds > 0 else { return "" }
            let total = Int(seconds.rounded())
            let m = total / 60
            let s = total % 60
            return "\(m):\(String(format: "%02d", s))"
        }()
        let preview = song.previewAssets?.first?.url?.absoluteString
        let appleURL = song.url?.absoluteString

        return Song(
            id: song.id.rawValue,
            title: song.title,
            artist: song.artistName,
            albumArtURL: artwork600,
            duration: durationString,
            previewURL: preview,
            appleMusicURL: appleURL,
            artistId: fallbackArtistId,
            albumId: nil
        )
    }

    /// Conservative near-dup collapse for MusicKit album relationships:
    /// MusicKit can return multiple editions of the same record (deluxe
    /// / explicit / storefront variants) that all share a name+year.
    /// Groups by normalized (name, year) and keeps the one with the
    /// highest trackCount; tiebreaks on earliest release year. Matches
    /// the behavior we had on the iTunes path so the grid doesn't
    /// double up.
    private static func dedupeAlbums(_ albums: [Album]) -> [Album] {
        var groups: [String: Album] = [:]
        for album in albums {
            let nameKey = album.name
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let key = "\(nameKey)|\(album.releaseYear ?? "")"
            if let existing = groups[key] {
                let e = existing.trackCount ?? 0
                let c = album.trackCount ?? 0
                if c > e {
                    groups[key] = album
                } else if c == e, (album.releaseYear ?? "") < (existing.releaseYear ?? "") {
                    groups[key] = album
                }
            } else {
                groups[key] = album
            }
        }
        return groups.values.sorted { (a, b) in
            (a.releaseYear ?? "") > (b.releaseYear ?? "")
        }
    }

    private static func mapSong(_ song: MusicKit.Song, artistIdByName: [String: String]) -> Song {
        let artwork600 = song.artwork?.url(width: 600, height: 600)?.absoluteString ?? ""
        let durationString: String = {
            guard let seconds = song.duration, seconds.isFinite, seconds > 0 else { return "" }
            let total = Int(seconds.rounded())
            let m = total / 60
            let s = total % 60
            return "\(m):\(String(format: "%02d", s))"
        }()
        let preview = song.previewAssets?.first?.url?.absoluteString
        let appleURL = song.url?.absoluteString
        let resolvedArtistId = artistIdByName[normalize(song.artistName)]

        return Song(
            id: song.id.rawValue,
            title: song.title,
            artist: song.artistName,
            albumArtURL: artwork600,
            duration: durationString,
            previewURL: preview,
            appleMusicURL: appleURL,
            artistId: resolvedArtistId,
            albumId: nil
        )
    }

    private static func mapArtist(_ artist: MusicKit.Artist) -> ArtistSummary {
        let imageURL = artist.artwork?.url(width: 600, height: 600)?.absoluteString
        return ArtistSummary(
            id: artist.id.rawValue,
            name: artist.name,
            primaryGenre: artist.genreNames?.first,
            imageURL: imageURL
        )
    }

    private static func mapAlbum(_ album: MusicKit.Album) -> Album {
        let artwork = album.artwork?.url(width: 600, height: 600)?.absoluteString ?? ""
        let year: String? = {
            guard let date = album.releaseDate else { return nil }
            let cal = Calendar(identifier: .gregorian)
            return String(cal.component(.year, from: date))
        }()
        return Album(
            id: album.id.rawValue,
            name: album.title,
            artworkURL: artwork,
            releaseYear: year,
            trackCount: album.trackCount,
            primaryGenre: album.genreNames.first,
            artistName: album.artistName
        )
    }

    /// True when the first artist looks like a direct match for the
    /// query — used to promote the artist to "top hit" ahead of the top
    /// song. Treats the query as a name match if the artist name equals
    /// the query (normalized), starts with the query, or any of the
    /// artist's name tokens starts with the query. Keeps us from
    /// pinning a random artist as top hit for a generic song-title query
    /// like "bohemian rhapsody."
    private static func queryMatchesArtistName(_ query: String, artist: ArtistSummary) -> Bool {
        let nq = normalize(query)
        guard !nq.isEmpty else { return false }
        let name = normalize(artist.name)
        if name == nq { return true }
        if name.hasPrefix(nq) { return true }
        let tokens = name.split(separator: " ")
        return tokens.contains { $0.hasPrefix(nq) }
    }

    private static func normalize(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
    }

    private func normalize(_ s: String) -> String { Self.normalize(s) }
}

/// Transport-layer bundle returned by `AppleMusicSearchService.search`.
/// `authStatus` lets views surface a Settings deep link when MusicKit is
/// denied without having to query `MusicAuthorization.currentStatus`
/// separately.
struct AppleMusicSearchResults: Sendable {
    let songs: [Song]
    let artists: [ArtistSummary]
    let albums: [Album]
    let topHit: SearchResults.TopHit?
    let authStatus: MusicAuthorization.Status

    static let empty = AppleMusicSearchResults(
        songs: [], artists: [], albums: [],
        topHit: nil,
        authStatus: .notDetermined
    )
}
