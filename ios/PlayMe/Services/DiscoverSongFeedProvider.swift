import Foundation

/// Pluggable source for the left Discover/Home song grid. The production
/// implementation reads Firebase's editorial `featured_songs` collection.
protocol DiscoverSongFeedProvider: Sendable {
    func loadInitial() async -> [Song]
}

final class FirestoreDiscoverSongFeedProvider: DiscoverSongFeedProvider, @unchecked Sendable {
    private let limit: Int

    init(limit: Int = 100) {
        self.limit = limit
    }

    func loadInitial() async -> [Song] {
        await FirebaseService.shared.fetchFeaturedSongs(limit: limit)
    }
}
