import Foundation

/// Default `SongGridProvider` for the Discovery background grid.
///
/// Fetches Apple's free "Most Played / Top Songs" RSS JSON feed — no auth, no
/// key, stable schema. Results are cached in `URLCache.shared` (honors server
/// `Cache-Control` for up to 24h) and a decoded mirror is persisted in
/// `UserDefaults` so first paint after cold launch is instant even offline.
struct ChartSongGridProvider: SongGridProvider {
    /// Apple Marketing Tools top songs feed. `100/songs.json` is the default
    /// list; swap `songs` to `music-videos` or adjust the storefront code as
    /// needed in the future.
    private static let feedURL = URL(string: "https://rss.applemarketingtools.com/api/v2/us/music/most-played/100/songs.json")!

    private static let cacheKey = "GridSong.ChartCache.v1"
    private static let cacheTimestampKey = "GridSong.ChartCache.v1.timestamp"
    private static let cacheTTL: TimeInterval = 60 * 60 * 24

    func load() async throws -> [GridSong] {
        if let cached = Self.readCache(), !cached.items.isEmpty, cached.isFresh {
            return cached.items
        }

        var request = URLRequest(url: Self.feedURL)
        request.cachePolicy = .returnCacheDataElseLoad
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            if let cached = Self.readCache(), !cached.items.isEmpty { return cached.items }
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(AppleFeedResponse.self, from: data)
        let items = decoded.feed.results.map(GridSong.init(appleEntry:))
        Self.writeCache(items)
        return items
    }

    // MARK: - Cache

    private struct Cached {
        let items: [GridSong]
        let timestamp: Date
        var isFresh: Bool { Date().timeIntervalSince(timestamp) < ChartSongGridProvider.cacheTTL }
    }

    private static func readCache() -> Cached? {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: cacheKey),
              let items = try? JSONDecoder().decode([GridSong].self, from: data) else { return nil }
        let ts = Date(timeIntervalSince1970: defaults.double(forKey: cacheTimestampKey))
        return Cached(items: items, timestamp: ts)
    }

    private static func writeCache(_ items: [GridSong]) {
        let defaults = UserDefaults.standard
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: cacheKey)
            defaults.set(Date().timeIntervalSince1970, forKey: cacheTimestampKey)
        }
    }

    /// Synchronous cache accessor used by `SongGridViewModel` to seed UI
    /// before the network round-trip completes.
    static func cachedItems() -> [GridSong] {
        readCache()?.items ?? []
    }
}

// MARK: - Apple feed decoding

private struct AppleFeedResponse: Decodable {
    let feed: Feed

    struct Feed: Decodable {
        let results: [Entry]
    }

    struct Entry: Decodable {
        let id: String
        let name: String?
        let artistName: String?
        let artworkUrl100: String?
    }
}

private extension GridSong {
    init(appleEntry entry: AppleFeedResponse.Entry) {
        let upgraded = entry.artworkUrl100.map(GridSong.upgradeArtwork) ?? ""
        self.init(id: entry.id, albumArtURL: upgraded, title: entry.name, artist: entry.artistName)
    }

    /// Swaps Apple's default `100x100bb.jpg` suffix for a crisper 600x600 that
    /// looks sharp on retina without the blur of the default thumbnail.
    static func upgradeArtwork(_ url: String) -> String {
        url.replacingOccurrences(of: "100x100bb", with: "600x600bb")
    }
}
