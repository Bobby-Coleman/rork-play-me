import Foundation

struct Conversation: Identifiable, Hashable, Sendable {
    let id: String
    let participants: [String]
    let participantNames: [String: String]
    let lastMessageText: String
    let lastMessageTimestamp: Date
    let unreadCount: Int
    /// Consecutive UTC days with at least one song message from either participant.
    let songStreakCount: Int

    func friendName(currentUserId: String) -> String {
        for (uid, name) in participantNames where uid != currentUserId {
            return name
        }
        return "Unknown"
    }

    func friendId(currentUserId: String) -> String {
        for uid in participants where uid != currentUserId {
            return uid
        }
        return ""
    }
}
