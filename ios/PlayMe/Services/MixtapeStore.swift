import Foundation
import Observation

/// CRUD store for the signed-in user's mixtapes. User-owned mixtapes live
/// in `users/{uid}/mixtapes/{id}` plus a `songs/{songId}` subcollection
/// for the embedded `Song` payload.
///
/// In addition to the persisted list, the store exposes a synthetic
/// "Liked" mixtape derived from `appState.likedShares`. The synthetic
/// mixtape is never written to Firestore — it's a view over the
/// existing per-share Like model so the user has a single Mixtapes
/// screen instead of two parallel surfaces. Computing it on the fly
/// also means the Liked mixtape stays reactive to like-toggle changes
/// without a separate listener.
///
/// Coordination with `SaveService`: every add/remove call updates both
/// Firestore AND the in-memory `SaveService.songToMixtapeIds` so the
/// "Save / Saved" toggle in fullscreen views and song cards stays in
/// sync without a refetch.
@MainActor
@Observable
final class MixtapeStore {
    /// User-owned mixtapes loaded from Firestore. Sorted newest-updated
    /// first so the Mixtapes grid feels lively after a fresh save.
    private(set) var userMixtapes: [Mixtape] = []
    /// True when `loadFromFirestore` has completed at least once for the
    /// current session.
    private(set) var hasLoaded: Bool = false

    /// `SaveService` instance to update on every mutation. Wired by
    /// `AppState` at construction so call sites don't need to plumb both.
    weak var saveService: SaveService?
    /// Closure that returns the current user's liked-and-resolved
    /// `[SongShare]`. Used to build the synthetic Liked mixtape on the
    /// fly. `AppState` provides this so the store doesn't need to know
    /// about the entire app graph.
    var likedSharesProvider: (@MainActor () -> [SongShare])?

    /// Combined list shown in the Mixtapes grid: synthetic "Liked"
    /// mixtape pinned first, then user-owned mixtapes in
    /// most-recently-updated order. Recomputed on access so the synthetic
    /// piece always reflects current `likedShares` state without a manual
    /// refresh hop.
    var allMixtapes: [Mixtape] {
        var result: [Mixtape] = []
        result.append(buildSyntheticLikedMixtape())
        result.append(contentsOf: userMixtapes)
        return result
    }

    /// Returns the canonical mixtape for a given id. Special-cases the
    /// synthetic Liked id so callers asking "give me the latest version
    /// of this mixtape" never miss the derived songs.
    func mixtape(withId id: String) -> Mixtape? {
        if id == Mixtape.systemLikedId {
            return buildSyntheticLikedMixtape()
        }
        return userMixtapes.first(where: { $0.id == id })
    }

    func clear() {
        userMixtapes = []
        hasLoaded = false
    }

    func loadFromFirestore() async {
        let firebase = FirebaseService.shared
        guard firebase.isSignedIn else {
            userMixtapes = []
            hasLoaded = true
            return
        }
        let mixtapes = await firebase.fetchMixtapes()
        userMixtapes = mixtapes.sorted { $0.updatedAt > $1.updatedAt }
        hasLoaded = true
    }

    // MARK: - CRUD

    @discardableResult
    func create(name: String, coverImageURL: String, isPrivate: Bool = false) async -> Mixtape? {
        let firebase = FirebaseService.shared
        guard firebase.isSignedIn, let uid = firebase.firebaseUID else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let cover = coverImageURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cover.isEmpty else { return nil }

        guard let id = await firebase.createMixtape(name: trimmed, coverImageURL: cover, isPrivate: isPrivate) else { return nil }
        let now = Date()
        let mixtape = Mixtape(
            id: id,
            ownerId: uid,
            name: trimmed,
            coverImageURL: cover,
            isPrivate: isPrivate,
            createdAt: now,
            updatedAt: now,
            songs: []
        )
        userMixtapes.insert(mixtape, at: 0)
        return mixtape
    }

    func rename(mixtapeId: String, to newName: String) async {
        guard !isSystemLiked(mixtapeId) else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        await FirebaseService.shared.renameMixtape(mixtapeId: mixtapeId, to: trimmed)
        if let idx = userMixtapes.firstIndex(where: { $0.id == mixtapeId }) {
            userMixtapes[idx].name = trimmed
            userMixtapes[idx].updatedAt = Date()
            resortByUpdatedAt()
        }
    }

    /// Writes the owner's "what is this mixtape about" blurb. Pass `nil`
    /// or an empty/whitespace string to clear it — we normalize both into
    /// `description = nil` locally so the detail header hides the line
    /// without the caller having to nil-coalesce.
    func updateDescription(mixtapeId: String, to newDescription: String?) async {
        guard !isSystemLiked(mixtapeId) else { return }
        let trimmed = newDescription?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let normalized: String? = trimmed.isEmpty ? nil : trimmed
        await FirebaseService.shared.updateMixtapeDescription(mixtapeId: mixtapeId, to: normalized)
        if let idx = userMixtapes.firstIndex(where: { $0.id == mixtapeId }) {
            userMixtapes[idx].description = normalized
            userMixtapes[idx].updatedAt = Date()
            resortByUpdatedAt()
        }
    }

