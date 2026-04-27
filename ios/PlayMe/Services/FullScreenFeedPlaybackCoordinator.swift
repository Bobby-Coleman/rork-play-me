import Foundation
import Observation

/// Drives autoplay for the TikTok-style fullscreen song feed
/// (`SongFullScreenFeedView`). The feed view binds its
/// `.scrollPosition(id: $visibleSongId)` to the coordinator and, on every
/// change, the coordinator pauses the previous song and starts the new one
/// via the shared `AudioPlayerService`.
///
/// Why a thin coordinator instead of in-line logic in the view: the
/// fullscreen feed is presented from multiple entry points (Discover grid,
/// Mixtape song list, Mixtapes Songs grid). Wiring autoplay through a
/// single object keeps the play/pause sequencing identical regardless of
/// the seed source, and gives us one place to special-case
/// missing-`previewURL` (logs and skips silently — the page still renders
/// the artwork).
@MainActor
@Observable
final class FullScreenFeedPlaybackCoordinator {
    /// The song currently considered "visible" in the feed. Bind a
    /// `.scrollPosition(id:)` to this value (the binding string is
    /// `song.id`) and call `onVisibleSongChanged` whenever the binding
    /// fires; the coordinator handles the AVPlayer transitions.
    var visibleSongId: String?

    /// Tracks the active playback session so a duplicate `play` for the
    /// same song doesn't restart the AVPlayer (and reset the scrub bar).
    private var lastTriggeredSongId: String?

    /// Starts playback for the song the user just opened the feed at. Idempotent.
    func startInitial(song: Song) {
        visibleSongId = song.id
        playIfNeeded(song: song)
    }

    /// Called when `.scrollPosition(id:)` reports a new visible page. Pass
    /// in the matching `Song` (the feed view holds the songs array, so
    /// it's a cheap lookup) so the coordinator can route to AVPlayer.
    func onVisibleSongChanged(to song: Song?) {
        guard let song else { return }
        guard song.id != lastTriggeredSongId else { return }
        playIfNeeded(song: song)
    }

    /// Public stop hook called when the feed dismisses so the player
    /// state doesn't leak to the underlying surface (e.g. the Discover
    /// grid wakes back up with the preview already playing).
    func stop() {
        AudioPlayerService.shared.stop()
        visibleSongId = nil
        lastTriggeredSongId = nil
    }

    private func playIfNeeded(song: Song) {
        // No previewURL → log and bail. The page still renders artwork +
        // metadata; we just can't autoplay. A user can still tap "Open in
        // Spotify" to launch the full track in their preferred service.
        guard song.previewURL != nil else {
            print("FullScreenFeedPlaybackCoordinator: no previewURL for song id=\(song.id) title=\"\(song.title)\"")
            lastTriggeredSongId = song.id
            AudioPlayerService.shared.pause()
            return
        }

        let audio = AudioPlayerService.shared
        // Pause any previous song so the swipe-to-next transition doesn't
        // briefly overlap two clips. `play(song:)` itself stops/teardowns
        // the previous AVPlayer when the song id changes, but the explicit
        // `pause()` makes the transition feel snappier on slower networks
        // by silencing audio while the new player loads.
        if audio.currentSongId != song.id {
            audio.pause()
        }
        audio.play(song: song)
        lastTriggeredSongId = song.id
    }
}
