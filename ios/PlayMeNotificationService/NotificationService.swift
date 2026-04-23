import UserNotifications
import WidgetKit
import UIKit

/// Runs in its own process every time APNs delivers a push marked with
/// `mutable-content: 1`. iOS guarantees ~30s of execution before it
/// force-calls our completion handler, which is more than enough time
/// to write widget state into the App Group container and download the
/// album art JPEG.
///
/// The main app's `AppState` still performs the same sync when its
/// received-shares listener fires, so foreground users stay correct too.
/// This extension exists purely to cover the suspended / terminated
/// app case, which is when the user is most likely to be looking at
/// their home screen anyway.
final class NotificationService: UNNotificationServiceExtension {
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttempt: UNMutableNotificationContent?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler
        let mutable = request.content.mutableCopy() as? UNMutableNotificationContent
        self.bestAttempt = mutable

        let info = request.content.userInfo
        let type = info["type"] as? String

        // Only `new_share` pushes carry widget payload. Every other push
        // type short-circuits straight back to the system with no edits.
        guard type == "new_share" else {
            contentHandler(mutable ?? request.content)
            return
        }

        persistWidgetFields(from: info)

        let urlString = (info["widgetAlbumArtURL"] as? String) ?? ""
        Task {
            await downloadAlbumArt(from: urlString)
            await MainActor.run {
                WidgetCenter.shared.reloadAllTimelines()
            }
            self.contentHandler?(mutable ?? request.content)
            self.contentHandler = nil
        }
    }

    override func serviceExtensionTimeWillExpire() {
        // iOS is about to kill us. Deliver whatever banner we have so the
        // user still sees the push even if the JPEG download didn't finish.
        if let handler = contentHandler {
            handler(bestAttempt ?? UNMutableNotificationContent())
            contentHandler = nil
        }
    }

    // MARK: - Persistence

    private func persistWidgetFields(from info: [AnyHashable: Any]) {
        guard let defaults = UserDefaults(suiteName: WidgetSharedConstants.appGroup) else {
            return
        }
        defaults.set(string(info, "widgetSongTitle"),       forKey: WidgetSharedConstants.Key.songTitle)
        defaults.set(string(info, "widgetSongArtist"),      forKey: WidgetSharedConstants.Key.songArtist)
        defaults.set(string(info, "widgetSenderFirstName"), forKey: WidgetSharedConstants.Key.senderFirstName)

        let note = string(info, "widgetNote")
        if note.isEmpty {
            defaults.removeObject(forKey: WidgetSharedConstants.Key.note)
        } else {
            defaults.set(note, forKey: WidgetSharedConstants.Key.note)
        }

        let shareId = (info["shareId"] as? String) ?? (info["id"] as? String) ?? ""
        defaults.set(shareId, forKey: WidgetSharedConstants.Key.shareId)
    }

    private func string(_ info: [AnyHashable: Any], _ key: String) -> String {
        (info[key] as? String) ?? ""
    }

    // MARK: - Album art

    private func downloadAlbumArt(from urlString: String) async {
        guard let fileURL = WidgetSharedConstants.albumArtFileURL() else { return }

        guard let url = URL(string: urlString), !urlString.isEmpty else {
            try? FileManager.default.removeItem(at: fileURL)
            return
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                return
            }
            // Decoding + re-encoding keeps the JPEG footprint small and
            // guarantees the widget's `UIImage(contentsOfFile:)` read
            // won't choke on an unexpected image format.
            if let image = UIImage(data: data),
               let jpeg = image.jpegData(compressionQuality: 0.85) {
                try jpeg.write(to: fileURL, options: .atomic)
            } else {
                try data.write(to: fileURL, options: .atomic)
            }
        } catch {
            // Silent failure: widget falls back to the previous album
            // art (or the solid placeholder) and the banner still lands.
        }
    }
}
