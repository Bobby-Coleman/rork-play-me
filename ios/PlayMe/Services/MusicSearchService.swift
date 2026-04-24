import Foundation
import FirebaseAuth

/// Resolves an Apple-Music song URL (what MusicKit returns) into the
/// equivalent Spotify track URL so Spotify-preferring users land on the
/// actual track page and autoplay, instead of a search fallback. Catalog
/// search itself lives in `AppleMusicSearchService`.
///
/// ## Resolution pipeline
///
/// For a given Apple Music URL we try, in order:
///
///   1. **Local in-memory cache** (this process, this launch). Instant.
///   2. **Local disk cache** (`UserDefaults`, 30-day TTL). ~5 ms.
///   3. **Global Firestore cache** (`spotifyResolutions/{sha256(amURL)}`).
///      Shared across every PlayMe user on Earth — once any device has
///      successfully resolved a song, every other device skips network
///      resolution forever. ~30 ms.
///   4. **Primary resolver: PlayMe Cloud Function** → Spotify Web API
///      `/search` via Client Credentials flow. App-wide rate limit
///      (~180 req/min) is shared by the whole backend, so the client
///      never self-limits. ~200 ms.
///   5. **Fallback resolver: Odesli (song.link)**. Anonymous tier
///      (~10 req/min/IP) is punishing in practice but still occasionally
///      succeeds when the Cloud Function is cold or upstream hiccups.
///      ~500 ms.
///   6. **Nothing works** → return `nil` → caller falls back to
///      `spotify:search://` handoff.
///
/// Every success on steps 4 or 5 writes back to layers 1, 2, **and** 3,
/// so the next viewer anywhere in the world short-circuits at step 3.
nonisolated struct SonglinkResponse: Codable, Sendable {
    let linksByPlatform: [String: SonglinkPlatformLink]?
}

nonisolated struct SonglinkPlatformLink: Codable, Sendable {
    let url: String?
}

/// Decoded response from our `resolveSpotifyTrack` Cloud Function.
nonisolated struct CloudFunctionResolutionResponse: Codable, Sendable {
    let trackId: String?
    let spotifyURL: String?
    let matchedTitle: String?
    let matchedArtist: String?
    let error: String?
}

