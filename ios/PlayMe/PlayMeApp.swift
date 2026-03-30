import SwiftUI

@main
struct PlayMeApp: App {
    @State private var spotifyAuth = SpotifyAuthService.shared

    var body: some Scene {
        WindowGroup {
            ContentView(spotifyAuth: spotifyAuth)
                .onOpenURL { url in
                    guard url.scheme == "playme", url.host == "spotify-callback" else { return }
                    Task {
                        await spotifyAuth.handleCallback(url: url)
                    }
                }
        }
    }
}
