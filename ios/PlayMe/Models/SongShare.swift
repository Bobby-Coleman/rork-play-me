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

    init(
        id: String = UUID().uuidString,
        song: Song,
        sender: AppUser,
        recipient: AppUser,
        note: String? = nil,
        timestamp: Date = Date(),
        recipientListenedAt: Date? = nil,
        recipientListenSources: [String] = []
    ) {
        self.id = id
        self.song = song
        self.sender = sender
        self.recipient = recipient
        self.note = note
        self.timestamp = timestamp
        self.recipientListenedAt = recipientListenedAt
        self.recipientListenSources = recipientListenSources
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
