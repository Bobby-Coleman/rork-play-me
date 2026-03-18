import Foundation

nonisolated struct SongShare: Identifiable, Hashable, Sendable {
    let id: String
    let song: Song
    let sender: AppUser
    let recipient: AppUser
    let note: String?
    let timestamp: Date

    init(id: String = UUID().uuidString, song: Song, sender: AppUser, recipient: AppUser, note: String? = nil, timestamp: Date = Date()) {
        self.id = id
        self.song = song
        self.sender = sender
        self.recipient = recipient
        self.note = note
        self.timestamp = timestamp
    }
}
