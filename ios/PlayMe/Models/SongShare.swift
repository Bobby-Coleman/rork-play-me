import Foundation

nonisolated struct SongShare: Identifiable, Hashable, Sendable {
    let id: String
    let song: Song
    let sender: AppUser
    let recipient: AppUser
    let note: String?
    let timestamp: Date
    let recipientListenedAt: Date?
    let recipientListenSources: [String]
    /// True when the recipient has liked this share. Denormalized onto the
    /// share doc by a Cloud Function so the SENDER can show the liker's
    /// avatar + heart on their sent feed card.
    let recipientLiked: Bool

    init(
        id: String = UUID().uuidString,
        song: Song,
        sender: AppUser,
        recipient: AppUser,
        note: String? = nil,
        timestamp: Date = Date(),
        recipientListenedAt: Date? = nil,
        recipientListenSources: [String] = [],
        recipientLiked: Bool = false
    ) {
        self.id = id
        self.song = song
        self.sender = sender
        self.recipient = recipient
        self.note = note
        self.timestamp = timestamp
        self.recipientListenedAt = recipientListenedAt
        self.recipientListenSources = recipientListenSources
        self.recipientLiked = recipientLiked
    }
}

nonisolated struct SentSongListener: Identifiable, Hashable, Sendable {
    let shareId: String
    let user: AppUser
    let listenedAt: Date
    let sources: [String]

    var id: String { shareId }
}

nonisolated struct SentSongHistoryItem: Identifiable, Hashable, Sendable {
    let song: Song
    let shares: [SongShare]

    var id: String { "sent-\(song.id)" }
    var timestamp: Date { shares.map(\.timestamp).max() ?? Date.distantPast }
    var latestShare: SongShare? { shares.max { $0.timestamp < $1.timestamp } }
    var recipientCount: Int { shares.count }

    var listeners: [SentSongListener] {
        shares.compactMap { share in
            guard let listenedAt = share.recipientListenedAt else { return nil }
            return SentSongListener(
                shareId: share.id,
                user: share.recipient,
                listenedAt: listenedAt,
                sources: share.recipientListenSources
            )
        }
        .sorted { $0.listenedAt > $1.listenedAt }
    }

    var recipients: [AppUser] {
        shares.map(\.recipient)
    }

    /// Recipients who liked this song (one per share that was liked),
    /// newest-like-first is not tracked, so order follows recipient order.
    var likers: [AppUser] {
        shares.filter(\.recipientLiked).map(\.recipient)
    }
}

/// One unique song within a single calendar day, carrying every share of
/// that song from that day (newest first). Sending one song to five friends
/// creates five `SongShare` docs but a single `DaySongGroup`, so calendar
/// surfaces show the song once with a recipient list.
nonisolated struct DaySongGroup: Identifiable, Hashable, Sendable {
    let song: Song
    /// Newest-first. Never empty.
    let shares: [SongShare]

    /// Unique within a day because grouping is by song.
    var id: String { song.id }
    /// The newest share, used for card-level context (note, timestamp,
    /// like state, send action).
    var primary: SongShare { shares[0] }
    var timestamp: Date { primary.timestamp }
    /// Every person this song went to that day, newest send first.
    var recipients: [AppUser] { shares.map(\.recipient) }
}

nonisolated enum DiscoveryFeedItem: Identifiable, Hashable, Sendable {
    case received(SongShare)
    case sent(SentSongHistoryItem)

    var id: String {
        switch self {
        case .received(let share):
            return share.id
        case .sent(let item):
            return item.id
        }
    }

    var timestamp: Date {
        switch self {
        case .received(let share):
            return share.timestamp
        case .sent(let item):
            return item.timestamp
        }
    }

    var albumPreviewShare: SongShare? {
        switch self {
        case .received(let share):
            return share
        case .sent(let item):
            return item.latestShare
        }
    }
}