actor MusicSearchService {
    static let shared = MusicSearchService()

    // Session hot cache — mirrors a subset of the disk cache plus any
    // resolutions that arrived this launch. Keyed by the NORMALIZED
    // Apple Music URL so casing and tracking-param variance don't poison
    // the cache. Values are full https Spotify URLs; callers extract the
    // track ID as needed via `SpotifyDeepLinkResolver`.
    private var songlinkCache: [String: String] = [:]

    // Global cooldown for the Odesli fallback. When we see a 429 on the
    // song.link side, every caller skips step 5 for the next 60 s so we
    // don't waste the Cloud Function fallback path on a known-bad state.
    // The Cloud Function itself has its own rate-limit handling.
    private var odesliCooldownUntil: Date? = nil

    // Disk cache file (UserDefaults key + TTL).
    private let diskCacheKey = "PlayMe.SonglinkCache.v1"
    private let diskCacheTTL: TimeInterval = 30 * 24 * 3600

    private struct DiskEntry: Codable {
        let spotifyURL: String
        let resolvedAt: Date
    }

    init() {
        loadDiskCacheIntoMemory()
    }

    /// Resolves an Apple Music song URL to the canonical Spotify track
    /// URL. `title` and `artist` are used as Spotify `/search` inputs
    /// in the Cloud Function path — they're always available from the
    /// `Song` that owns the `appleMusicURL`, so this signature is cheap
    /// for callers. Returns `nil` when every resolver path failed —
    /// callers should fall back to a `spotify:search://` handoff.
    /// Successful resolutions populate every cache layer automatically.
    func resolveSpotifyURL(appleMusicURL: String, title: String, artist: String) async -> String? {
        let normalized = Self.normalizeAppleMusicURL(appleMusicURL)

        // Layer 1+2: local cache (in-memory backed by disk).
        if let cached = songlinkCache[normalized] {
            print("event=open_in_spotify resolve_result source=cache_local spotifyURL=\"\(cached)\" amURL=\"\(appleMusicURL)\"")
            return cached
        }

        // Layer 3: global Firestore cache. Cheap Firestore read; on a
        // hit we warm the local caches so we never look it up again
        // from this device.
        if let globalHit = await FirebaseService.shared.fetchSpotifyResolution(normalizedAmURL: normalized) {
            songlinkCache[normalized] = globalHit.spotifyURL
            persistToDisk()
            print("event=open_in_spotify resolve_result source=cache_global spotifyURL=\"\(globalHit.spotifyURL)\" amURL=\"\(appleMusicURL)\"")
            return globalHit.spotifyURL
        }

        // Layer 4: primary resolver — PlayMe Cloud Function hitting
        // Spotify Web API /search. This is the path that OWNS resolving
        // new songs at scale; Odesli is just insurance.
        if let resolved = await performCloudFunctionRequest(normalizedAmURL: normalized, title: title, artist: artist) {
            songlinkCache[normalized] = resolved.spotifyURL
            persistToDisk()
            await FirebaseService.shared.writeSpotifyResolution(
                normalizedAmURL: normalized,
                trackId: resolved.trackId,
                spotifyURL: resolved.spotifyURL,
                source: "spotify_api"
            )
            return resolved.spotifyURL
        }

        // Layer 5: fallback resolver — Odesli. Skipped during cooldown.
        if let until = odesliCooldownUntil, Date() < until {
            let remaining = Int(until.timeIntervalSince(Date()))
            print("event=open_in_spotify resolve_result source=odesli_cooldown remaining_s=\(remaining) amURL=\"\(appleMusicURL)\"")
            return nil
        }
        if let spotifyURL = await performSonglinkRequest(appleMusicURL: appleMusicURL, attempt: 1) {
            songlinkCache[normalized] = spotifyURL
            persistToDisk()
            if let trackId = SpotifyDeepLinkResolver.spotifyTrackID(fromSpotifyURL: spotifyURL) {
                await FirebaseService.shared.writeSpotifyResolution(
                    normalizedAmURL: normalized,
                    trackId: trackId,
                    spotifyURL: spotifyURL,
                    source: "songlink"
                )
            }
            return spotifyURL
        }

        return nil
    }

    // MARK: - URL normalization

    /// Derives a stable cache key from any Apple Music URL variation.
    /// Collapses case, drops tracking params (`uo`, `at`, `mt`, `app`,
    /// affiliate tokens) that differ across senders for the same song,
    /// and keeps only the `i=<trackId>` selector that identifies the
    /// actual track inside an album URL. The result is the same for
    /// every device that ever encounters the same song, which is the
    /// whole point of the global Firestore cache.
    static func normalizeAppleMusicURL(_ raw: String) -> String {
        guard var components = URLComponents(string: raw) else {
            return raw.lowercased()
        }
        let keptQuery = components.queryItems?.filter { $0.name == "i" } ?? []
        components.queryItems = keptQuery.isEmpty ? nil : keptQuery
        components.fragment = nil
        components.host = components.host?.lowercased()
        components.path = components.path.lowercased()
        return components.string ?? raw.lowercased()
    }

    // MARK: - Disk cache

    private func loadDiskCacheIntoMemory() {
        guard let data = UserDefaults.standard.data(forKey: diskCacheKey) else { return }
        guard let decoded = try? JSONDecoder().decode([String: DiskEntry].self, from: data) else { return }
        let now = Date()
        var kept: Int = 0
        for (key, entry) in decoded where now.timeIntervalSince(entry.resolvedAt) < diskCacheTTL {
            songlinkCache[key] = entry.spotifyURL
            kept += 1
        }
        print("event=open_in_spotify cache_loaded entries=\(kept) total_on_disk=\(decoded.count)")
    }

    private func persistToDisk() {
        let entries: [String: DiskEntry] = songlinkCache.mapValues {
            DiskEntry(spotifyURL: $0, resolvedAt: Date())
        }
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: diskCacheKey)
    }

    // MARK: - Primary resolver: Cloud Function (Spotify Web API)

    private struct CloudFunctionHit {
        let trackId: String
        let spotifyURL: String
    }

    /// Calls our `resolveSpotifyTrack` Cloud Function, which holds the
    /// Spotify client secret server-side and hits `/v1/search` via
    /// Client Credentials flow. Returns `nil` on any failure so the
    /// caller falls through to the Odesli fallback.
    private func performCloudFunctionRequest(normalizedAmURL: String, title: String, artist: String) async -> CloudFunctionHit? {
        guard let endpoint = Self.resolveSpotifyTrackEndpoint else {
            print("event=open_in_spotify resolve_result source=cloudfn_no_endpoint amURL=\"\(normalizedAmURL)\"")
            return nil
        }
        guard let user = Auth.auth().currentUser else {
            // No Firebase Auth session — the function requires a Bearer
            // ID token for abuse protection, so we can't call it. Fall
            // through to Odesli.
            print("event=open_in_spotify resolve_result source=cloudfn_unauthenticated amURL=\"\(normalizedAmURL)\"")
            return nil
        }

        let idToken: String
        do {
            idToken = try await user.getIDToken()
        } catch {
            print("event=open_in_spotify resolve_result source=cloudfn_id_token_failed error=\"\(error.localizedDescription)\" amURL=\"\(normalizedAmURL)\"")
            return nil
        }

        let body: [String: Any] = [
            "title": title,
            "artist": artist,
            "amURL": normalizedAmURL
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])

        print("event=open_in_spotify resolve_attempt source=cloudfn url=\"\(endpoint.absoluteString)\" amURL=\"\(normalizedAmURL)\"")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return nil }

            guard (200...299).contains(http.statusCode) else {
                let bodyString = String(data: data, encoding: .utf8) ?? ""
                print("event=open_in_spotify resolve_result source=cloudfn status=http_\(http.statusCode) body=\"\(bodyString.prefix(200))\" amURL=\"\(normalizedAmURL)\"")
                return nil
            }

            let decoded: CloudFunctionResolutionResponse
            do {
                decoded = try JSONDecoder().decode(CloudFunctionResolutionResponse.self, from: data)
            } catch {
                print("event=open_in_spotify resolve_result source=cloudfn status=decode_fail error=\"\(error)\" amURL=\"\(normalizedAmURL)\"")
                return nil
            }

            if let err = decoded.error, !err.isEmpty {
                print("event=open_in_spotify resolve_result source=cloudfn status=error error=\"\(err)\" amURL=\"\(normalizedAmURL)\"")
                return nil
            }

            guard let trackId = decoded.trackId, !trackId.isEmpty,
                  let spotifyURL = decoded.spotifyURL, !spotifyURL.isEmpty else {
                print("event=open_in_spotify resolve_result source=cloudfn status=no_match amURL=\"\(normalizedAmURL)\"")
                return nil
            }

            print("event=open_in_spotify resolve_result source=cloudfn status=ok trackId=\(trackId) spotifyURL=\"\(spotifyURL)\" matchedTitle=\"\(decoded.matchedTitle ?? "")\" matchedArtist=\"\(decoded.matchedArtist ?? "")\" amURL=\"\(normalizedAmURL)\"")
            return CloudFunctionHit(trackId: trackId, spotifyURL: spotifyURL)
        } catch {
            print("event=open_in_spotify resolve_result source=cloudfn status=network_error error=\"\(error.localizedDescription)\" amURL=\"\(normalizedAmURL)\"")
            return nil
        }
    }

    private static let resolveSpotifyTrackEndpoint: URL? = {
        let region = "us-central1"
        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: path),
              let projectId = dict["PROJECT_ID"] as? String, !projectId.isEmpty else {
            return nil
        }
        return URL(string: "https://\(region)-\(projectId).cloudfunctions.net/resolveSpotifyTrack")
    }()

    // MARK: - Fallback resolver: Odesli (song.link)

    private func performSonglinkRequest(appleMusicURL: String, attempt: Int) async -> String? {
        guard var components = URLComponents(string: "https://api.song.link/v1-alpha.1/links") else {
            return nil
        }

        var queryItems: [URLQueryItem] = [URLQueryItem(name: "url", value: appleMusicURL)]
        let apiKey = Config.SONGLINK_API_KEY
        if !apiKey.isEmpty {
            queryItems.append(URLQueryItem(name: "key", value: apiKey))
        }
        components.queryItems = queryItems

        guard let url = components.url else { return nil }

        print("event=open_in_spotify resolve_attempt source=songlink attempt=\(attempt) url=\"\(url.absoluteString)\" authenticated=\(!apiKey.isEmpty)")

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse else { return nil }

            if http.statusCode == 429 {
                let cooldown: TimeInterval = 60
                odesliCooldownUntil = Date().addingTimeInterval(cooldown)
                print("event=open_in_spotify resolve_result source=songlink status=http_429 attempt=\(attempt) cooldown_s=\(Int(cooldown)) amURL=\"\(appleMusicURL)\"")

                if attempt == 1 {
                    do {
                        try await Task.sleep(for: .seconds(cooldown))
                    } catch {
                        return nil
                    }
                    return await performSonglinkRequest(appleMusicURL: appleMusicURL, attempt: attempt + 1)
                }
                return nil
            }

            guard (200...299).contains(http.statusCode) else {
                print("event=open_in_spotify resolve_result source=songlink status=http_\(http.statusCode) amURL=\"\(appleMusicURL)\"")
                return nil
            }

            let decoded: SonglinkResponse
            do {
                decoded = try JSONDecoder().decode(SonglinkResponse.self, from: data)
            } catch {
                print("event=open_in_spotify resolve_result source=songlink status=decode_fail error=\"\(error)\" amURL=\"\(appleMusicURL)\"")
                return nil
            }

            if let spotifyURL = decoded.linksByPlatform?["spotify"]?.url {
                print("event=open_in_spotify resolve_result source=songlink status=ok attempt=\(attempt) spotifyURL=\"\(spotifyURL)\" amURL=\"\(appleMusicURL)\"")
                return spotifyURL
            }

            let platforms = decoded.linksByPlatform?.keys.sorted().joined(separator: ",") ?? ""
            print("event=open_in_spotify resolve_result source=songlink status=no_spotify_platform platforms=\"\(platforms)\" amURL=\"\(appleMusicURL)\"")
        } catch {
            print("event=open_in_spotify resolve_result source=songlink status=network_error error=\"\(error)\" amURL=\"\(appleMusicURL)\"")
        }

        return nil
    }
}
