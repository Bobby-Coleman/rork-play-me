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
/// An active Apple Music subscription is *not* required. Catalog search is
/// intentionally non-prompting; user MusicKit authorization is reserved for
/// Apple Music personalization.
actor AppleMusicSearchService {
    static let shared = AppleMusicSearchService()

    /// Cached authorization status. Reads never prompt; only
    /// `requestUserAuthorizationForPersonalization()` can show Apple's sheet.
    private var cachedAuthStatus: MusicAuthorization.Status?

    /// Per-query LRU result cache. Stores the typeahead and expanded
    /// payloads independently because the two-phase pipeline issues them
    /// on separate trips — phase 2's expanded fetch should hit the cache
    /// even if phase 1 was a fresh network round-trip a few hundred ms
    /// earlier. Cache is in-memory only; search responses change too
    /// often for disk persistence to be worth it, and 60 s is a generous
    /// ceiling for "typo + backspace + retype the same query."
    private struct CachedSearch {
        var typeahead: AppleMusicSearchResults?
        var expanded: AppleMusicSearchResults?
        var storedAt: Date
    }
    private var resultCache: [String: CachedSearch] = [:]
    /// Maintains LRU recency. The most-recently-touched key is at the
    /// end; on overflow we evict from the front.
    private var cacheOrder: [String] = []
    private let cacheTTL: TimeInterval = 60
    private let cacheCap: Int = 50

    /// Returns the current MusicKit authorization status without prompting.
    /// Safe for launch/search hot paths.
    func authorizationStatus() async -> MusicAuthorization.Status {
        if let cached = cachedAuthStatus { return cached }
        let current = MusicAuthorization.currentStatus
        cachedAuthStatus = current
        return current
    }

    /// The only code path allowed to show Apple's Music permission sheet.
    /// Call this after the user explicitly chooses Apple Music
    /// personalization, never for search.
    func requestUserAuthorizationForPersonalization() async -> MusicAuthorization.Status {
        let requested = await MusicAuthorization.request()
        cachedAuthStatus = requested
        return requested
    }

    /// Populates `cachedAuthStatus` without prompting so search views can
    /// cheaply inspect known denied/authorized state later.
    func refreshCachedAuthorizationStatus() async -> MusicAuthorization.Status {
        let current = MusicAuthorization.currentStatus
        cachedAuthStatus = current
        return current
    }

    /// Phase 1 of the two-phase search pipeline: Apple's typeahead
    /// endpoint only. Returns prefix-aware top results — the same data
    /// the Apple Music app shows above its autocomplete list — and is
    /// what the user sees first. Cheap on Apple's side and what makes
    /// the UI feel "instant."
    ///
    /// Cancellation-safe (returns `.empty` without writing to cache) and
    /// LRU-cached for `cacheTTL` seconds, so a backspace/retype within
    /// the window doesn't fire another request.
    func searchTypeahead(term: String) async -> AppleMusicSearchResults {
        let trimmed = term.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return .empty }
        let key = Self.normalize(trimmed)

        if let hit = cacheRead(key: key)?.typeahead {
            return hit
        }

        let status = await authorizationStatus()

        let suggestionsResp = await Self.fetchSuggestions(term: trimmed, limit: 10)
        if Task.isCancelled { return .empty }

        var artistIdByName: [String: String] = [:]
        if let s = suggestionsResp {
            for top in s.topResults {
                if case .artist(let a) = top {
                    let key = Self.normalize(a.name)
                    if artistIdByName[key] == nil { artistIdByName[key] = a.id.rawValue }
                }
            }
        }

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

        let topHit: SearchResults.TopHit? = {
            if let hit = suggTopHit { return hit }
            if let artist = suggArtists.first,
               Self.queryMatchesArtistName(trimmed, artist: artist) {
                return .artist(artist)
            }
            if let song = suggSongs.first { return .song(song) }
            if let artist = suggArtists.first { return .artist(artist) }
            if let album = suggAlbums.first { return .album(album) }
            return nil
        }()

        let result = AppleMusicSearchResults(
            songs: suggSongs,
            artists: suggArtists,
            albums: suggAlbums,
            topHit: topHit,
            authStatus: status
        )
        cacheWrite(key: key, typeahead: result)
        return result
    }

    /// Phase 2 of the two-phase search pipeline: the deeper full-catalog
    /// search. Used to pad each per-type bucket beyond what Apple's
    /// typeahead returns; merged by id on top of the typeahead payload
    /// in `AppState.searchSongs` so the per-tab lists ("Songs",
    /// "Albums", "Artists") feel complete.
    ///
    /// Lower default limit (12 vs. the old unified 25) since this only
    /// pads the tail and the user almost always taps something in the
    /// first few rows. Cancellation-safe and LRU-cached.
    func searchExpanded(term: String, limit: Int = 12) async -> AppleMusicSearchResults {
        let trimmed = term.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return .empty }
        let key = Self.normalize(trimmed)

        if let hit = cacheRead(key: key)?.expanded {
            return hit
        }

        let status = await authorizationStatus()

        let fullResp = await Self.fetchFullSearch(term: trimmed, limit: min(max(limit, 1), 25))
        if Task.isCancelled { return .empty }

        var artistIdByName: [String: String] = [:]
        if let f = fullResp {
            for artist in f.artists {
                let key = Self.normalize(artist.name)
                if artistIdByName[key] == nil { artistIdByName[key] = artist.id.rawValue }
            }
        }

        let fullSongs: [Song] = fullResp?.songs.map { Self.mapSong($0, artistIdByName: artistIdByName) } ?? []
        let fullArtists: [ArtistSummary] = fullResp?.artists.map(Self.mapArtist(_:)) ?? []
        let fullAlbums: [Album] = fullResp?.albums.map(Self.mapAlbum(_:)) ?? []

        // Phase 2 is rarely used as the only payload (typeahead almost
        // always returns first), so a permissive heuristic is fine for
        // the standalone topHit.
        let topHit: SearchResults.TopHit? = {
            if let artist = fullArtists.first,
               Self.queryMatchesArtistName(trimmed, artist: artist) {
                return .artist(artist)
            }
            if let song = fullSongs.first { return .song(song) }
            if let artist = fullArtists.first { return .artist(artist) }
            if let album = fullAlbums.first { return .album(album) }
            return nil
        }()

        let result = AppleMusicSearchResults(
            songs: fullSongs,
            artists: fullArtists,
            albums: fullAlbums,
            topHit: topHit,
            authStatus: status
        )
        cacheWrite(key: key, expanded: result)
        return result
    }

    // MARK: - LRU cache helpers

    /// Returns the cached entry if still within `cacheTTL` and refreshes
    /// recency. Stale entries are evicted lazily on read.
    private func cacheRead(key: String) -> CachedSearch? {
        guard let entry = resultCache[key] else { return nil }
        if Date().timeIntervalSince(entry.storedAt) > cacheTTL {
            resultCache.removeValue(forKey: key)
            cacheOrder.removeAll { $0 == key }
            return nil
        }
        if let idx = cacheOrder.firstIndex(of: key) {
            cacheOrder.remove(at: idx)
        }
        cacheOrder.append(key)
        return entry
    }

    /// Writes one half of the cached payload (typeahead or expanded),
    /// preserving the other half if it was already there. Touches LRU
    /// recency and evicts the least-recently-used key when over cap.
    private func cacheWrite(
        key: String,
        typeahead: AppleMusicSearchResults? = nil,
        expanded: AppleMusicSearchResults? = nil
    ) {
        var entry = resultCache[key] ?? CachedSearch(typeahead: nil, expanded: nil, storedAt: Date())
        if let t = typeahead { entry.typeahead = t }
        if let e = expanded { entry.expanded = e }
        entry.storedAt = Date()
        resultCache[key] = entry

        if let idx = cacheOrder.firstIndex(of: key) {
            cacheOrder.remove(at: idx)
        }
        cacheOrder.append(key)

        while cacheOrder.count > cacheCap, let evict = cacheOrder.first {
            cacheOrder.removeFirst()
            resultCache.removeValue(forKey: evict)
        }
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
    /// Apple's typeahead ranking wins on overlaps. Public so
    /// `AppState.searchSongs` can merge the two-phase payloads after
    /// they each return.
    static func mergeDedupe<T>(
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

    // MARK: - Artist id resolution

    /// Resolves a MusicKit artist id for a free-form artist name. Used
    /// when a song was ingested before we started storing `artistId`
    /// alongside shares — tapping the artist byline on that legacy
    /// card should still route to the artist page, so we fall back to
    /// a MusicKit search at tap time.
    ///
    /// Prefers an exact case/diacritic-insensitive name match. Returns
    /// the first search hit when nothing matches exactly; returns nil
    /// on empty input or search failure.
    func resolveArtistId(name: String) async -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        async let typeaheadTask = searchTypeahead(term: trimmed)
        async let expandedTask = searchExpanded(term: trimmed, limit: 8)
        let (typeahead, expanded) = await (typeaheadTask, expandedTask)

        let merged = Self.mergeDedupe(
            primary: typeahead.artists,
            fallback: expanded.artists,
            id: \ArtistSummary.id
        )

        let normalizedQuery = Self.normalize(trimmed)
        if let exact = merged.first(where: {
            Self.normalize($0.name) == normalizedQuery
        }) {
            return exact.id
        }
        return merged.first?.id
    }

    // MARK: - Artist details

    /// MusicKit-backed artist page data: canonical `artistName` (pulled
    /// straight off the Artist resource — no deriving from a track row),
    /// `topSongs` as ranked by Apple Music itself, and the full album
    /// discography. This is the same data the Apple Music app shows
    /// when you open an artist page.
    ///
    /// Returns `nil` when the resource request fails, so the caller can fall
    /// back to iTunes `/lookup`.
    ///
    /// - Parameter artistId: MusicKit `Artist.id.rawValue` (identical to
    ///   the iTunes `artistId` numeric string for the vast majority of
    ///   catalog artists; MusicKit search already hands us this value).
    func fetchArtistDetails(artistId: String) async -> ArtistDetails? {
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
/// `authStatus` lets personalization surfaces react to a prior denial without
/// querying `MusicAuthorization.currentStatus` separately.
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
