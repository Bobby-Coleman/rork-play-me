import Foundation

/// Mirror of `ios/PlayMe/Shared/WidgetSharedConstants.swift` compiled into the
/// notification service extension target. Xcode 16's file-system-synchronized
/// folders can't share a single source file across multiple sync roots without
/// overlapping groups, so we accept a ~40-line duplicate here. If you change
/// a key or the app group id, update BOTH files — a mismatch silently breaks
/// widget refresh from the extension while the foreground path keeps working,
/// which is a miserable bug to diagnose.
enum WidgetSharedConstants {
    static let appGroup = "group.app.rork.playme.shared"
    static let albumArtFilename = "widgetAlbumArt.jpg"
    static let senderAvatarFilename = "widgetSenderAvatar.jpg"

    enum Key {
        static let songTitle        = "widgetSongTitle"
        static let songArtist       = "widgetSongArtist"
        static let senderFirstName  = "widgetSenderFirstName"
        static let senderAvatarURL  = "widgetSenderAvatarURL"
        static let note             = "widgetNote"
        static let shareId          = "widgetShareId"
        /// Cached song-unread portion of the app-icon badge, written by
        /// the main app on reconcile and incremented by the notification
        /// service extension on `new_share` pushes while suspended.
        static let unreadCount      = "widgetUnreadCount"
        /// Last app-icon badge total written by the main app. The
        /// notification extension increments this on `new_share` so it
        /// can update the badge without reading the live count.
        static let appIconBadgeTotal = "appIconBadgeTotal"
    }

    static let allKeys: [String] = [
        Key.songTitle,
        Key.songArtist,
        Key.senderFirstName,
        Key.senderAvatarURL,
        Key.note,
        Key.shareId,
        Key.unreadCount,
        Key.appIconBadgeTotal,
    ]

    static func albumArtFileURL() -> URL? {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroup
        ) else { return nil }
        return containerURL.appendingPathComponent(albumArtFilename)
    }

    static func senderAvatarFileURL() -> URL? {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroup
        ) else { return nil }
        return containerURL.appendingPathComponent(senderAvatarFilename)
    }
}
