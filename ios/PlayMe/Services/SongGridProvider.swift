import Foundation

/// Pluggable source for `GridSong` data. Implementations return a flat list;
/// looping / windowing / caching is the caller's responsibility so every
/// provider looks identical to the UI.
protocol SongGridProvider: Sendable {
    func load() async throws -> [GridSong]
}
