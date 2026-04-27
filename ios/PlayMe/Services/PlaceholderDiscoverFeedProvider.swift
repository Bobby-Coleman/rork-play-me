import Foundation

/// First-cut `DiscoverFeedProvider` driven by Apple's free "Most Played /
/// Top Songs" RSS feed (the same source `ChartSongGridProvider` uses for
/// the ambient grid) hydrated with iTunes `/lookup` so each entry carries
/// the `previewURL`, `appleMusicURL`, `artistId`, and `albumId` we need
/// for the TikTok-style fullscreen feed's preview playback.
///
/// Wire shape:
/// 1. RSS feed → list of song IDs + arts + names.
/// 2. iTunes `/lookup?id=id1,id2,...&entity=song` → previewURL etc.
/// 3. Merge by id, preserve RSS ranking.
///
/// Both calls are cached (`URLCache.shared` for HTTP, `UserDefaults` for
/// the decoded `[Song]`) so repeat opens of the Home tab are instant.
/// First-paint after a cold launch reads the persisted list synchronously
/// before kicking off the network refresh.
///
/// `loadMore` is a no-op for v1 (the RSS feed already returns 100 items in
/// a single payload), but the signature is preserved so a future
/// `RecommendationsDiscoverFeedProvider` can paginate.
final class PlaceholderDiscoverFeedProvider: DiscoverFeedProvider {
    private static let feedURL = URL(string: "https://rss.applemarketingtools.com/api/v2/us/music/most-played/100/songs.json")!
    private static let lookupBase = "https://itunes.apple.com/lookup"

    private static let cacheKey = "DiscoverFeed.Placeholder.v1"
    private static let cacheTimestampKey = "DiscoverFeed.Placeholder.v1.timestamp"
    private static let cacheTTL: TimeInterval = 60 * 60 * 6

    /// iTunes `/lookup` accepts up to ~150 ids per request comfortably; we
    /// use 100 to match the RSS payload size.
    private static let lookupBatchSize = 100

    func loadInitial() async throws -> [Song] {
        if let cached = Self.readCache(), !cached.songs.isEmpty, cached.isFresh {
            return cached.songs
        }

        let songs = try await fetchAndHydrate()
        if !songs.isEmpty {
            Self.writeCache(songs)
        } else if let stale = Self.readCache(), !stale.songs.isEmpty {
            return stale.songs
        }
        return songs
    }

    func loadMore(after cursor: DiscoverCursor?) async throws -> (songs: [Song], next: DiscoverCursor?) {
        // Single-page provider for v1 — the RSS feed already returns the
        // full top-100 list. Returning `(empty, nil)` is the sentinel for
        // "no more pages". Caller should treat the result as end-of-feed
        // rather than a loading state.
        _ = cursor
        return (songs: [], next: nil)
    }

    /// Synchronous accessor for the on-disk cache. View code uses it to
    /// seed the grid before the network round-trip completes so first
    /// paint is instant after a cold launch.
    static func cachedSongs() -> [Song] {
        readCache()?.songs ?? []
    }

    // MARK: - Network

    private func fetchAndHydrate() async throws -> [Song] {
        var request = URLRequest(url: Self.feedURL)
        request.cachePolicy = .returnCacheDataElseLoad
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(AppleFeedResponse.self, from: data)
        let entries = decoded.feed.results
        guard !entries.isEmpty else { return [] }

        let ids = entries.map(\.id)
        let lookupMap = await Self.fetchLookupMap(ids: ids)

        // Preserve RSS ranking and skip entries the lookup didn't enrich
        // with a preview — without `previewURL` the fullscreen feed has
        // nothing to autoplay, which is the main reason the Discover tab
        // exists. Items missing a preview still render in the grid via
        // `Song.previewURL == nil` (the player tolerates it), but we
        // de-prioritize them by appending after the playable set so the
        // top of the grid is always autoplay-ready.
        var playable: [Song] = []
        var fallbacks: [Song] = []

        for entry in entries {
            let upgradedArt = entry.artworkUrl100.map(Self.upgradeArtwork) ?? ""
            if let hydrated = lookupMap[entry.id] {
                let song = Song(
                    id: entry.id,
                    title: hydrated.title ?? entry.name ?? "",
                    artist: hydrated.artist ?? entry.artistName ?? "",
                    albumArtURL: hydrated.albumArtURL.isEmpty ? upgradedArt : hydrated.albumArtURL,
                    duration: hydrated.duration,
                    previewURL: hydrated.previewURL,
                    appleMusicURL: hydrated.appleMusicURL,
                    artistId: hydrated.artistId,
                    albumId: hydrated.albumId
                )
                if song.previewURL != nil {
                    playable.append(song)
                } else {
                    fallbacks.append(song)
                }
            } else {
                let song = Song(
                    id: entry.id,
                    title: entry.name ?? "",
                    artist: entry.artistName ?? "",
                    albumArtURL: upgradedArt,
                    duration: ""
                )
                fallbacks.append(song)
            }
        }

        return playable + fallbacks
    }

