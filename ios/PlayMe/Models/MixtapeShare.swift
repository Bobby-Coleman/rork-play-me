import Foundation

/// A snapshot of a mixtape sent from one user to another. Snapshot
/// (not reference) semantics are deliberate — same as `SongShare` — so
/// what the recipient opens is exactly what the sender sent, even if
/// the owner edits or deletes the original mixtape later. This is the
/// industry-standard MVP for playlist sharing: simpler permission
/// model, no live edits, no "this share now points at nothing"
/// failure mode.
///
/// Stored at `mixtapeShares/{shareId}` with the mixtape's full
/// `[Song]` payload embedded so the recipient view never needs a
/// follow-up read into the sender's account.
nonisolated struct MixtapeShare: Identifiable, Hashable, Sendable {
    let id: String
    /// Snapshot of the mixtape at send time. The `id`/`ownerId` on
    /// this struct still match the original mixtape doc, which is
    /// useful for "open the live mixtape" affordances when the
    /// recipient is also the owner — but does NOT imply live linkage
    /// otherwise. Treat as a frozen value.
    let mixtape: Mixtape
    let sender: AppUser
    let recipient: AppUser
    let note: String?
    let timestamp: Date

    init(
        id: String = UUID().uuidString,
        mixtape: Mixtape,
        sender: AppUser,
        recipient: AppUser,
        note: String? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.mixtape = mixtape
        self.sender = sender
        self.recipient = recipient
        self.note = note
        self.timestamp = timestamp
    }
}
