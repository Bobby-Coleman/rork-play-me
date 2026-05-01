import SwiftUI
import UIKit

/// "Open in Spotify" / "Open in Apple Music" pill. The caller picks the
/// service — typically `appState.preferredMusicService` so we honor the
/// choice the user made at onboarding. Spotify path optionally takes a
/// pre-resolved URL (from an iTunes Apple-Music-URL handoff) so callers
/// that already resolved it once don't pay for a second network round-trip.
///
/// `shareId`, when non-nil, enables one-shot Firestore writeback: the
/// moment we successfully resolve a Spotify URI for a share that was
/// persisted without one (usually because send-time enrichment hit a
/// 429), we patch `shares/{id}.song.spotifyURI`. Every other device
/// that later views the same share skips song.link entirely.
@MainActor
func openInServiceButton(
    song: Song,
    service: MusicService,
    resolvedSpotifyURL: String? = nil,
    shareId: String? = nil,
    onOpened: (() -> Void)? = nil
) -> some View {
    Button {
        Task {
            let opened = await openInService(song: song, service: service, resolvedSpotifyURL: resolvedSpotifyURL, shareId: shareId)
            if opened {
                onOpened?()
            }
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
private func openInService(song: Song, service: MusicService, resolvedSpotifyURL: String?, shareId: String? = nil) async -> Bool {
    switch service {
    case .appleMusic:
        if let url = appleMusicURL(for: song) {
            return await openURL(url)
        }
        return false

    case .spotify:
        let hasURI = song.spotifyURI != nil
        let hasAM = song.appleMusicURL != nil
        print("event=open_in_spotify start title=\"\(song.title)\" artist=\"\(song.artist)\" hasSpotifyURI=\(hasURI) hasAppleMusicURL=\(hasAM) hasPrefetchedSpotifyURL=\(resolvedSpotifyURL != nil) shareId=\(shareId ?? "nil")")

        var candidateResolvedURL = resolvedSpotifyURL

        if SpotifyDeepLinkResolver.spotifyTrackID(for: song, resolvedSpotifyURL: candidateResolvedURL) == nil,
           let appleMusicURL = song.appleMusicURL {
            print("event=open_in_spotify resolve_attempt reason=missing_track_id amURL=\"\(appleMusicURL)\"")
            let newlyResolved = await MusicSearchService.shared.resolveSpotifyURL(appleMusicURL: appleMusicURL, title: song.title, artist: song.artist)
            candidateResolvedURL = newlyResolved

            // Writeback: if we got a hit AND we have a share context,
            // patch the share doc so every other viewer skips songlink.
            // Only the FIRST viewer of a share without a URI pays this
            // write; all subsequent viewers read the URI from Firestore.
            if let resolvedURL = newlyResolved,
               let trackID = SpotifyDeepLinkResolver.spotifyTrackID(fromSpotifyURL: resolvedURL),
               let shareId,
               !shareId.isEmpty,
               song.spotifyURI == nil {
                let uri = "spotify:track:\(trackID)"
                print("event=open_in_spotify firestore_writeback shareId=\(shareId) uri=\(uri)")
                Task { await FirebaseService.shared.patchShareSpotifyURI(shareId: shareId, spotifyURI: uri) }
            }
        } else if SpotifyDeepLinkResolver.spotifyTrackID(for: song, resolvedSpotifyURL: candidateResolvedURL) == nil {
            print("event=open_in_spotify resolve_skipped reason=no_apple_music_url title=\"\(song.title)\"")
        }

        if let trackURL = SpotifyDeepLinkResolver.trackURL(for: song, resolvedSpotifyURL: candidateResolvedURL) {
            let openedInApp = await openURL(trackURL, universalLinksOnly: true)
            print("event=open_in_spotify handoff kind=universal opened=\(openedInApp) url=\"\(trackURL.absoluteString)\"")
            if openedInApp {
                return true
            }
            if let uri = SpotifyDeepLinkResolver.trackURI(for: song, resolvedSpotifyURL: candidateResolvedURL) {
                let openedViaURI = await openURL(uri)
                print("event=open_in_spotify handoff kind=uri opened=\(openedViaURI) url=\"\(uri.absoluteString)\"")
                if openedViaURI {
                    return true
                }
            }
            let openedInSafari = await openURL(trackURL)
            print("event=open_in_spotify handoff kind=safari opened=\(openedInSafari) url=\"\(trackURL.absoluteString)\"")
            return openedInSafari
        } else if let searchURL = SpotifyDeepLinkResolver.spotifySearchURL(for: song) {
            let openedSearch = await openURL(searchURL)
            print("event=open_in_spotify handoff kind=search opened=\(openedSearch) url=\"\(searchURL.absoluteString)\" reason=no_track_id")
            return openedSearch
        } else {
            print("event=open_in_spotify handoff kind=none reason=no_track_id_no_search_url title=\"\(song.title)\"")
            return false
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
