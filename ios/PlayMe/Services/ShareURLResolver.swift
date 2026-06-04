import Foundation

/// Turns a music link shared into Riff from another app (Spotify or Apple
/// Music, via the RiffShare Share Extension) into a full catalog `Song` the
/// app can send.
///
/// Both services put a track URL on the iOS share sheet:
///   - Apple Music: `https://music.apple.com/<store>/album/<name>/<albumId>?i=<trackId>`
///   - Spotify:     `https://open.spotify.com/track/<trackId>` (or `spotify:track:<id>`)
///
/// Apple Music resolves directly through `AppleMusicSearchService` (we own a
/// developer token). Spotify has no client-side Web API, so we bounce the
/// link through Odesli to get the matching Apple Music link / metadata and
/// then resolve that. Resolution always runs in the **main app** (not the
/// extension) so it can reuse the MusicKit token + Firebase auth.
enum ShareURLResolver {

    /// Resolves a shared link into a `Song`, or `nil` if it isn't a
    /// recognizable single-track music link we can map to the catalog.
    static func resolveSong(fromShareURL rawURL: String) async -> Song? {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lowered = trimmed.lowercased()
        if lowered.contains("music.apple.com") {
            return await resolveAppleMusic(urlString: trimmed)
        }
        if lowered.contains("open.spotify.com") || lowered.hasPrefix("spotify:") {
            return await resolveSpotify(urlString: trimmed)
        }
        return nil
    }

    // MARK: - Apple Music

    private static func resolveAppleMusic(urlString: String) async -> Song? {
        guard let trackId = SpotifyDeepLinkResolver.appleMusicTrackID(fromAppleMusicURL: urlString) else {
            print("event=share_import resolve_result service=apple status=no_track_id url=\"\(urlString)\"")
            return nil
        }
        let song = await AppleMusicSearchService.shared.lookupSong(
            appleMusicID: trackId, isrc: nil, title: "", artist: ""
        )
        print("event=share_import resolve_result service=apple status=\(song == nil ? "miss" : "ok") trackId=\(trackId)")
        return song
    }

    // MARK: - Spotify

    private static func resolveSpotify(urlString: String) async -> Song? {
        // Normalize `spotify:track:<id>` URIs to an https URL Odesli accepts.
        let httpsURL: String
        if urlString.hasPrefix("spotify:"),
           let id = SpotifyDeepLinkResolver.spotifyTrackID(for:
                Song(id: "", title: "", artist: "", albumArtURL: "", duration: "", spotifyURI: urlString),
                resolvedSpotifyURL: nil) {
            httpsURL = "https://open.spotify.com/track/\(id)"
        } else {
            httpsURL = urlString
        }

        let lookup = await MusicSearchService.shared.appleMusicLink(forSpotifyURL: httpsURL)

        // Primary: Odesli gave us an Apple Music link with a track selector.
        if let amURL = lookup?.appleMusicURL,
           let trackId = SpotifyDeepLinkResolver.appleMusicTrackID(fromAppleMusicURL: amURL),
           let song = await AppleMusicSearchService.shared.lookupSong(
                appleMusicID: trackId, isrc: nil, title: "", artist: "") {
            print("event=share_import resolve_result service=spotify status=ok_via_apple_link trackId=\(trackId)")
            return song
        }

        // Fallback: catalog text search using the title/artist Odesli reported.
        if let title = lookup?.title, !title.isEmpty {
            let artist = lookup?.artist ?? ""
            let term = "\(title) \(artist)".trimmingCharacters(in: .whitespaces)
            let results = await AppleMusicSearchService.shared.searchExpanded(term: term, limit: 5)
            print("event=share_import resolve_result service=spotify status=\(results.songs.isEmpty ? "miss_text" : "ok_via_text") term=\"\(term)\"")
            return results.songs.first
        }

        print("event=share_import resolve_result service=spotify status=miss url=\"\(httpsURL)\"")
        return nil
    }
}
