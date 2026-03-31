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

nonisolated struct SpotifyUserProfile: Codable, Sendable {
    let id: String
    let display_name: String?
}

nonisolated struct SpotifySavedTracksResponse: Codable, Sendable {
    let items: [SpotifySavedTrackItem]
}

nonisolated struct SpotifySavedTrackItem: Codable, Sendable {
    let track: SpotifyTrack
}

nonisolated struct SpotifyTrack: Codable, Sendable {
    let id: String
    let name: String
    let uri: String
    let duration_ms: Int
    let preview_url: String?
    let artists: [SpotifyArtist]
    let album: SpotifyAlbum
}

nonisolated struct SpotifyArtist: Codable, Sendable {
    let name: String
}

nonisolated struct SpotifyAlbum: Codable, Sendable {
    let images: [SpotifyImage]
}

nonisolated struct SpotifyImage: Codable, Sendable {
    let url: String
    let width: Int?
    let height: Int?
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
    private let scopes = "user-read-private user-read-email user-library-read streaming app-remote-control user-modify-playback-state user-read-playback-state"

    private var clientID: String {
        let id = Config.EXPO_PUBLIC_SPOTIFY_CLIENT_ID
        return id.isEmpty ? "10ac0a719f3e4135a2d3fd857c67d0f6" : id
    }

    init() {
        accessToken = UserDefaults.standard.string(forKey: "spotifyAccessToken")
        refreshToken = UserDefaults.standard.string(forKey: "spotifyRefreshToken")
        userDisplayName = UserDefaults.standard.string(forKey: "spotifyDisplayName")
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

    var userDisplayName: String? {
        didSet { UserDefaults.standard.set(userDisplayName, forKey: "spotifyDisplayName") }
    }

    func fetchUserProfile() async {
        guard let token = accessToken else { return }
        var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/me")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return }
            let profile = try JSONDecoder().decode(SpotifyUserProfile.self, from: data)
            userDisplayName = profile.display_name ?? profile.id
        } catch {}
    }

    func fetchRecentSavedTrack() async -> Song? {
        guard let token = accessToken else { return nil }
        var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/tracks?limit=1")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return nil }
            let saved = try JSONDecoder().decode(SpotifySavedTracksResponse.self, from: data)
            guard let item = saved.items.first else { return nil }
            let track = item.track
            let artURL = track.album.images.first?.url ?? ""
            let durationSec = track.duration_ms / 1000
            let mins = durationSec / 60
            let secs = durationSec % 60
            let duration = "\(mins):\(String(format: "%02d", secs))"
            return Song(
                id: track.id,
                title: track.name,
                artist: track.artists.map(\.name).joined(separator: ", "),
                albumArtURL: artURL,
                duration: duration,
                spotifyURI: track.uri,
                previewURL: track.preview_url
            )
        } catch {
            return nil
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
