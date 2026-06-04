import UIKit
import UniformTypeIdentifiers

/// Share Extension entry point for "Send to Riff" from Spotify / Apple Music
/// (or any app that shares a link). This is a deliberately UI-less controller:
/// the heavy lifting (resolving the link to a catalog song, picking friends,
/// sending) happens in the main app, which already holds Firebase auth + the
/// MusicKit token. Here we only:
///
///   1. Pull the shared track URL out of the extension input items.
///   2. Stash it (plus a timestamp) in the shared App Group container.
///   3. Launch the host app via `playme://share-song`.
///   4. Complete the request so the share sheet dismisses immediately.
///
/// The App Group write is the source of truth; the deep link is just the
/// nudge to open the app. If `openURL` is throttled, the main app still picks
/// the link up on next foreground (freshness-windowed) — see
/// `ContentView.consumePendingSharedSong`.
final class ShareViewController: UIViewController {

    // Must match `WidgetSharedConstants` in the main app. Extensions can't
    // import the app target, so these are duplicated here intentionally.
    private let appGroupId = "group.app.rork.playme.shared"
    private let pendingURLKey = "pendingShareSongURL"
    private let pendingURLAtKey = "pendingShareSongURLAt"

    private let hostDeepLink = URL(string: "playme://share-song")!

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        extractSharedURL()
    }

    // MARK: - Input extraction

    private func extractSharedURL() {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem])?
            .compactMap { $0.attachments }
            .flatMap { $0 } ?? []

        // Prefer a real URL attachment (what Spotify / Apple Music provide).
        if let urlProvider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.url.identifier)
        }) {
            urlProvider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] data, _ in
                let urlString = (data as? URL)?.absoluteString ?? (data as? String)
                self?.finishOnMain(with: urlString)
            }
            return
        }

        // Fallback: plain text that may contain a URL.
        if let textProvider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)
        }) {
            textProvider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { [weak self] data, _ in
                self?.finishOnMain(with: self?.firstURL(in: data as? String))
            }
            return
        }

        finishOnMain(with: nil)
    }

    private func firstURL(in text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..., in: text)
        return detector?.firstMatch(in: text, options: [], range: range)?.url?.absoluteString
    }

    // MARK: - Persist + hand off

    private func finishOnMain(with urlString: String?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.persist(urlString)
            // Complete the request only after the open call has been issued,
            // so the share sheet doesn't tear us down mid-launch.
            self.openHostApp { [weak self] in
                self?.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
            }
        }
    }

    private func persist(_ urlString: String?) {
        guard let urlString, !urlString.isEmpty,
              let defaults = UserDefaults(suiteName: appGroupId) else { return }
        defaults.set(urlString, forKey: pendingURLKey)
        defaults.set(Date().timeIntervalSince1970, forKey: pendingURLAtKey)
    }

    /// Launches the host app by walking the responder chain to the live
    /// `UIApplication` instance and calling the modern
    /// `open(_:options:completionHandler:)`.
    ///
    /// Why not `UIApplication.shared.open` or `perform(#selector(openURL:))`?
    /// `UIApplication.shared` is unavailable in extensions, and on iOS 18+
    /// the deprecated `openURL(_:)` is forcibly disabled (always returns
    /// false, never opens) — which is why the previous selector-based version
    /// silently failed. Casting the responder to `UIApplication` and calling
    /// the non-deprecated `open` is the supported-in-practice path.
    private func openHostApp(completion: @escaping () -> Void) {
        var responder: UIResponder? = self
        while let current = responder {
            if let application = current as? UIApplication {
                application.open(hostDeepLink, options: [:]) { _ in completion() }
                return
            }
            responder = current.next
        }
        completion()
    }
}
