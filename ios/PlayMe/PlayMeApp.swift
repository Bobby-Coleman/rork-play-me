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
                    if let code = sdkParams?[SPTAppRemoteAccessTokenKey], !code.isEmpty {
                        spotifyAuth.setDirectToken(code)
                        playbackService.pendingAuthCode = code
                        playbackService.connectWithToken(code)
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
