import Foundation
import Security

/// Holds the Apple Music developer JWT used by `AppleMusicSearchService`
/// to talk to `api.music.apple.com`. The token is minted server-side by
/// the `getMusicKitDeveloperToken` Cloud Function so the underlying
/// MusicKit `.p8` private key never ships in the binary.
///
/// Lifecycle (all silent — never user-visible):
/// - Cold start: read from Keychain. If absent or expired, fetch fresh.
/// - Steady state: return the cached token.
/// - Near-expiry (within `refreshSkew`): fetch a fresh token before the
///   next request goes out.
/// - 401 from `api.music.apple.com`: caller invokes `forceRefresh()` to
///   throw away the cached token and mint a new one before retrying once.
///
/// The service is an actor so concurrent search keystrokes can't double-
/// fire `fetchAppleMusicDeveloperToken` against the Cloud Function. A
/// single in-flight refresh is shared across waiters via an
/// `Task<TokenBundle, Error>?` slot.
actor AppleMusicTokenService {
    static let shared = AppleMusicTokenService()

    /// Refresh proactively when the cached token has fewer than this many
    /// seconds of life remaining. 5 minutes leaves comfortable headroom
    /// for the next request to complete on the same JWT.
    private let refreshSkew: TimeInterval = 5 * 60

    private struct TokenBundle: Sendable {
        let token: String
        let expiresAt: Date

        var isExpired: Bool { Date() >= expiresAt }
    }

    private var cached: TokenBundle?
    private var inFlight: Task<TokenBundle, Error>?

    private init() {}

    /// Returns a developer JWT suitable for `Authorization: Bearer …`
    /// against `api.music.apple.com`. Throws `FirebaseService.AppleMusicTokenError`
    /// on all failure modes so callers can decide between "fall back to
    /// iTunes," "surface unavailable," or "treat as empty result."
    func token() async throws -> String {
        if let bundle = cached, !shouldRefresh(bundle) {
            return bundle.token
        }
        if let bundle = loadFromKeychain(), !shouldRefresh(bundle) {
            cached = bundle
            return bundle.token
        }
        return try await refreshTokenLocked().token
    }

    /// Drop the cached token and request a fresh one. Used by the
    /// search/artist HTTP paths after a 401 from Apple Music — same
    /// pattern as `resolveSpotifyTrack` re-minting on 401.
    func forceRefresh() async throws -> String {
        cached = nil
        clearKeychain()
        return try await refreshTokenLocked().token
    }

    private func shouldRefresh(_ bundle: TokenBundle) -> Bool {
        Date().addingTimeInterval(refreshSkew) >= bundle.expiresAt
    }

    /// Single-flight refresh. Concurrent callers piggy-back on the
    /// in-flight `Task` so we never double-fire the Cloud Function.
    private func refreshTokenLocked() async throws -> TokenBundle {
        if let existing = inFlight {
            return try await existing.value
        }
        let task = Task<TokenBundle, Error> { [weak self] in
            guard let self else { throw FirebaseService.AppleMusicTokenError.network("released") }
            return try await self.performRefresh()
        }
        inFlight = task
        defer { inFlight = nil }
        let bundle = try await task.value
        cached = bundle
        saveToKeychain(bundle)
        return bundle
    }

    /// Performs the actual Cloud Function call. `FirebaseService` is
    /// `@MainActor`-isolated; the implicit await-hop puts the network
    /// call on the main thread (it's just plumbing — the URLSession
    /// handler runs on its own queue) and we end up back on this
    /// actor's executor with the result.
    private func performRefresh() async throws -> TokenBundle {
        let result = await FirebaseService.shared.fetchAppleMusicDeveloperToken()
        switch result {
        case .success(let pair):
            return TokenBundle(token: pair.token, expiresAt: pair.expiresAt)
        case .failure(let err):
            throw err
        }
    }

    // MARK: - Keychain persistence

    /// Generic-password Keychain item. Token isn't sensitive PII (it's a
    /// developer JWT, not a user secret) but Keychain still gives us free
    /// at-rest protection and survives reinstalls if the user opts in.
    private static let keychainService = "com.playme.applemusic.developertoken"
    private static let keychainAccount = "default"

    private struct Persisted: Codable {
        let token: String
        let expiresAt: TimeInterval
    }

    private func saveToKeychain(_ bundle: TokenBundle) {
        let payload = Persisted(token: bundle.token, expiresAt: bundle.expiresAt.timeIntervalSince1970)
        guard let data = try? JSONEncoder().encode(payload) else { return }

        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount,
        ]
        let attrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attrs as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var insertQuery = baseQuery
            for (k, v) in attrs { insertQuery[k] = v }
            SecItemAdd(insertQuery as CFDictionary, nil)
        }
    }

    private func loadFromKeychain() -> TokenBundle? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount,
            kSecReturnData as String: kCFBooleanTrue as Any,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        guard let payload = try? JSONDecoder().decode(Persisted.self, from: data) else { return nil }
        let bundle = TokenBundle(
            token: payload.token,
            expiresAt: Date(timeIntervalSince1970: payload.expiresAt)
        )
        if bundle.isExpired { return nil }
        return bundle
    }

    private func clearKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
