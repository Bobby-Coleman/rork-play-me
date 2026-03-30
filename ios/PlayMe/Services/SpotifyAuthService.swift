import Foundation
import AuthenticationServices
import CryptoKit

nonisolated struct SpotifyTokenResponse: Codable, Sendable {
    let access_token: String
    let token_type: String
    let scope: String?
    let expires_in: Int
    let refresh_token: String?
}

nonisolated struct SpotifyUserProfile: Codable, Sendable {
    let id: String
    let display_name: String?
    let email: String?
}

@Observable
@MainActor
class SpotifyAuthService: NSObject {
    var isAuthenticated: Bool = false
    var userProfile: SpotifyUserProfile?
    var isAuthenticating: Bool = false

    private var accessToken: String?
    private var refreshToken: String?
    private var tokenExpiry: Date?
    private var codeVerifier: String?

    private let keychain = KeychainService.shared

    private let clientID: String = Config.EXPO_PUBLIC_SPOTIFY_CLIENT_ID
    private let redirectURI = "playme://spotify-callback"
    private let tokenURL = "https://accounts.spotify.com/api/token"
    private let authorizeURL = "https://accounts.spotify.com/authorize"

    private let scopes = [
        "user-read-private",
        "user-read-email",
        "streaming",
        "user-library-read"
    ].joined(separator: " ")

    override init() {
        super.init()
        loadStoredTokens()
    }

    private func loadStoredTokens() {
        if let token = keychain.loadString(key: "spotify_access_token"),
           let refresh = keychain.loadString(key: "spotify_refresh_token"),
           let expiryData = keychain.load(key: "spotify_token_expiry") {
            accessToken = token
            refreshToken = refresh
            tokenExpiry = try? JSONDecoder().decode(Date.self, from: expiryData)
            isAuthenticated = true

            Task { await fetchUserProfile() }
        }
    }

    private func storeTokens(access: String, refresh: String?, expiresIn: Int) {
        accessToken = access
        if let refresh { refreshToken = refresh }
        tokenExpiry = Date().addingTimeInterval(TimeInterval(expiresIn))

        keychain.save(access, for: "spotify_access_token")
        if let refresh { keychain.save(refresh, for: "spotify_refresh_token") }
        if let expiry = tokenExpiry, let data = try? JSONEncoder().encode(expiry) {
            keychain.save(data, for: "spotify_token_expiry")
        }
    }

    func getValidAccessToken() async -> String? {
        if let expiry = tokenExpiry, Date() > expiry.addingTimeInterval(-60) {
            await refreshAccessToken()
        }
        return accessToken
    }

    func authenticate() async {
        isAuthenticating = true
        defer { isAuthenticating = false }

        let verifier = generateCodeVerifier()
        codeVerifier = verifier
        guard let challenge = generateCodeChallenge(from: verifier) else { return }

        var components = URLComponents(string: authorizeURL)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge)
        ]

        guard let authURL = components.url else { return }

        do {
            let callbackURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
                let session = ASWebAuthenticationSession(
                    url: authURL,
                    callback: .customScheme("playme")
                ) { url, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let url {
                        continuation.resume(returning: url)
                    } else {
                        continuation.resume(throwing: URLError(.cancelled))
                    }
                }
                session.prefersEphemeralWebBrowserSession = false
                session.presentationContextProvider = self
                session.start()
            }

            guard let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "code" })?.value else { return }

            await exchangeCodeForToken(code: code)
            await fetchUserProfile()
        } catch {
            // User cancelled or auth failed
        }
    }

    private func exchangeCodeForToken(code: String) async {
        guard let verifier = codeVerifier else { return }

        var request = URLRequest(url: URL(string: tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "grant_type=authorization_code",
            "code=\(code)",
            "redirect_uri=\(redirectURI.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? redirectURI)",
            "client_id=\(clientID)",
            "code_verifier=\(verifier)"
        ].joined(separator: "&")

        request.httpBody = body.data(using: .utf8)

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let tokenResponse = try JSONDecoder().decode(SpotifyTokenResponse.self, from: data)
            storeTokens(access: tokenResponse.access_token, refresh: tokenResponse.refresh_token, expiresIn: tokenResponse.expires_in)
            isAuthenticated = true
        } catch {}
    }

    private func refreshAccessToken() async {
        guard let refresh = refreshToken else { return }

        var request = URLRequest(url: URL(string: tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "grant_type=refresh_token",
            "refresh_token=\(refresh)",
            "client_id=\(clientID)"
        ].joined(separator: "&")

        request.httpBody = body.data(using: .utf8)

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let tokenResponse = try JSONDecoder().decode(SpotifyTokenResponse.self, from: data)
            storeTokens(access: tokenResponse.access_token, refresh: tokenResponse.refresh_token ?? refresh, expiresIn: tokenResponse.expires_in)
        } catch {
            disconnect()
        }
    }

    private func fetchUserProfile() async {
        guard let token = await getValidAccessToken() else { return }

        var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/me")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            userProfile = try JSONDecoder().decode(SpotifyUserProfile.self, from: data)
        } catch {}
    }

    func disconnect() {
        accessToken = nil
        refreshToken = nil
        tokenExpiry = nil
        userProfile = nil
        isAuthenticated = false
        keychain.deleteAll()
    }

    private func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
            .prefix(128)
            .description
    }

    private func generateCodeChallenge(from verifier: String) -> String? {
        guard let data = verifier.data(using: .ascii) else { return nil }
        let hash = SHA256.hash(data: data)
        return Data(hash)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

extension SpotifyAuthService: @preconcurrency ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = scene.windows.first else {
                return ASPresentationAnchor()
            }
            return window
        }
    }
}
