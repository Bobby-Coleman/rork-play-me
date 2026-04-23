import SwiftUI
import UIKit

/// "Open in Spotify" / "Open in Apple Music" pill. The caller picks the
/// service — typically `appState.preferredMusicService` so we honor the
/// choice the user made at onboarding. Spotify path optionally takes a
/// pre-resolved URL (from an iTunes Apple-Music-URL handoff) so callers
/// that already resolved it once don't pay for a second network round-trip.
@MainActor
func openInServiceButton(song: Song, service: MusicService, resolvedSpotifyURL: String? = nil) -> some View {
    Button {
        Task {
            await openInService(song: song, service: service, resolvedSpotifyURL: resolvedSpotifyURL)
        }
    } label: {
        HStack(spacing: 6) {
            Image(systemName: "arrow.up.right")
                .font(.system(size: 11, weight: .semibold))
            Text(service == .spotify ? "Open in Spotify" : "Open in Apple Music")
                .font(.system(size: 13, weight: .medium))
        }
        .foregroundStyle(.white.opacity(0.6))
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.08))
        .clipShape(.capsule)
    }
}

@MainActor
private func openInService(song: Song, service: MusicService, resolvedSpotifyURL: String?) async {
    switch service {
    case .appleMusic:
        if let url = appleMusicURL(for: song) {
            _ = await openURL(url)
        }

    case .spotify:
        var candidateResolvedURL = resolvedSpotifyURL

        if SpotifyDeepLinkResolver.spotifyTrackID(for: song, resolvedSpotifyURL: candidateResolvedURL) == nil,
           let appleMusicURL = song.appleMusicURL {
            candidateResolvedURL = await MusicSearchService.shared.resolveSpotifyURL(appleMusicURL: appleMusicURL)
        }

        if let trackURL = SpotifyDeepLinkResolver.trackURL(for: song, resolvedSpotifyURL: candidateResolvedURL) {
            let openedInApp = await openURL(trackURL, universalLinksOnly: true)
            if !openedInApp,
               let uri = SpotifyDeepLinkResolver.trackURI(for: song, resolvedSpotifyURL: candidateResolvedURL) {
                let openedViaURI = await openURL(uri)
                if !openedViaURI {
                    _ = await openURL(trackURL)
                }
            }
        } else if let searchURL = SpotifyDeepLinkResolver.spotifySearchURL(for: song) {
            _ = await openURL(searchURL)
        }
    }
}

private func appleMusicURL(for song: Song) -> URL? {
    if let appleMusicURL = song.appleMusicURL, let url = URL(string: appleMusicURL) {
        return url
    }

    let query = "\(song.title) \(song.artist)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
    return URL(string: "https://music.apple.com/search?term=\(query)")
}

@MainActor
private func openURL(_ url: URL, universalLinksOnly: Bool = false) async -> Bool {
    await withCheckedContinuation { continuation in
        let options: [UIApplication.OpenExternalURLOptionsKey: Any] = universalLinksOnly
            ? [.universalLinksOnly: true]
            : [:]
        UIApplication.shared.open(url, options: options) { success in
            continuation.resume(returning: success)
        }
    }
}
