import Foundation

/// Primary `SongGridProvider` for the Discovery background grid.
///
/// Reads a single Firestore document (`curatedGrids/current`) whose `items`
/// array is a list of `{ id, albumArtURL, title?, artist? }` dictionaries.
/// Editorial staff can rotate this list at will — the app picks up the
/// change on the next cold launch (and even sooner once a snapshot listener
/// is added).
///
/// Accepts an optional `override` so preview/test harnesses can inject a
/// dataset with zero network access.
struct CuratedSongGridProvider: SongGridProvider {
    let override: [GridSong]?

    init(override: [GridSong]? = nil) {
        self.override = override
    }

    func load() async throws -> [GridSong] {
        if let override, !override.isEmpty { return override }
        return await FirebaseService.shared.fetchCuratedGrid()
    }
}
