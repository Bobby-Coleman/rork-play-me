import Foundation

/// Builds the 10-song carousel on the "send your first song" onboarding step.
///
/// Algorithm (iTunes fan-out — no recs API exists):
///   1. If a specific `recentSong` was picked, seed the list with it.
///   2. Fetch top tracks for the `recentArtist` (same artist as the recent song or a free-typed artist).
///      These get higher weight so "more by the artist you've been listening to" appears first.
///   3. Fetch top tracks for each `favoriteArtists` entry.
///   4. Dedupe by trackId, cap to `limit` (default 10).
actor SongSuggestionsService {
    static let shared = SongSuggestionsService()

    private let search = MusicSearchService.shared

    func buildSuggestions(
        favoriteArtists: [String],
        recentArtist: String?,
        recentSong: Song?,
        limit: Int = 10
    ) async -> [Song] {
        var ordered: [Song] = []
        var seen = Set<String>()

        // 1. Seed with the specifically-picked song, if any.
        if let recentSong {
            ordered.append(recentSong)
            seen.insert(recentSong.id)
        }

        // 2. Mix in other songs from the recent artist (up to 4 picks).
        if let artist = recentArtist?.trimmingCharacters(in: .whitespaces), !artist.isEmpty {
            let tracks = (try? await search.topTracks(forArtist: artist, limit: 6)) ?? []
            for track in tracks {
                if ordered.count >= limit { break }
                if seen.insert(track.id).inserted {
                    ordered.append(track)
                }
            }
        }

        // 3. For each favorite artist, pull 1–2 top tracks, interleaved.
        //    We do two passes so each artist gets one pick before any gets a second.
        let favs = favoriteArtists
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let perArtistTracks = await withTaskGroup(of: (String, [Song]).self) { group in
            for artist in favs {
                group.addTask {
                    let tracks = (try? await self.search.topTracks(forArtist: artist, limit: 4)) ?? []
                    return (artist, tracks)
                }
            }
            var out: [String: [Song]] = [:]
            for await (artist, tracks) in group {
                out[artist] = tracks
            }
            return out
        }

        for pass in 0..<2 {
            for artist in favs {
                if ordered.count >= limit { break }
                let tracks = perArtistTracks[artist] ?? []
                guard pass < tracks.count else { continue }
                let track = tracks[pass]
                if seen.insert(track.id).inserted {
                    ordered.append(track)
                }
            }
        }

        // 4. Fallback: if we still don't have enough (e.g. user skipped everything),
        //    pad with a plain iTunes search of the first favorite or recent term.
        if ordered.count < limit {
            let fallbackTerm = favs.first ?? recentArtist ?? ""
            if !fallbackTerm.isEmpty {
                let extra = (try? await search.search(term: fallbackTerm, limit: limit * 2)) ?? []
                for track in extra {
                    if ordered.count >= limit { break }
                    if seen.insert(track.id).inserted {
                        ordered.append(track)
                    }
                }
            }
        }

        return Array(ordered.prefix(limit))
    }
}
