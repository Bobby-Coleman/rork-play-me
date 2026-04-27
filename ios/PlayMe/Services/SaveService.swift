import Foundation
import Observation

/// Single source of truth for "is this song saved to any of the user's
/// mixtapes". Every Save UI in the app — the Discover fullscreen feed,
/// the Mixtapes feed, the Received feed song card — reads `isSaved(song)`
/// off this object so the icon state stays consistent.
///
/// The actual song↔mixtape mapping lives in `MixtapeStore`; this service
/// is the lookup index that lets a UI cheaply answer "which mixtapes
/// contain this song?" without scanning every mixtape every time. The two
/// objects coordinate: `MixtapeStore` calls into `SaveService` after each
/// add/remove/delete write so the index stays in sync.
///
/// Persistence shape:
/// `users/{uid}/savedSongs/{songId}` → `{ mixtapeIds: [String], updatedAt }`
@MainActor
@Observable
final class SaveService {
    /// Map of `song.id` → set of mixtape IDs it lives in. `mixtapeIds`
    /// includes user-owned mixtapes only; the synthetic Liked mixtape is
    /// derived elsewhere.
    private(set) var songToMixtapeIds: [String: Set<String>] = [:]

    /// Set of all `song.id`s that live in at least one mixtape. Cached for
    /// O(1) `isSaved` checks called from cell-rendering hot paths.
    private(set) var savedSongIds: Set<String> = []

    /// True when `loadFromFirestore` has completed at least once for the
    /// current session. UI uses this to skip rendering "Save" placeholders
    /// before the index has hydrated.
    private(set) var hasLoaded: Bool = false

    func isSaved(songId: String) -> Bool {
        savedSongIds.contains(songId)
    }

    func isSaved(song: Song) -> Bool {
        savedSongIds.contains(song.id)
    }

    func mixtapeIds(forSongId songId: String) -> Set<String> {
        songToMixtapeIds[songId] ?? []
    }

    /// Local-only mutation used by `MixtapeStore` after a Firestore write
    /// completes. Also rebuilds the convenience `savedSongIds` set so
    /// readers don't have to recompute it.
    func setMixtapeMembership(songId: String, mixtapeIds: Set<String>) {
        if mixtapeIds.isEmpty {
            songToMixtapeIds.removeValue(forKey: songId)
            savedSongIds.remove(songId)
        } else {
            songToMixtapeIds[songId] = mixtapeIds
            savedSongIds.insert(songId)
        }
    }

    func addMixtape(_ mixtapeId: String, toSongId songId: String) {
        var current = songToMixtapeIds[songId] ?? []
        current.insert(mixtapeId)
        setMixtapeMembership(songId: songId, mixtapeIds: current)
    }

    func removeMixtape(_ mixtapeId: String, fromSongId songId: String) {
        var current = songToMixtapeIds[songId] ?? []
        current.remove(mixtapeId)
        setMixtapeMembership(songId: songId, mixtapeIds: current)
    }

    /// Bulk set used after the initial Firestore fetch. Replaces the in-memory
    /// index wholesale.
    func replaceAll(_ index: [String: Set<String>]) {
        songToMixtapeIds = index
        savedSongIds = Set(index.compactMap { $1.isEmpty ? nil : $0 })
        hasLoaded = true
    }

    /// Reset on logout so the next user doesn't see the previous account's
    /// saved-state.
    func clear() {
        songToMixtapeIds = [:]
        savedSongIds = []
        hasLoaded = false
    }

    /// Loads the savedSongs index for the signed-in user. No-op if not
    /// signed in. Errors are swallowed and surfaced as "no saves yet" so
    /// the UI never blocks on a transient Firestore hiccup.
    func loadFromFirestore() async {
        let firebase = FirebaseService.shared
        guard firebase.isSignedIn else {
            replaceAll([:])
            return
        }
        let index = await firebase.fetchSavedSongIndex()
        replaceAll(index)
    }
}
