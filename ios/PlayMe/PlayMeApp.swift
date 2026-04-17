import SwiftUI
import FirebaseAuth
import FirebaseCore
import FirebaseMessaging
import UserNotifications
import ChottuLinkSDK

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

        let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]
        UNUserNotificationCenter.current().requestAuthorization(options: authOptions) { granted, error in
            if let error {
                print("Notification permission error: \(error.localizedDescription)")
            }
            print("Notification permission granted: \(granted)")
        }
        application.registerForRemoteNotifications()

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
        completionHandler([.banner, .badge, .sound])
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
