import Foundation

/// Opaque cursor type passed back to `DiscoverFeedProvider.loadMore`. The
/// placeholder implementation ignores the value, but the signature is part
/// of the contract so a future recommendations provider can paginate
/// without changing call sites.
nonisolated struct DiscoverCursor: Sendable, Hashable {
    let token: String
    init(token: String) { self.token = token }
}

/// Pluggable source for the Home / Discover feed. Returns full `Song`
/// objects (preview URL, Apple Music URL, etc.) rather than the leaner
/// `GridSong` because the same payload powers both the staggered grid
/// AND the TikTok-style fullscreen feed where preview playback matters.
///
/// Three implementation slots:
/// 1. `PlaceholderDiscoverFeedProvider` — Apple top charts hydrated with
///    iTunes lookup so previews work today.
/// 2. (Future) `RecommendationsDiscoverFeedProvider` — server-side reco.
/// 3. (Tests) any `Sendable` mock returning a fixed list.
///
/// `loadInitial()` should be cheap to call repeatedly; implementations are
/// expected to apply their own caching where appropriate.
protocol DiscoverFeedProvider: Sendable {
    func loadInitial() async throws -> [Song]
    /// Returns the next page of songs plus an optional next cursor. Pass
    /// `nil` for the first call. A nil return cursor signals end-of-feed.
    func loadMore(after cursor: DiscoverCursor?) async throws -> (songs: [Song], next: DiscoverCursor?)
}
