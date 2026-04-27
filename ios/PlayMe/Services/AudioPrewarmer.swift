import Foundation
import AVFoundation

/// Pool of pre-loaded `AVPlayerItem`s so swiping between songs in the
/// fullscreen feed feels near-instant.
///
/// How it works:
/// - The fullscreen feed calls `prewarm(songs:)` whenever the visible
///   song changes, passing the upcoming neighbors (typically `N+1`,
///   `N+2`, `N-1`).
/// - For each song with a `previewURL` not already in the pool, we
///   build an `AVURLAsset` and immediately call
///   `loadValuesAsynchronously(forKeys: ["playable", "duration"])` —
///   this is the actual fetch trigger that gets the first segment of
///   audio resident in memory before the user swipes.
/// - We wrap the asset in an `AVPlayerItem` (with a small forward
///   buffer) and store it keyed by `song.id`.
/// - `AudioPlayerService.playViaAVPlayer` calls `consume(songId:)`
///   before falling back to `AVPlayerItem(url:)` — so a prewarmed item
///   is picked up automatically and its initial buffer is already
///   resident, meaning `.readyToPlay` fires within a frame or two
///   instead of after a network round-trip.
///
/// `AVPlayerItem` instances can only be attached to one `AVPlayer` at
/// a time, so `consume` is one-shot: it removes the item from the
/// pool. The pool is bounded (LRU at 5) so we never hold more than a
/// few megabytes of audio in memory, and `clearAll()` is called when
/// the fullscreen feed dismisses so we don't carry that cost into
/// other surfaces.
@Observable
@MainActor
final class AudioPrewarmer {
    static let shared = AudioPrewarmer()

    /// Cap the pool so memory stays bounded. With 30-second iTunes
    /// previews this is roughly 5 × ~1 MB peak on the high end — well
    /// under any reasonable budget.
    private let maxItems = 5

    /// Insertion-ordered map of song.id → prewarmed item. Order is the
    /// LRU order; oldest entry is at index 0 so eviction pops the
    /// front.
    private var orderedKeys: [String] = []
    private var items: [String: AVPlayerItem] = [:]

    private init() {}

    /// Pre-fetch and pool `AVPlayerItem`s for the given songs. Songs
    /// without a `previewURL` are skipped silently — there is nothing
    /// to prewarm. Songs already in the pool are left alone (their
    /// asset is presumably further along in loading already).
    func prewarm(songs: [Song]) {
        for song in songs {
            guard items[song.id] == nil else { continue }
            guard let raw = song.previewURL,
                  let url = URL(string: raw) else { continue }

            let asset = AVURLAsset(url: url)
            // The empty-completion call is intentional: kicking off
            // `loadValuesAsynchronously` is what triggers the network
            // fetch. We don't need to inspect the result here — the
            // `AVPlayerItem` will surface the eventual status when the
            // player attaches.
            asset.loadValuesAsynchronously(forKeys: ["playable", "duration"]) {}

            let item = AVPlayerItem(asset: asset)
            // 5s of forward buffer is plenty for a 30s preview and
            // keeps each prewarmed item small.
            item.preferredForwardBufferDuration = 5

            items[song.id] = item
            orderedKeys.append(song.id)

            evictIfNeeded()
        }
    }

    /// Take a prewarmed item out of the pool and return it for use by
    /// an `AVPlayer`. One-shot — the item is removed since AVPlayerItem
    /// instances can only be attached to a single player. Returns nil
    /// if the song wasn't prewarmed (or was already consumed).
    func consume(songId: String) -> AVPlayerItem? {
        guard let item = items.removeValue(forKey: songId) else { return nil }
        orderedKeys.removeAll { $0 == songId }
        return item
    }

    /// Drop everything. Called when the fullscreen feed dismisses so
    /// we don't keep megabytes of audio data resident after the user
    /// is no longer looking at the feed.
    func clearAll() {
        items.removeAll()
        orderedKeys.removeAll()
    }

    private func evictIfNeeded() {
        while orderedKeys.count > maxItems, let oldest = orderedKeys.first {
            orderedKeys.removeFirst()
            items.removeValue(forKey: oldest)
        }
    }
}
