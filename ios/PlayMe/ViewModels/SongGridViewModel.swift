import Foundation
import Observation

/// Owns the Discovery background grid dataset. Uses a three-tier pipeline so
/// the screen paints instantly and upgrades opportunistically:
///
///   1. Bundled seed (`MockSongGridProvider.samples`) — applied synchronously
///      on init so the very first frame of the view has real album art.
///   2. Persisted disk cache (`UserDefaults` JSON) — replayed on `.task`,
///      giving repeat users the last-known curated list without a network
///      round trip.
///   3. Remote curated list (`CuratedSongGridProvider` → Firestore doc
///      `curatedGrids/current`) — hydrates the grid with the freshest list
///      after launch. Failures are silent; the current in-memory list is
///      preserved.
///
/// Dedup is enforced at every tier. Upstream sources may contain duplicate
/// `albumArtURL`s (different song IDs pointing at the same cover); the view
/// layer reads `dedupedDisplayItems` which guarantees each cover appears
/// exactly once.
@Observable
@MainActor
final class SongGridViewModel {
    private(set) var items: [GridSong]
    private let provider: SongGridProvider
    private var hasLoaded = false

    /// UserDefaults key for the persisted curated cache.
    private static let cacheKey = "GridSong.CuratedCache.v1"

    init(provider: SongGridProvider = CuratedSongGridProvider()) {
        self.provider = provider
        let seed = MockSongGridProvider.samples
        self.items = Self.dedup(seed)
    }

    /// Convenience accessor the view layer should prefer. Always deduped,
    /// never empty (falls back to the seed).
    var dedupedDisplayItems: [GridSong] {
        let d = Self.dedup(items)
        return d.isEmpty ? Self.dedup(MockSongGridProvider.samples) : d
    }

    /// Kicks off a one-shot load: reads the on-disk cache first, then hits
    /// the remote provider. Safe to call repeatedly.
    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true

        if let cached = Self.readCache(), !cached.isEmpty {
            items = Self.dedup(cached)
        }

        do {
            let fetched = try await provider.load()
            let cleaned = Self.dedup(fetched)
            guard !cleaned.isEmpty else { return }
            items = cleaned
            Self.writeCache(cleaned)
        } catch {
            print("SongGridViewModel: provider failed, keeping current items — \(error.localizedDescription)")
        }
    }

    /// Returns a list duplicated enough times to contain at least `minimum`
    /// entries, preserving order. Grid rendering wraps items itself, so this
    /// is only useful in legacy callers; kept for compatibility.
    func looped(minimum: Int) -> [GridSong] {
        let base = dedupedDisplayItems
        guard !base.isEmpty else { return [] }
        guard base.count < minimum else { return base }
        var result: [GridSong] = []
        result.reserveCapacity(minimum)
        var loop = 0
        while result.count < minimum {
            for song in base {
                result.append(GridSong(
                    id: "\(song.id)#\(loop)",
                    albumArtURL: song.albumArtURL,
                    title: song.title,
                    artist: song.artist
                ))
                if result.count >= minimum { break }
            }
            loop += 1
        }
        return result
    }

    // MARK: - Helpers

    /// Filters the list so each `albumArtURL` appears at most once while
    /// preserving insertion order.
    private static func dedup(_ arr: [GridSong]) -> [GridSong] {
        var seen = Set<String>()
        seen.reserveCapacity(arr.count)
        return arr.filter { seen.insert($0.albumArtURL).inserted }
    }

    private static func readCache() -> [GridSong]? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return nil }
        return try? JSONDecoder().decode([GridSong].self, from: data)
    }

    private static func writeCache(_ items: [GridSong]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
    }
}
