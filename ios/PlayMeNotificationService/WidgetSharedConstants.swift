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

    enum Key {
        static let songTitle        = "widgetSongTitle"
        static let songArtist       = "widgetSongArtist"
        static let senderFirstName  = "widgetSenderFirstName"
        static let note             = "widgetNote"
        static let shareId          = "widgetShareId"
    }

    static let allKeys: [String] = [
        Key.songTitle,
        Key.songArtist,
        Key.senderFirstName,
        Key.note,
        Key.shareId,
    ]

    static func albumArtFileURL() -> URL? {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroup
        ) else { return nil }
        return containerURL.appendingPathComponent(albumArtFilename)
    }
}
