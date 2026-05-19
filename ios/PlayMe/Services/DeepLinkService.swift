import Foundation
import ChottuLinkSDK

final class DeepLinkService {
    static let shared = DeepLinkService()

    /// Public TestFlight join link (also used as ChottuLink destination so Safari never opens a dead domain).
    static let publicTestFlightInviteURL = "https://testflight.apple.com/join/yRycD1gD"

    // Phase B: invite codes embedded in deep links auto-fill the
    // onboarding gate. Persisted across launches so a cold-launch from
    // a fresh install still picks the code up when the gate screen
    // mounts a few seconds later.
    private let inviteCodeKey = "playme_pendingInviteCode"

    // Legacy fields from the old `?referringUserId=` flow. Phase B
    // moved auto-friending server-side (handled by `redeemInviteCode`),
    // so these are no longer read. Kept defined for one release so
    // older clients with values stashed in UserDefaults don't crash if
    // someone reads them; safe to delete once no shipped build references
    // them.
    private let referrerIdKey = "playme_pendingReferrerId"
    private let referrerUsernameKey = "playme_pendingReferrerUsername"

    var pendingInviteCode: String? {
        get { UserDefaults.standard.string(forKey: inviteCodeKey) }
        set {
            if let v = newValue, !v.isEmpty {
                UserDefaults.standard.set(v.uppercased(), forKey: inviteCodeKey)
            } else {
                UserDefaults.standard.removeObject(forKey: inviteCodeKey)
            }
        }
    }

    var pendingReferrerId: String? {
        get { UserDefaults.standard.string(forKey: referrerIdKey) }
        set { UserDefaults.standard.set(newValue, forKey: referrerIdKey) }
    }

    var pendingReferrerUsername: String? {
        get { UserDefaults.standard.string(forKey: referrerUsernameKey) }
        set { UserDefaults.standard.set(newValue, forKey: referrerUsernameKey) }
    }

    private init() {}

    func clearPendingInviteCode() {
        pendingInviteCode = nil
    }

    func clearPendingReferrer() {
        pendingReferrerId = nil
        pendingReferrerUsername = nil
    }

    // MARK: - Personal invite (Phase B)

    /// Result of generating a personal invite: the human-typeable code +
    /// the ChottuLink shortlink that wraps it. The share-sheet body
    /// includes both so recipients can either tap the link OR type the
    /// code manually on a different device.
    struct PersonalInvite {
        let code: String
        let shortURL: String
    }

    /// Mints a fresh single-use personal invite code via the
    /// `generateInviteCode` Cloud Function, then wraps the returned
    /// destination URL in a ChottuLink shortlink (via `CLDynamicLinkBuilder`)
    /// so the shared URL is short, branded, and resolves to the gate
    /// auto-fill on install.
    ///
    /// Returns `nil` on any failure (rate limit, network, ChottuLink
    /// error). The caller should fall back to the legacy TestFlight URL.
    func createPersonalInvite(for username: String) async -> PersonalInvite? {
        guard let generated = await FirebaseService.shared.generateInviteCode() else {
            return nil
        }

        let builder = CLDynamicLinkBuilder(
            destinationURL: generated.destinationURL,
            domain: "playme.chottu.link"
        )
        .setIOSBehaviour(.app)
        .setSocialParameters(
            title: "Join me on RIFF!",
            description: "\(username) sent you an invite code",
            imageUrl: ""
        )
        .setLinkName("invite-\(generated.code)-\(Int(Date().timeIntervalSince1970))")
        .build()

        do {
            if let shortURL = try await ChottuLink.createDynamicLink(for: builder), !shortURL.isEmpty {
                return PersonalInvite(code: generated.code, shortURL: shortURL)
            }
            // ChottuLink returned nil — fall through to the raw URL.
            return PersonalInvite(code: generated.code, shortURL: generated.destinationURL)
        } catch {
            #if DEBUG
            print("[ChottuLink] short link creation failed: \(error.localizedDescription)")
            #endif
            // Fall back to the raw destination URL — the gate will still
            // auto-fill the code if the user opens the link on an
            // installed device.
            return PersonalInvite(code: generated.code, shortURL: generated.destinationURL)
        }
    }
}
