import Foundation
import MusicKit

/// Apple Music catalog search and artist-details, served from the
/// `api.music.apple.com` HTTP API with a developer-only JWT (minted by
/// `AppleMusicTokenService` via the `getMusicKitDeveloperToken` Cloud
/// Function). Returns songs/artists/albums pre-ranked by Apple's own
/// relevance model — the same data the Apple Music app uses.
///
/// Why HTTP instead of the iOS MusicKit framework?
/// MusicKit's `MusicCatalogSearchRequest` / `MusicCatalogSearchSuggestionsRequest`
/// require `MusicAuthorization` to be `.authorized` even though the
/// underlying catalog is public. The HTTP API only needs a developer
/// token, so search and artist pages work for every user (Spotify-flow
/// included) without ever prompting for MusicKit access. The MusicKit
/// user prompt is reserved exclusively for the Apple Music personalization
/// step in `MusicServiceView`.
///
/// Used for in-app typeahead regardless of the user's preferred streaming
/// service; for playback we still route through `AudioPlayerService`
/// (30 s previews) and deep-link into the user's preferred service via
/// `resolveSpotifyURL`.
actor AppleMusicSearchService {
    static let shared = AppleMusicSearchService()

    /// Cached MusicKit user authorization status. Populated only by
    /// `requestUserAuthorizationForPersonalization()` /
    /// `refreshCachedAuthorizationStatus()` — never by search, which is
    /// authorization-free. Consumed by personalization surfaces that
    /// need to know whether the user has granted Apple Music access.
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

    // MARK: - User authorization (personalization only, never search)

    /// The only code path allowed to show Apple's Music permission sheet.
    /// Call this after the user explicitly chooses Apple Music
    /// personalization in onboarding — never for search, which uses the
    /// developer-only HTTP API and needs no user consent.
    func requestUserAuthorizationForPersonalization() async -> MusicAuthorization.Status {
        let requested = await MusicAuthorization.request()
        cachedAuthStatus = requested
        return requested
    }

    /// Populates `cachedAuthStatus` without prompting so personalization
    /// surfaces can cheaply inspect known denied/authorized state later.
    /// Fire-and-forget at app launch from `AppState.init()`.
    func refreshCachedAuthorizationStatus() async -> MusicAuthorization.Status {
        let current = MusicAuthorization.currentStatus
        cachedAuthStatus = current
        return current
    }

    // MARK: - Public search API

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

        let topResults = await Self.fetchSuggestions(term: trimmed, limit: 10)
        if Task.isCancelled { return .empty }

        // First pass: build a name → artistId map from the suggestion
        // batch. Used to back-populate `Song.artistId` so the byline on
        // a top-hit song row is tappable in the same response.
        var artistIdByName: [String: String] = [:]
        for top in topResults {
            if case .artist(let a) = top {
                let key = Self.normalize(a.attributes.name)
                if artistIdByName[key] == nil { artistIdByName[key] = a.id }
            }
        }

        var suggSongs: [Song] = []
        var suggArtists: [ArtistSummary] = []
        var suggAlbums: [Album] = []
        var suggTopHit: SearchResults.TopHit?

        for top in topResults {
            switch top {
            case .song(let resource):
                let mapped = Self.mapSong(resource, artistIdByName: artistIdByName)
                suggSongs.append(mapped)
                if suggTopHit == nil { suggTopHit = .song(mapped) }
            case .artist(let resource):
                let mapped = Self.mapArtist(resource)
                suggArtists.append(mapped)
                if suggTopHit == nil { suggTopHit = .artist(mapped) }
            case .album(let resource):
                let mapped = Self.mapAlbum(resource)
                suggAlbums.append(mapped)
                if suggTopHit == nil { suggTopHit = .album(mapped) }
            case .unknown:
                continue
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
            authStatus: .authorized
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

        let buckets = await Self.fetchFullSearch(term: trimmed, limit: min(max(limit, 1), 25))
        if Task.isCancelled { return .empty }

        var artistIdByName: [String: String] = [:]
        if let artists = buckets?.artists?.data {
            for artist in artists {
                let key = Self.normalize(artist.attributes.name)
                if artistIdByName[key] == nil { artistIdByName[key] = artist.id }
            }
        }

        let fullSongs: [Song] = buckets?.songs?.data
            .map { Self.mapSong($0, artistIdByName: artistIdByName) } ?? []
        let fullArtists: [ArtistSummary] = buckets?.artists?.data
            .map(Self.mapArtist(_:)) ?? []
        let fullAlbums: [Album] = buckets?.albums?.data
            .map(Self.mapAlbum(_:)) ?? []

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
            authStatus: .authorized
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

    // MARK: - HTTP request fan-out

    /// Apple's typeahead endpoint
    /// (`/v1/catalog/{sf}/search/suggestions?kinds=topResults&types=...`).
    /// Returns prefix-aware top results — the exact same data the Apple
    /// Music app uses while typing. Failures and cancellations collapse
    /// to an empty array so the caller can still present the full-search
    /// tail.
    private static func fetchSuggestions(term: String, limit: Int) async -> [AMTopResultContent] {
        guard let url = buildURL(
            path: "search/suggestions",
            query: [
                "term": term,
                "kinds": "topResults",
                "types": "songs,artists,albums",
                "limit": String(limit),
            ]
        ) else { return [] }

        guard let data = await authedGet(url) else { return [] }
        do {
            let decoded = try JSONDecoder().decode(AMSearchSuggestionsResponse.self, from: data)
            return decoded.results.suggestions?.compactMap { $0.content } ?? []
        } catch {
            print("[AppleMusicSearch] suggestions decode error for '\(term)': \(error)")
            return []
        }
    }

    /// The deeper, literal-match catalog search
    /// (`/v1/catalog/{sf}/search?term=...&types=...`). Used here only to
    /// pad the per-tab lists below the typeahead results. Same failure /
    /// cancellation contract as `fetchSuggestions`.
    private static func fetchFullSearch(term: String, limit: Int) async -> AMSearchResponse.Results? {
        guard let url = buildURL(
            path: "search",
            query: [
                "term": term,
                "types": "songs,artists,albums",
                "limit": String(limit),
            ]
        ) else { return nil }

        guard let data = await authedGet(url) else { return nil }
        do {
            return try JSONDecoder().decode(AMSearchResponse.self, from: data).results
        } catch {
            print("[AppleMusicSearch] full search decode error for '\(term)': \(error)")
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

    // MARK: - Single-song lookup (Shazam, deep links, etc.)

    /// Resolves a single `Song` from any combination of identifiers that
    /// `ShazamMatchService` (or other callers) may have. Tries in order:
    /// 1. `/v1/catalog/{sf}/songs/{appleMusicID}` — most reliable when
    ///    the upstream gives us a canonical Apple Music id.
    /// 2. `/v1/catalog/{sf}/songs?filter[isrc]={isrc}` — fallback used
    ///    when the matched media item lacks an Apple Music id (rare,
    ///    but happens for older catalog entries / regional gaps).
    /// 3. `searchExpanded(term: "title artist", limit: 1)` — last-ditch
    ///    full-text search so we never strand the user without a tappable
    ///    result.
    ///
    /// Returns `nil` only if all three paths fail (no auth/network, or
    /// the track is genuinely missing from this storefront).
    func lookupSong(
        appleMusicID: String?,
        isrc: String?,
        title: String,
        artist: String
    ) async -> Song? {
        if let appleMusicID, !appleMusicID.isEmpty,
           let resource = await Self.fetchSongByID(appleMusicID) {
            return Self.mapSong(resource, artistIdByName: [:])
        }
        if let isrc, !isrc.isEmpty,
           let resource = await Self.fetchSongByISRC(isrc) {
            return Self.mapSong(resource, artistIdByName: [:])
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let searchTerm = [trimmedTitle, trimmedArtist]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !searchTerm.isEmpty else { return nil }

        let fallback = await searchExpanded(term: searchTerm, limit: 1)
        return fallback.songs.first
    }

    /// `GET /v1/catalog/{sf}/songs/{id}` — typed Apple-Music song resource.
    private static func fetchSongByID(_ id: String) async -> AMSongResource? {
        guard let url = buildURL(path: "songs/\(id)", query: [:]) else { return nil }
        guard let data = await authedGet(url) else { return nil }
        do {
            let decoded = try JSONDecoder().decode(AMSongLookupResponse.self, from: data)
            return decoded.data.first
        } catch {
            print("[AppleMusicSearch] song-by-id decode error for '\(id)': \(error)")
            return nil
        }
    }

    /// `GET /v1/catalog/{sf}/songs?filter[isrc]={isrc}` — first match wins.
    private static func fetchSongByISRC(_ isrc: String) async -> AMSongResource? {
        guard let url = buildURL(
            path: "songs",
            query: ["filter[isrc]": isrc]
        ) else { return nil }
        guard let data = await authedGet(url) else { return nil }
        do {
            let decoded = try JSONDecoder().decode(AMSongLookupResponse.self, from: data)
            return decoded.data.first
        } catch {
            print("[AppleMusicSearch] song-by-isrc decode error for '\(isrc)': \(error)")
            return nil
        }
    }

    // MARK: - Artist id resolution

    /// Resolves a MusicKit artist id for a free-form artist name. Used
    /// when a song was ingested before we started storing `artistId`
    /// alongside shares — tapping the artist byline on that legacy
    /// card should still route to the artist page, so we fall back to
    /// a catalog search at tap time.
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

    /// Catalog-backed artist page data: canonical `artistName` (pulled
    /// straight off the Artist resource — no deriving from a track row),
    /// `topSongs` as ranked by Apple Music itself, and the full album
    /// discography. This is the same data the Apple Music app shows
    /// when you open an artist page.
    ///
    /// Returns `nil` when the catalog request fails, so the caller can
    /// fall back to iTunes `/lookup`.
    ///
    /// - Parameter artistId: Apple Music catalog artist id (identical
    ///   to the iTunes `artistId` numeric string for the vast majority
    ///   of catalog artists; search already hands us this value).
    func fetchArtistDetails(artistId: String) async -> ArtistDetails? {
        let trimmed = artistId.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        guard let artist = await Self.fetchArtistDetailsRemote(artistId: trimmed) else {
            return nil
        }

        let topSongs: [Song] = (artist.views?.topSongs?.data ?? [])
            .map { Self.mapArtistTopSong($0, fallbackArtistId: trimmed) }
        let albumsRaw: [Album] = {
            let primary = artist.views?.fullAlbums?.data ?? []
            if !primary.isEmpty { return primary.map(Self.mapAlbum(_:)) }
            return (artist.views?.featuredAlbums?.data ?? []).map(Self.mapAlbum(_:))
        }()
        let albums = Self.dedupeAlbums(albumsRaw)

        return ArtistDetails(
            artistId: trimmed,
            artistName: artist.attributes.name,
            topTracks: topSongs,
            albums: albums
        )
    }

    /// Per-artist `?views=top-songs,full-albums` endpoint. Returns the
    /// full artist resource with `top-songs` and `full-albums` view data
    /// inline so consumers don't have to fan out to per-view endpoints.
    private static func fetchArtistDetailsRemote(artistId: String) async -> AMArtistDetailsResponse.Artist? {
        guard let url = buildURL(
            path: "artists/\(artistId)",
            query: [
                "views": "top-songs,full-albums,featured-albums",
                "extend": "artistBio",
                "limit[artists:top-songs]": "20",
                "limit[artists:full-albums]": "50",
            ]
        ) else { return nil }

        guard let data = await authedGet(url) else { return nil }
        do {
            let decoded = try JSONDecoder().decode(AMArtistDetailsResponse.self, from: data)
            return decoded.data.first
        } catch {
            print("[AppleMusicSearch] artist details decode error for '\(artistId)': \(error)")
            return nil
        }
    }

    // MARK: - Authenticated HTTP helper

    /// Authenticated GET against `api.music.apple.com`. Mints/refreshes
    /// the JWT transparently via `AppleMusicTokenService` and retries
    /// once on 401 (after force-refresh) so a stale or rotated token
    /// recovers without surfacing an empty result. Returns `nil` on
    /// network failure, cancellation, or final non-2xx response.
    private static func authedGet(_ url: URL) async -> Data? {
        if Task.isCancelled { return nil }

        let firstAttempt: Data?
        do {
            let token = try await AppleMusicTokenService.shared.token()
            firstAttempt = try await rawGet(url: url, bearer: token)
        } catch is CancellationError {
            return nil
        } catch RetryableHTTPError.unauthorized {
            firstAttempt = nil
        } catch {
            print("[AppleMusicSearch] HTTP error for \(url.path): \(error)")
            return nil
        }
        if let data = firstAttempt { return data }

        if Task.isCancelled { return nil }

        // First attempt was 401. Force a fresh token and retry once.
        do {
            let token = try await AppleMusicTokenService.shared.forceRefresh()
            return try await rawGet(url: url, bearer: token)
        } catch is CancellationError {
            return nil
        } catch RetryableHTTPError.unauthorized {
            print("[AppleMusicSearch] 401 after force-refresh for \(url.path); giving up")
            return nil
        } catch {
            print("[AppleMusicSearch] retry error for \(url.path): \(error)")
            return nil
        }
    }

    /// Retryable HTTP outcomes lifted to typed errors so `authedGet`
    /// can branch cleanly on 401 (force-refresh-and-retry) without
    /// inspecting status codes from inside the do/catch.
    private enum RetryableHTTPError: Error { case unauthorized }

    /// Single round-trip: GET with `Authorization: Bearer …`. Returns
    /// `Data` on 2xx, throws `RetryableHTTPError.unauthorized` on 401,
    /// returns `nil`-equivalent (throws a generic error) on every other
    /// non-2xx so the caller can decide.
    private static func rawGet(url: URL, bearer: String) async throws -> Data? {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 15
        req.cachePolicy = .useProtocolCachePolicy

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else { return nil }
            switch http.statusCode {
            case 200..<300:
                return data
            case 401:
                throw RetryableHTTPError.unauthorized
            default:
                let body = String(data: data, encoding: .utf8).map { String($0.prefix(200)) } ?? ""
                print("[AppleMusicSearch] HTTP \(http.statusCode) for \(url.path) body=\(body)")
                return nil
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if (error as NSError).code == NSURLErrorCancelled { throw CancellationError() }
            throw error
        }
    }

    /// Builds a fully-qualified URL against
    /// `https://api.music.apple.com/v1/catalog/{storefront}/{path}` with
    /// percent-encoded query params. Centralized here so every endpoint
    /// gets identical storefront resolution.
    private static func buildURL(path: String, query: [String: String]) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.music.apple.com"
        components.path = "/v1/catalog/\(storefront())/\(path)"
        components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components.url
    }

    /// Storefront slug (`us`, `gb`, `jp`, ...) used in every catalog
    /// URL. Apple Music requires it; MusicKit framework was hiding this
    /// behind `MusicAuthorization`. We derive it from the device locale
    /// — the catalog you read from doesn't have to match the user's
    /// Apple Music subscription region, just be a valid storefront.
    private static func storefront() -> String {
        let region = Locale.current.region?.identifier ?? "US"
        let normalized = region.lowercased()
        return normalized.isEmpty ? "us" : normalized
    }

    // MARK: - Mapping

    /// Variant of `mapSong` used for the top-songs list on the artist
    /// page. Unlike the search variant, there's no cross-result
    /// `artistIdByName` table to consult, so we pin the song to the
    /// page's artistId — good enough for the only tap target inside
    /// the Popular list (the row itself opens `SongActionSheet`).
    private static func mapArtistTopSong(_ resource: AMSongResource, fallbackArtistId: String) -> Song {
        let attrs = resource.attributes
        let artwork600 = attrs.artwork?.resolvedURL(width: 600, height: 600) ?? ""
        let durationString = formatDuration(millis: attrs.durationInMillis)
        let preview = attrs.previews?.first?.url
        let appleURL = attrs.url

        return Song(
            id: resource.id,
            title: attrs.name,
            artist: attrs.artistName,
            albumArtURL: artwork600,
            duration: durationString,
            previewURL: preview,
            appleMusicURL: appleURL,
            artistId: fallbackArtistId,
            albumId: nil
        )
    }

    /// Conservative near-dup collapse for catalog album relationships:
    /// Apple Music can return multiple editions of the same record
    /// (deluxe / explicit / storefront variants) that all share a
    /// name+year. Groups by normalized (name, year) and keeps the one
    /// with the highest trackCount; tiebreaks on earliest release year.
    /// Matches the behavior we had on the iTunes path so the grid
    /// doesn't double up.
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

    private static func mapSong(_ resource: AMSongResource, artistIdByName: [String: String]) -> Song {
        let attrs = resource.attributes
        let artwork600 = attrs.artwork?.resolvedURL(width: 600, height: 600) ?? ""
        let durationString = formatDuration(millis: attrs.durationInMillis)
        let preview = attrs.previews?.first?.url
        let appleURL = attrs.url
        let resolvedArtistId = artistIdByName[normalize(attrs.artistName)]

        return Song(
            id: resource.id,
            title: attrs.name,
            artist: attrs.artistName,
            albumArtURL: artwork600,
            duration: durationString,
            previewURL: preview,
            appleMusicURL: appleURL,
            artistId: resolvedArtistId,
            albumId: nil
        )
    }

    private static func mapArtist(_ resource: AMArtistResource) -> ArtistSummary {
        let attrs = resource.attributes
        let imageURL = attrs.artwork?.resolvedURL(width: 600, height: 600)
        return ArtistSummary(
            id: resource.id,
            name: attrs.name,
            primaryGenre: attrs.genreNames?.first,
            imageURL: imageURL
        )
    }

    private static func mapAlbum(_ resource: AMAlbumResource) -> Album {
        let attrs = resource.attributes
        let artwork = attrs.artwork?.resolvedURL(width: 600, height: 600) ?? ""
        let year = attrs.releaseDate.flatMap { String($0.prefix(4)) }
        return Album(
            id: resource.id,
            name: attrs.name,
            artworkURL: artwork,
            releaseYear: year,
            trackCount: attrs.trackCount,
            primaryGenre: attrs.genreNames?.first,
            artistName: attrs.artistName
        )
    }

    /// Formats an Apple Music `durationInMillis` payload as `m:ss`.
    /// Returns an empty string when duration is missing or zero — same
    /// contract as the old MusicKit path so empty-string callers keep
    /// the same UI.
    private static func formatDuration(millis: Int?) -> String {
        guard let ms = millis, ms > 0 else { return "" }
        let total = ms / 1000
        let m = total / 60
        let s = total % 60
        return "\(m):\(String(format: "%02d", s))"
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
/// `authStatus` is preserved as a compile-compat shim — search no longer
/// gates on `MusicAuthorization`, so this is always `.authorized`. The
/// real personalization status lives on `AppState.musicAuthStatus` and
/// is populated by `MusicServiceView` / `refreshCachedAuthorizationStatus`,
/// not by search responses.
struct AppleMusicSearchResults: Sendable {
    let songs: [Song]
    let artists: [ArtistSummary]
    let albums: [Album]
    let topHit: SearchResults.TopHit?
    let authStatus: MusicAuthorization.Status

    static let empty = AppleMusicSearchResults(
        songs: [], artists: [], albums: [],
        topHit: nil,
        authStatus: .authorized
    )
}
