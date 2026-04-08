import Foundation

struct ChatMessage: Identifiable, Hashable, Sendable {
    let id: String
    let senderId: String
    let text: String
    let timestamp: Date
    let song: Song?

    init(id: String = UUID().uuidString, senderId: String, text: String, timestamp: Date = Date(), song: Song? = nil) {
        self.id = id
        self.senderId = senderId
        self.text = text
        self.timestamp = timestamp
        self.song = song
    }
}
