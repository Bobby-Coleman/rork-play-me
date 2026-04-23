import Foundation

/// The four filter tabs across the top of the search UI. Drives which slice
/// of the reranked results is shown to the user.
enum SearchFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case artists
    case songs
    case albums

    var id: String { rawValue }

    var displayLabel: String {
        switch self {
        case .all:     return "All"
        case .artists: return "Artists"
        case .songs:   return "Songs"
        case .albums:  return "Albums"
        }
    }
}

/// Unified result bundle produced by `AppState.search`. Every bucket is
/// already reranked by `SearchRanker` — the view layer just slices and
/// displays.
struct SearchResults: Sendable {
    var artists: [ArtistSummary]
    var songs: [Song]
    var albums: [Album]
    /// Highest absolute score across all three buckets. Rendered as the
    /// Spotify-style "Top result" row above the grouped sections.
    var topHit: TopHit?

    static let empty = SearchResults(artists: [], songs: [], albums: [], topHit: nil)

    var isEmpty: Bool {
        artists.isEmpty && songs.isEmpty && albums.isEmpty
    }

    /// Tagged union so the view can switch on the winner without losing
    /// type information. Each case carries the full hit, not just its id.
    enum TopHit: Sendable {
        case artist(ArtistSummary)
        case song(Song)
        case album(Album)
    }
}
