import SwiftUI
import UIKit
import FirebaseAuth
import FirebaseCore
import FirebaseMessaging
import UserNotifications
import ChottuLinkSDK
import Nuke

// MARK: - Foreground notification suppression tracker

/// Lightweight main-actor registry the notification delegate consults in
/// `willPresent` to decide whether to surface a banner. When the user is
/// already looking at the screen a push is about to interrupt (e.g. a
/// DM arrives while they're already inside that thread), the banner is
/// noise — we just let the listener update the UI silently instead.
@MainActor
final class ActiveScreenTracker {
    static let shared = ActiveScreenTracker()
    private init() {}

    /// Conversation ID currently on-screen in `ChatView`. `nil` when no
    /// thread is open. Updated in `ChatView.onAppear/onDisappear`.
    var activeConversationId: String?
    /// True when `AddFriendsView` is on-screen. Drives suppression of
    /// friend-request banners.
    var isViewingAddFriends: Bool = false
}

// MARK: - Push / notification permission (deferred from cold launch)

enum NotificationPermission {
    private static let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]

    /// At launch: only register with APNs if the user already granted (or provisional) — no system prompt.
    static func registerForRemoteNotificationsIfAlreadyAuthorized() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let ok: Bool
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                ok = true
            default:
                ok = false
            }
            guard ok else { return }
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    static func currentAuthorizationStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }

    /// Shows the system permission dialog only when status is `.notDetermined`; registers when allowed.
    static func requestAuthorizationAndRegister() async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                switch settings.authorizationStatus {
                case .denied:
                    continuation.resume(returning: .denied)
                case .authorized, .provisional, .ephemeral:
                    DispatchQueue.main.async {
                        UIApplication.shared.registerForRemoteNotifications()
                    }
                    continuation.resume(returning: settings.authorizationStatus)
                case .notDetermined:
                    UNUserNotificationCenter.current().requestAuthorization(options: Self.authOptions) { granted, error in
                        if let error {
                            print("Notification permission error: \(error.localizedDescription)")
                        }
                        print("Notification permission granted: \(granted)")
                        DispatchQueue.main.async {
                            if granted {
                                UIApplication.shared.registerForRemoteNotifications()
                            }
                            UNUserNotificationCenter.current().getNotificationSettings { updated in
                                continuation.resume(returning: updated.authorizationStatus)
                            }
                        }
                    }
                @unknown default:
                    continuation.resume(returning: settings.authorizationStatus)
                }
            }
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate, ChottuLinkDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        FirebaseApp.configure()

        let config = CLConfiguration(
            apiKey: "c_app_3GyFRIbGUgB7iWYwMPEOM2Q7ogTMxPSf",
            delegate: self
        )
        ChottuLink.initialize(config: config)

        UNUserNotificationCenter.current().delegate = self
        Messaging.messaging().delegate = self

        NotificationPermission.registerForRemoteNotificationsIfAlreadyAuthorized()

        return true
    }

    // MARK: - ChottuLinkDelegate

    func chottuLink(didResolveDeepLink link: URL, metadata: [String: Any]?) {
        print("[ChottuLink] resolved link: \(link.absoluteString)")

        guard let components = URLComponents(url: link, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else { return }

        let referrerId = queryItems.first(where: { $0.name == "referringUserId" })?.value
        let referrerUsername = queryItems.first(where: { $0.name == "referringUsername" })?.value

        if let referrerId, !referrerId.isEmpty {
            DeepLinkService.shared.pendingReferrerId = referrerId
            DeepLinkService.shared.pendingReferrerUsername = referrerUsername

            NotificationCenter.default.post(
                name: .didReceiveDeepLink,
                object: nil,
                userInfo: ["referringUserId": referrerId, "referringUsername": referrerUsername ?? ""]
            )
        }
    }

    func chottuLink(didFailToResolveDeepLink originalURL: URL?, error: any Error) {
        print("[ChottuLink] failed to resolve: \(error.localizedDescription)")
    }

    func chottuLink(didInitializeWith configuration: CLConfiguration) {
        print("[ChottuLink] SDK initialized")
    }

    func chottuLink(didFailToInitializeWith error: any Error) {
        print("[ChottuLink] init failed: \(error.localizedDescription)")
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        #if DEBUG
        Auth.auth().setAPNSToken(deviceToken, type: .sandbox)
        #else
        Auth.auth().setAPNSToken(deviceToken, type: .prod)
        #endif
        Messaging.messaging().apnsToken = deviceToken
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("APNs registration failed: \(error.localizedDescription)")
    }

    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        if Auth.auth().canHandleNotification(userInfo) {
            completionHandler(.noData)
            return
        }
        completionHandler(.newData)
    }

    // MARK: - MessagingDelegate

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken else { return }
        print("FCM token received: \(token.prefix(20))...")
        Task { @MainActor in
            await FirebaseService.shared.saveFCMToken(token)
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let content = notification.request.content
        let userInfo = content.userInfo
        let type = userInfo["type"] as? String
        let threadId = content.threadIdentifier

        // Suppress the banner when the user is already looking at the
        // destination surface. The listener updates will repaint the
        // screen silently, so a banner on top would be redundant noise.
        // We still pass it through for badge updates below? — no: setBadgeCount
        // is owned by the client, so we just pass an empty option set to
        // skip banner/sound/badge entirely here.
        Task { @MainActor in
            let tracker = ActiveScreenTracker.shared
            if type == "new_message" || type == "new_share" {
                if let convId = userInfo["conversationId"] as? String,
                   tracker.activeConversationId == convId {
                    completionHandler([])
                    return
                }
                if threadId.hasPrefix("conv-"),
                   let active = tracker.activeConversationId,
                   threadId == "conv-\(active)" {
                    completionHandler([])
                    return
                }
            } else if type == "friend_request", tracker.isViewingAddFriends {
                completionHandler([])
                return
            }

            completionHandler([.banner, .badge, .sound])
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}

extension Notification.Name {
    static let didReceiveDeepLink = Notification.Name("didReceiveDeepLink")
}

@main
struct PlayMeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    init() {
        // Shared URLCache still useful as a secondary tier for non-Nuke
        // AsyncImage sites that might remain (e.g. avatars elsewhere).
        URLCache.shared = URLCache(
            memoryCapacity: 32 * 1024 * 1024,
            diskCapacity: 128 * 1024 * 1024,
            diskPath: "playme_url_cache"
        )

        // Nuke is the primary album-art pipeline. Big memory cache so the
        // Discovery grid and every SongCardView share decoded bitmaps; big
        // disk cache so cold launch after a week still paints instantly.
        // Task coalescing deduplicates concurrent requests for the same URL,
        // which is exactly what the Discovery grid needs when many slots
        // bind the same URL during a loop cycle.
        var config = ImagePipeline.Configuration.withDataCache
        let imageCache = ImageCache()
        imageCache.costLimit = 80 * 1024 * 1024
        imageCache.countLimit = 500
        config.imageCache = imageCache
        if let dataCache = try? DataCache(name: "playme.album.cache") {
            dataCache.sizeLimit = 400 * 1024 * 1024
            config.dataCache = dataCache
        }
        config.isProgressiveDecodingEnabled = false
        config.isTaskCoalescingEnabled = true
        ImagePipeline.shared = ImagePipeline(configuration: config)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    if Auth.auth().canHandle(url) { return }
                    ChottuLink.handleLink(url)
                }
        }
    }
}
