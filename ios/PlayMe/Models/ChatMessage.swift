import Foundation

struct ChatMessage: Identifiable, Hashable, Sendable {
    let id: String
    let senderId: String
    let text: String
    let timestamp: Date
    let song: Song?

    /// When non-nil, this message is an inline reply (WhatsApp/Telegram-style)
    /// to another message in the same conversation. The full parent isn't
    /// fetched on render — instead we embed a small `replyToPreview`
    /// snapshot at send-time so the quoted bubble renders even after the
    /// parent has been paged out of the visible window.
    let replyToMessageId: String?
    let replyToPreview: ReplyPreview?

    /// One reaction per user, keyed by Firebase UID. Empty when nobody
    /// has reacted. Tapping the same emoji you already reacted with
    /// removes your entry (toggle semantics).
    let reactions: [String: String]

    init(
        id: String = UUID().uuidString,
        senderId: String,
        text: String,
        timestamp: Date = Date(),
        song: Song? = nil,
        replyToMessageId: String? = nil,
        replyToPreview: ReplyPreview? = nil,
        reactions: [String: String] = [:]
    ) {
        self.id = id
        self.senderId = senderId
        self.text = text
        self.timestamp = timestamp
        self.song = song
        self.replyToMessageId = replyToMessageId
        self.replyToPreview = replyToPreview
        self.reactions = reactions
    }
}

/// Compact snapshot of the parent message embedded on a reply at send-time.
/// We snapshot rather than join-on-render so the quoted bubble survives the
/// parent being scrolled past the tail-listener window (older than the most
/// recent ~50 messages).
struct ReplyPreview: Hashable, Sendable {
    let messageId: String
    let senderId: String
    /// Truncated to ~80 chars; populated even if the parent was a song-only
    /// message so the quoted strip still has a label to show.
    let textSnippet: String
    /// Set when the parent message embedded a song. Used to render a
    /// "🎵 \(songTitle)" hint instead of a text snippet.
    let songTitle: String?
}
