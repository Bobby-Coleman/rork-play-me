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

    enum Key {
        static let songTitle        = "widgetSongTitle"
        static let songArtist       = "widgetSongArtist"
        static let senderFirstName  = "widgetSenderFirstName"
        static let note             = "widgetNote"
        static let shareId          = "widgetShareId"
    }

    /// All `UserDefaults` keys owned by the widget in a single array. Useful
    /// for clear-state paths (sign-out, etc.).
    static let allKeys: [String] = [
        Key.songTitle,
        Key.songArtist,
        Key.senderFirstName,
        Key.note,
        Key.shareId,
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
}
