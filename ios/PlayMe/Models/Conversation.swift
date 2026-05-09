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
    /// Total song messages sent between these two participants.
    let songMessageCount: Int
    /// Local day string (`yyyy-MM-dd`) for the last song message that advanced
    /// the streak. Used only for reset countdown display.
    let songStreakLastDay: String?
    /// Last-read timestamp per participant, parsed from
    /// `lastReadAt_<uid>` fields on the conversation document. Drives the
    /// iMessage-style "Read" indicator under the most recent message the
    /// current user has sent. Missing entries mean "never read".
    let lastReadAt: [String: Date]

    init(
        id: String,
        participants: [String],
        participantNames: [String: String],
        lastMessageText: String,
        lastMessageTimestamp: Date,
        unreadCount: Int,
        songStreakCount: Int,
        songMessageCount: Int = 0,
        songStreakLastDay: String? = nil,
        lastReadAt: [String: Date] = [:]
    ) {
        self.id = id
        self.participants = participants
        self.participantNames = participantNames
        self.lastMessageText = lastMessageText
        self.lastMessageTimestamp = lastMessageTimestamp
        self.unreadCount = unreadCount
        self.songStreakCount = songStreakCount
        self.songMessageCount = songMessageCount
        self.songStreakLastDay = songStreakLastDay
        self.lastReadAt = lastReadAt
    }

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

    /// Returns a copy of this conversation with `unreadCount` overridden.
    /// Used by `ChatView` to zero the inbox badge optimistically the moment
    /// a thread is opened, without waiting for the Firestore snapshot to
    /// round-trip the `unreadCount_<uid>` = 0 write. The listener will
    /// later reconcile the authoritative value and this optimistic update
    /// will simply match.
    func withUnreadCount(_ newCount: Int) -> Conversation {
        Conversation(
            id: id,
            participants: participants,
            participantNames: participantNames,
            lastMessageText: lastMessageText,
            lastMessageTimestamp: lastMessageTimestamp,
            unreadCount: newCount,
            songStreakCount: songStreakCount,
            songMessageCount: songMessageCount,
            songStreakLastDay: songStreakLastDay,
            lastReadAt: lastReadAt
        )
    }
}