    func delete(mixtapeId: String) async {
        guard !isSystemLiked(mixtapeId) else { return }
        // Remove song-membership index entries for every song that lived
        // only in this mixtape so `SaveService.isSaved` flips off
        // immediately on the local client.
        if let removed = userMixtapes.first(where: { $0.id == mixtapeId }) {
            for song in removed.songs {
                saveService?.removeMixtape(mixtapeId, fromSongId: song.id)
            }
        }
        await FirebaseService.shared.deleteMixtape(mixtapeId: mixtapeId)
        userMixtapes.removeAll { $0.id == mixtapeId }
    }

    func addSong(_ song: Song, to mixtapeId: String) async {
        guard !isSystemLiked(mixtapeId) else { return }
        await FirebaseService.shared.addSongToMixtape(mixtapeId: mixtapeId, song: song)
        if let idx = userMixtapes.firstIndex(where: { $0.id == mixtapeId }) {
            if !userMixtapes[idx].songs.contains(where: { $0.id == song.id }) {
                userMixtapes[idx].songs.insert(song, at: 0)
            }
            userMixtapes[idx].updatedAt = Date()
            resortByUpdatedAt()
        }
        saveService?.addMixtape(mixtapeId, toSongId: song.id)
    }

    func removeSong(songId: String, from mixtapeId: String) async {
        guard !isSystemLiked(mixtapeId) else { return }
        await FirebaseService.shared.removeSongFromMixtape(mixtapeId: mixtapeId, songId: songId)
        if let idx = userMixtapes.firstIndex(where: { $0.id == mixtapeId }) {
            userMixtapes[idx].songs.removeAll { $0.id == songId }
            userMixtapes[idx].updatedAt = Date()
            resortByUpdatedAt()
        }
        saveService?.removeMixtape(mixtapeId, fromSongId: songId)
    }

    /// Toggle membership: removes the song if already in the mixtape, otherwise
    /// adds it. Used by `SaveToMixtapeSheet` checkmark rows.
    func toggleSong(_ song: Song, in mixtapeId: String) async {
        guard !isSystemLiked(mixtapeId) else { return }
        let isMember = userMixtapes.first(where: { $0.id == mixtapeId })?.songs.contains(where: { $0.id == song.id }) ?? false
        if isMember {
            await removeSong(songId: song.id, from: mixtapeId)
        } else {
            await addSong(song, to: mixtapeId)
        }
    }

    /// Returns the union of all songs across user-owned mixtapes plus any
    /// synthetic Liked mixtape entries, deduplicated by `song.id`. Drives
    /// the `Songs` segment of the Mixtapes screen. Sorted in
    /// most-recently-added order using the embedded mixtapes' `updatedAt`
    /// (with Liked songs sorted by their share timestamp inside the
    /// synthetic mixtape).
    func allSongsAcrossMixtapes() -> [Song] {
        var ordered: [Song] = []
        var seen = Set<String>()

        // Liked first because it's pinned at the top of the grid; it
        // already comes out of `buildSyntheticLikedMixtape()` newest-first.
        let liked = buildSyntheticLikedMixtape()
        for song in liked.songs where seen.insert(song.id).inserted {
            ordered.append(song)
        }

        // Walk user mixtapes newest-updated first; their internal order is
        // newest-added first, so iterating preserves global recency.
        for mix in userMixtapes {
            for song in mix.songs where seen.insert(song.id).inserted {
                ordered.append(song)
            }
        }
        return ordered
    }

    // MARK: - Helpers

    private func isSystemLiked(_ id: String) -> Bool {
        id == Mixtape.systemLikedId
    }

    private func resortByUpdatedAt() {
        userMixtapes.sort { $0.updatedAt > $1.updatedAt }
    }

    /// Builds the synthetic "Liked" mixtape from the user's currently
    /// liked shares, deduplicated by `song.id` (newest like first). Re-run
    /// on every read so it stays in sync with `appState.likedShareIds`
    /// without a separate listener.
    private func buildSyntheticLikedMixtape() -> Mixtape {
        let firebaseUID = FirebaseService.shared.firebaseUID ?? ""
        let liked = likedSharesProvider?() ?? []
        var seen = Set<String>()
        var songs: [Song] = []
        for share in liked where seen.insert(share.song.id).inserted {
            songs.append(share.song)
        }
        let updatedAt = liked.first?.timestamp ?? Date()
        return Mixtape(
            id: Mixtape.systemLikedId,
            ownerId: firebaseUID,
            name: "Liked",
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: updatedAt,
            songs: songs,
            isSystemLiked: true
        )
    }
}
