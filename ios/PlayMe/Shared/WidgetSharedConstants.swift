import Foundation

/// Single source of truth for every identifier the main app, the widget,
/// and the notification service extension must agree on. Drift between
/// these three targets silently breaks widget updates (the extension
/// would write to a different suite / file than the widget reads from),
/// so any change here affects all three processes at once.
enum WidgetSharedConstants {
    /// App Group shared by PlayMe, PlayMeWidget, and PlayMeNotificationService.
    /// Matches the `com.apple.security.application-groups` entitlement on all
    /// three targets.
    static let appGroup = "group.app.rork.playme.shared"

    /// Album art JPEG written to the App Group's container Documents by whoever
    /// last refreshed the widget (main app listener OR the service extension).
    static let albumArtFilename = "widgetAlbumArt.jpg"
    static let senderAvatarFilename = "widgetSenderAvatar.jpg"

    enum Key {
        static let songTitle        = "widgetSongTitle"
        static let songArtist       = "widgetSongArtist"
        static let senderFirstName  = "widgetSenderFirstName"
        static let senderAvatarURL  = "widgetSenderAvatarURL"
        static let note             = "widgetNote"
        static let shareId          = "widgetShareId"
        /// User-selected widget look (`WidgetStyle` raw value). Lives in
        /// the App Group so the widget extension can read it. Deliberately
        /// NOT in `allKeys`: it's a device-level preference that should
        /// survive sign-out.
        static let widgetStyle      = "widgetStyle"
        /// Monotonic counter bumped on every widget-style change so
        /// WidgetKit busts cached timelines. Deliberately NOT in
        /// `allKeys` — survives sign-out like `widgetStyle`.
        static let widgetStyleEpoch = "widgetStyleEpoch"
        /// Cached song-unread portion of the app-icon badge, written by
        /// the main app on reconcile and incremented by the notification
        /// service extension on `new_share` pushes while suspended.
        static let unreadCount      = "widgetUnreadCount"
        /// Last app-icon badge total written by the main app. The
        /// notification extension increments this on `new_share` so it
        /// can update the badge without reading the live count.
        static let appIconBadgeTotal = "appIconBadgeTotal"
        /// Share IDs the user has already seen in the feed or in messages
        /// (local-only "checked" tracking — distinct from the server-side
        /// `recipientListenedAt`, which means the song was actually played
        /// and powers the sender's "Listened by" UI).
        static let seenShareIds     = "widgetSeenShareIds"

        /// Written by the Share Extension (RiffShare) when the user shares a
        /// Spotify/Apple Music track into Riff: the raw track URL plus the
        /// epoch timestamp of when it was captured. The main app reads these
        /// on `playme://share-song` deep links and on foreground (freshness
        /// window) to resolve + present the send flow.
        static let pendingShareSongURL   = "pendingShareSongURL"
        static let pendingShareSongURLAt = "pendingShareSongURLAt"
    }

    /// All `UserDefaults` keys owned by the widget in a single array. Useful
    /// for clear-state paths (sign-out, etc.).
    static let allKeys: [String] = [
        Key.songTitle,
        Key.songArtist,
        Key.senderFirstName,
        Key.senderAvatarURL,
        Key.note,
        Key.shareId,
        Key.unreadCount,
        Key.appIconBadgeTotal,
        Key.seenShareIds,
    ]

    /// Full file URL for the album art JPEG inside the App Group container.
    /// Returns `nil` if the container can't be resolved (should only happen
    /// if the entitlement is missing).
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

/// Visual style of the home-screen widget. Raw values persist in the App
/// Group under `WidgetSharedConstants.Key.widgetStyle`; the widget
/// extension compiles its own mirror of this enum (extensions can't import
/// the app target), so raw values must never change. A legacy stored
/// "cdDark" (removed style) decodes to nil and falls back to `.cd` at
/// every read site.
enum WidgetStyle: String, CaseIterable, Identifiable {
    /// Album art seated as a CD inside the clear jewel case.
    case cd
    /// Full-bleed album art with the sender avatar + note overlay.
    case classic

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cd: return "CD case"
        case .classic: return "Classic"
        }
    }
}
