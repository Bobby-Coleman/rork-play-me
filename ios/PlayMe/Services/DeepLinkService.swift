import Foundation
import ChottuLinkSDK

final class DeepLinkService {
    static let shared = DeepLinkService()

    /// Public TestFlight join link (also used as ChottuLink destination so Safari never opens a dead domain).
    static let publicTestFlightInviteURL = "https://testflight.apple.com/join/yRycD1gD"

    private let referrerIdKey = "playme_pendingReferrerId"
    private let referrerUsernameKey = "playme_pendingReferrerUsername"

    var pendingReferrerId: String? {
        get { UserDefaults.standard.string(forKey: referrerIdKey) }
        set { UserDefaults.standard.set(newValue, forKey: referrerIdKey) }
    }

    var pendingReferrerUsername: String? {
        get { UserDefaults.standard.string(forKey: referrerUsernameKey) }
        set { UserDefaults.standard.set(newValue, forKey: referrerUsernameKey) }
    }

    private init() {}

    func clearPendingReferrer() {
        pendingReferrerId = nil
        pendingReferrerUsername = nil
    }

    func createInviteLink(userId: String, username: String) async -> String? {
        let encoded = username.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? username
        let destination = "\(Self.publicTestFlightInviteURL)?referringUserId=\(userId)&referringUsername=\(encoded)"

        let builder = CLDynamicLinkBuilder(
            destinationURL: destination,
            domain: "playme.chottu.link"
        )
        .setIOSBehaviour(.app)
        .setSocialParameters(
            title: "Join me on RIFF!",
            description: "\(username) invited you to share music on RIFF",
            imageUrl: ""
        )
        .setLinkName("invite-\(userId.prefix(8))-\(Int(Date().timeIntervalSince1970))")
        .build()

        do {
            let shortURL = try await ChottuLink.createDynamicLink(for: builder)
            return shortURL
        } catch {
            print("[ChottuLink] link creation error: \(error.localizedDescription)")
            return nil
        }
    }
}