    /// Batches iTunes `/lookup` calls. Returns a `[id: hydrated]` dict.
    /// Errors collapse to "no enrichment" rather than throwing so a
    /// transient lookup failure never erases the entire feed.
    private static func fetchLookupMap(ids: [String]) async -> [String: HydratedSong] {
        guard !ids.isEmpty else { return [:] }
        var batches: [[String]] = []
        for batchStart in stride(from: 0, to: ids.count, by: lookupBatchSize) {
            let end = min(batchStart + lookupBatchSize, ids.count)
            batches.append(Array(ids[batchStart..<end]))
        }

        var merged: [String: HydratedSong] = [:]
        await withTaskGroup(of: [String: HydratedSong].self) { group in
            for batch in batches {
                group.addTask {
                    await Self.fetchOneLookupBatch(ids: batch)
                }
            }
            for await partial in group {
                for (k, v) in partial { merged[k] = v }
            }
        }
        return merged
    }

    private static func fetchOneLookupBatch(ids: [String]) async -> [String: HydratedSong] {
        let joined = ids.joined(separator: ",")
        guard let url = URL(string: "\(lookupBase)?id=\(joined)&entity=song&limit=\(ids.count)") else {
            return [:]
        }

        do {
            var req = URLRequest(url: url)
            req.cachePolicy = .returnCacheDataElseLoad
            req.timeoutInterval = 15
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
                return [:]
            }
            let decoded = try JSONDecoder().decode(iTunesLookupResponse.self, from: data)
            var out: [String: HydratedSong] = [:]
            for item in decoded.results where item.wrapperType == "track" {
                guard let trackId = item.trackId else { continue }
                let key = String(trackId)
                let art100 = item.artworkUrl100 ?? item.collectionArtworkUrl100 ?? ""
                let art = art100.replacingOccurrences(of: "100x100", with: "600x600")
                let minutes = (item.trackTimeMillis ?? 0) / 1000 / 60
                let seconds = ((item.trackTimeMillis ?? 0) / 1000) % 60
                let duration = item.trackTimeMillis == nil ? "" : "\(minutes):\(String(format: "%02d", seconds))"
                out[key] = HydratedSong(
                    title: item.trackName,
                    artist: item.artistName,
                    albumArtURL: art,
                    duration: duration,
                    previewURL: item.previewUrl,
                    appleMusicURL: item.trackViewUrl,
                    artistId: item.artistId.map(String.init),
                    albumId: item.collectionId.map(String.init)
                )
            }
            return out
        } catch {
            return [:]
        }
    }

    private static func upgradeArtwork(_ url: String) -> String {
        url.replacingOccurrences(of: "100x100bb", with: "600x600bb")
    }

    // MARK: - Cache

    private struct Cached {
        let songs: [Song]
        let timestamp: Date
        var isFresh: Bool {
            Date().timeIntervalSince(timestamp) < PlaceholderDiscoverFeedProvider.cacheTTL
        }
    }

    private static func readCache() -> Cached? {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: cacheKey),
              let songs = try? JSONDecoder().decode([SongCacheRecord].self, from: data) else {
            return nil
        }
        let ts = Date(timeIntervalSince1970: defaults.double(forKey: cacheTimestampKey))
        return Cached(songs: songs.map(\.asSong), timestamp: ts)
    }

    private static func writeCache(_ songs: [Song]) {
        let defaults = UserDefaults.standard
        let payload = songs.map(SongCacheRecord.init(song:))
        if let data = try? JSONEncoder().encode(payload) {
            defaults.set(data, forKey: cacheKey)
            defaults.set(Date().timeIntervalSince1970, forKey: cacheTimestampKey)
        }
    }
}

// MARK: - Wire types

private struct AppleFeedResponse: Decodable {
    let feed: Feed
    struct Feed: Decodable { let results: [Entry] }
    struct Entry: Decodable {
        let id: String
        let name: String?
        let artistName: String?
        let artworkUrl100: String?
    }
}

private struct HydratedSong {
    let title: String?
    let artist: String?
    let albumArtURL: String
    let duration: String
    let previewURL: String?
    let appleMusicURL: String?
    let artistId: String?
    let albumId: String?
}

/// Persistence-friendly mirror of `Song`. `Song` itself is intentionally
/// `Hashable` but not `Codable` (the project ships several call sites that
/// would have to change otherwise), so we encode through this shadow type.
private struct SongCacheRecord: Codable {
    let id: String
    let title: String
    let artist: String
    let albumArtURL: String
    let duration: String
    let spotifyURI: String?
    let previewURL: String?
    let appleMusicURL: String?
    let artistId: String?
    let albumId: String?

    init(song: Song) {
        self.id = song.id
        self.title = song.title
        self.artist = song.artist
        self.albumArtURL = song.albumArtURL
        self.duration = song.duration
        self.spotifyURI = song.spotifyURI
        self.previewURL = song.previewURL
        self.appleMusicURL = song.appleMusicURL
        self.artistId = song.artistId
        self.albumId = song.albumId
    }

    var asSong: Song {
        Song(
            id: id,
            title: title,
            artist: artist,
            albumArtURL: albumArtURL,
            duration: duration,
            spotifyURI: spotifyURI,
            previewURL: previewURL,
            appleMusicURL: appleMusicURL,
            artistId: artistId,
            albumId: albumId
        )
    }
}
