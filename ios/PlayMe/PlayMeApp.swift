import SwiftUI
import SpotifyiOS
import FirebaseCore

@main
struct PlayMeApp: App {
    @State private var spotifyAuth = SpotifyAuthService.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(spotifyAuth: spotifyAuth)
                .onOpenURL { url in
                    guard url.scheme == "playme" else { return }

                    let playbackService = SpotifyPlaybackService.shared

                    let sdkParams = playbackService.authParameters(from: url)
                    let sdkToken = sdkParams?[SPTAppRemoteAccessTokenKey]

                    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                    let codeFromQuery = components?.queryItems?.first(where: { $0.name == "code" })?.value

                    let authCode = codeFromQuery ?? sdkToken

                    if let code = authCode, !code.isEmpty {
                        Task {
                            let success = await spotifyAuth.exchangeCodeViaServer(code: code)
                            if success {
                                playbackService.connect()
                            } else if let token = sdkToken, !token.isEmpty {
                                spotifyAuth.setDirectToken(token)
                                playbackService.connectWithToken(token)
                            }
                        }
                    } else if let token = sdkToken, !token.isEmpty {
                        spotifyAuth.setDirectToken(token)
                        playbackService.connectWithToken(token)
                    }
                }
                .onChange(of: scenePhase) { _, newPhase in
                    switch newPhase {
                    case .active:
                        if spotifyAuth.isAuthenticated {
                            SpotifyPlaybackService.shared.connect()
                        }
                    case .background:
                        SpotifyPlaybackService.shared.disconnect()
                    default:
                        break
                    }
                }
        }
    }
}
