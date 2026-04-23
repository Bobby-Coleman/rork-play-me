import Foundation

/// Deezer public API is the free (no-auth) source of truth for artist
/// photos — iTunes Search doesn't expose them. We only use Deezer for
/// this single field; everything else stays on iTunes.
private struct DeezerArtistSearchResponse: Codable {
    let data: [DeezerArtistHit]
}

private struct DeezerArtistHit: Codable {
    let id: Int?
    let name: String?
    /// Deezer's largest served artist photo (1000x1000).
    let picture_xl: String?
    /// Fallback sizes if xl isn't present on an older artist row.
    let picture_big: String?
    let picture_medium: String?
}

/// Resolves artist display images from Deezer. Keyed by normalized name;
/// any nil/error result is cached as "miss" so we don't hammer the API on
/// repeat misses either.
actor ArtistImageService {
    static let shared = ArtistImageService()

    private enum CacheEntry {
        case hit(String)
        case miss
    }

    private var cache: [String: CacheEntry] = [:]

    /// Returns Deezer's best artist image URL for `name`, or nil if Deezer
    /// has no sufficiently-confident match. Safe to call on every render —
    /// results are memoized for the session.
    func imageURL(forName name: String) async -> String? {
        let key = Self.normalize(name)
        guard !key.isEmpty else { return nil }

        if let cached = cache[key] {
            if case .hit(let url) = cached { return url }
            return nil
        }

        guard let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.deezer.com/search/artist?q=\(encoded)&limit=1") else {
            cache[key] = .miss
            return nil
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                cache[key] = .miss
                return nil
            }
            let decoded = try JSONDecoder().decode(DeezerArtistSearchResponse.self, from: data)
            guard let hit = decoded.data.first,
                  let hitName = hit.name,
                  Self.normalize(hitName) == key else {
                // Guards against "Drake" matching a tribute act — we require
                // the Deezer artist's name to round-trip to the same
                // normalized form as the input.
                cache[key] = .miss
                return nil
            }
            let picked = hit.picture_xl ?? hit.picture_big ?? hit.picture_medium
            if let picked, !picked.isEmpty {
                cache[key] = .hit(picked)
                return picked
            }
            cache[key] = .miss
            return nil
        } catch is CancellationError {
            // Rapid-typing flows cancel in-flight requests by design. Don't
            // poison the cache with a miss for a valid artist name just
            // because the user kept typing — the next real attempt should
            // be allowed to hit the network again.
            return nil
        } catch {
            // URLSession surfaces cancellation as NSURLErrorCancelled rather
            // than a Swift CancellationError on some OS versions. Treat the
            // same way so cancellations never become permanent misses.
            if (error as NSError).code == NSURLErrorCancelled {
                return nil
            }
            cache[key] = .miss
            return nil
        }
    }

    /// Lowercased, whitespace-trimmed, diacritics-stripped. "Beyoncé" ==
    /// "beyonce" so a Deezer hit still matches when iTunes drops the accent.
    private static func normalize(_ s: String) -> String {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        let folded = trimmed.folding(options: .diacriticInsensitive, locale: .current)
        return folded.lowercased()
    }
}
