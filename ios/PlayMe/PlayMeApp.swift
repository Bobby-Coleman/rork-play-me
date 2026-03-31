import SwiftUI
import SpotifyiOS

@main
struct PlayMeApp: App {
    @State private var spotifyAuth = SpotifyAuthService.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView(spotifyAuth: spotifyAuth)
                .onOpenURL { url in
                    guard url.scheme == "playme" else { return }

                    let playbackService = SpotifyPlaybackService.shared

                    if let params = playbackService.authParameters(from: url),
                       let token = params[SPTAppRemoteAccessTokenKey], !token.isEmpty {
                        spotifyAuth.accessToken = token
                        playbackService.connect()
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
