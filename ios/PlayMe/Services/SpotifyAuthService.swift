import Foundation
import CryptoKit
import AuthenticationServices

nonisolated struct SpotifyTokenResponse: Codable, Sendable {
    let access_token: String
    let token_type: String
    let scope: String?
    let expires_in: Int
    let refresh_token: String?
}

@Observable
@MainActor
class SpotifyAuthService {
    static let shared = SpotifyAuthService()

    var accessToken: String? {
        didSet { UserDefaults.standard.set(accessToken, forKey: "spotifyAccessToken") }
    }
    var refreshToken: String? {
        didSet { UserDefaults.standard.set(refreshToken, forKey: "spotifyRefreshToken") }
    }
    var tokenExpirationDate: Date? {
        didSet {
            if let date = tokenExpirationDate {
                UserDefaults.standard.set(date.timeIntervalSince1970, forKey: "spotifyTokenExpiration")
            }
        }
    }
    var isAuthenticated: Bool { accessToken != nil }
    var isLoggingIn: Bool = false
    var authError: String?

    private var codeVerifier: String?

    private let authorizeURL = "https://accounts.spotify.com/authorize"
    private let tokenURL = "https://accounts.spotify.com/api/token"
    private let redirectURI = "playme://spotify-callback"
    private let scopes = "user-read-private user-read-email"

    private var clientID: String {
        let id = Config.EXPO_PUBLIC_SPOTIFY_CLIENT_ID
        return id.isEmpty ? "10ac0a719f3e4135a2d3fd857c67d0f6" : id
    }

    init() {
        accessToken = UserDefaults.standard.string(forKey: "spotifyAccessToken")
        refreshToken = UserDefaults.standard.string(forKey: "spotifyRefreshToken")
        let expiration = UserDefaults.standard.double(forKey: "spotifyTokenExpiration")
        if expiration > 0 {
            tokenExpirationDate = Date(timeIntervalSince1970: expiration)
        }
    }

    func startLogin() {
        authError = nil
        isLoggingIn = true

        let verifier = generateCodeVerifier()
        codeVerifier = verifier
        let challenge = generateCodeChallenge(from: verifier)

        let state = UUID().uuidString

        var components = URLComponents(string: authorizeURL)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge),
        ]

        guard let url = components.url else {
            authError = "Failed to build authorization URL"
            isLoggingIn = false
            return
        }

        UIApplication.shared.open(url)
    }

    func handleCallback(url: URL) async -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            if let error = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "error" })?.value {
                authError = "Spotify login denied: \(error)"
            } else {
                authError = "Invalid callback from Spotify"
            }
            isLoggingIn = false
            return false
        }

        guard let verifier = codeVerifier else {
            authError = "Missing code verifier"
            isLoggingIn = false
            return false
        }

        do {
            let tokenResponse = try await exchangeCodeForToken(code: code, codeVerifier: verifier)
            accessToken = tokenResponse.access_token
            refreshToken = tokenResponse.refresh_token
            tokenExpirationDate = Date().addingTimeInterval(TimeInterval(tokenResponse.expires_in))
            codeVerifier = nil
            isLoggingIn = false
            return true
        } catch {
            authError = "Failed to get access token"
            isLoggingIn = false
            return false
        }
    }

    func logout() {
        accessToken = nil
        refreshToken = nil
        tokenExpirationDate = nil
        codeVerifier = nil
        UserDefaults.standard.removeObject(forKey: "spotifyAccessToken")
        UserDefaults.standard.removeObject(forKey: "spotifyRefreshToken")
        UserDefaults.standard.removeObject(forKey: "spotifyTokenExpiration")
    }

    private nonisolated func exchangeCodeForToken(code: String, codeVerifier: String) async throws -> SpotifyTokenResponse {
        let clientID = "10ac0a719f3e4135a2d3fd857c67d0f6"
        let redirectURI = "playme://spotify-callback"
        let tokenURL = "https://accounts.spotify.com/api/token"

        var request = URLRequest(url: URL(string: tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var body = URLComponents()
        body.queryItems = [
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "code_verifier", value: codeVerifier),
        ]
        request.httpBody = body.query?.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode(SpotifyTokenResponse.self, from: data)
    }

    private func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    private func generateCodeChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash).base64URLEncodedString()
    }
}

extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
