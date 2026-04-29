import Foundation

/// Opaque pagination token for `DiscoverMixtapeFeedProvider.loadMore`.
nonisolated struct DiscoverMixtapeCursor: Sendable, Hashable {
    /// Firestore document id of the last mixtape from the prior page
    /// (`featured_mixtapes` doc ids).
    let lastDocumentId: String
}

/// Pluggable source for the Home tab's curated mixtape Pinterest grid.
/// `MockDiscoverMixtapeFeedProvider` reads `featured_mixtapes` today; a
/// future `CommunityDiscoverMixtapeFeedProvider` can swap in without
/// view changes.
protocol DiscoverMixtapeFeedProvider: Sendable {
    func loadInitial() async -> [Mixtape]
    func loadMore(after cursor: DiscoverMixtapeCursor?) async -> ([Mixtape], DiscoverMixtapeCursor?)
}

/// Loads editorial mixtapes from Firestore `featured_mixtapes`, ordered by
/// `order` ascending. Cursor is the last document id from the previous
/// response (Firestore `start(afterDocument:)` semantics).
final class MockDiscoverMixtapeFeedProvider: DiscoverMixtapeFeedProvider, @unchecked Sendable {
    private let pageSize: Int
    private var lastFetchedDocumentId: String?

    init(pageSize: Int = 20) {
        self.pageSize = pageSize
    }

    func loadInitial() async -> [Mixtape] {
        lastFetchedDocumentId = nil
        let (page, last) = await FirebaseService.shared.fetchFeaturedMixtapes(
            limit: pageSize,
            startAfterDocumentId: nil
        )
        lastFetchedDocumentId = last
        return page
    }

    func loadMore(after cursor: DiscoverMixtapeCursor?) async -> ([Mixtape], DiscoverMixtapeCursor?) {
        let afterId = cursor?.lastDocumentId ?? lastFetchedDocumentId
        guard let afterId else { return ([], nil) }
        let (page, last) = await FirebaseService.shared.fetchFeaturedMixtapes(
            limit: pageSize,
            startAfterDocumentId: afterId
        )
        guard !page.isEmpty else { return ([], nil) }
        lastFetchedDocumentId = last
        let next = last.map { DiscoverMixtapeCursor(lastDocumentId: $0) }
        return (page, next)
    }
}
