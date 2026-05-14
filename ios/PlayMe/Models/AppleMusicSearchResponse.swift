import Foundation

/// Codable mirrors of the Apple Music HTTP API responses we consume.
///
/// All requests hit `api.music.apple.com/v1/catalog/{storefront}/...` with
/// a developer-only Bearer JWT (see `AppleMusicTokenService`). The JSON is
/// structured — Apple's catalog response shape differs slightly between
/// `/search`, `/search/suggestions`, and the per-artist views, so each
/// endpoint gets its own outer envelope. The inner resource types
/// (`AMSongResource`, `AMArtistResource`, `AMAlbumResource`) are shared
/// across endpoints and feed `AppleMusicSearchService`'s mapping helpers.
///
/// Field coverage mirrors what the old MusicKit-framework path read:
/// `attributes.name`, `artistName`, `artwork`, `durationInMillis`,
/// `previews[].url`, `releaseDate`, `genreNames`, `url` for the
/// `appleMusicURL`. Nothing more — additional fields can be appended
/// without breaking existing decoders since `Decodable` ignores
/// unrecognized keys.

// MARK: - /v1/catalog/{sf}/search

struct AMSearchResponse: Decodable {
    let results: Results

    struct Results: Decodable {
        let songs: SongsBucket?
        let artists: ArtistsBucket?
        let albums: AlbumsBucket?
    }

    struct SongsBucket: Decodable { let data: [AMSongResource] }
    struct ArtistsBucket: Decodable { let data: [AMArtistResource] }
    struct AlbumsBucket: Decodable { let data: [AMAlbumResource] }
}

// MARK: - /v1/catalog/{sf}/songs/{id} and /songs?filter[isrc]={isrc}

/// Lookup envelopes for direct song-by-id and ISRC-filter requests. Apple
/// returns the same `{ data: [AMSongResource] }` shape for both, so a
/// single decoder covers them.
struct AMSongLookupResponse: Decodable {
    let data: [AMSongResource]
}

// MARK: - /v1/catalog/{sf}/search/suggestions

/// Response shape for `kinds=topResults&types=songs,artists,albums`.
/// `results.suggestions` is a heterogeneous list keyed by `kind`; each
/// entry's `content` is the resource itself (already typed via its
/// `type` discriminator).
struct AMSearchSuggestionsResponse: Decodable {
    let results: Results

    struct Results: Decodable {
        let suggestions: [Suggestion]?
    }

    struct Suggestion: Decodable {
        let kind: String
        let content: AMTopResultContent?
    }
}

/// Discriminated union over song / artist / album, branching on the
/// resource's `type` field. Unknown types decode to `.unknown` so a
/// future Apple-side addition (e.g. music-videos in topResults) doesn't
/// fail the whole response.
enum AMTopResultContent: Decodable {
    case song(AMSongResource)
    case artist(AMArtistResource)
    case album(AMAlbumResource)
    case unknown

    private enum CodingKeys: String, CodingKey { case type }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        let single = try decoder.singleValueContainer()
        switch type {
        case "songs":
            self = .song(try single.decode(AMSongResource.self))
        case "artists":
            self = .artist(try single.decode(AMArtistResource.self))
        case "albums":
            self = .album(try single.decode(AMAlbumResource.self))
        default:
            self = .unknown
        }
    }
}

// MARK: - /v1/catalog/{sf}/artists/{id}?views=top-songs,full-albums

struct AMArtistDetailsResponse: Decodable {
    let data: [Artist]

    struct Artist: Decodable {
        let id: String
        let attributes: AMArtistResource.Attributes
        let views: Views?

        struct Views: Decodable {
            let topSongs: SongsView?
            let fullAlbums: AlbumsView?
            /// Some Apple Music storefronts return `featured-albums` as the
            /// full-discography stand-in instead of the `full-albums` view.
            /// Decode both so we can fall back if needed.
            let featuredAlbums: AlbumsView?

            enum CodingKeys: String, CodingKey {
                case topSongs = "top-songs"
                case fullAlbums = "full-albums"
                case featuredAlbums = "featured-albums"
            }

            struct SongsView: Decodable { let data: [AMSongResource] }
            struct AlbumsView: Decodable { let data: [AMAlbumResource] }
        }
    }
}

// MARK: - Resource types

struct AMSongResource: Decodable {
    let id: String
    let attributes: Attributes

    struct Attributes: Decodable {
        let name: String
        let artistName: String
        let albumName: String?
        let durationInMillis: Int?
        let releaseDate: String?
        let genreNames: [String]?
        let artwork: AMArtwork?
        let previews: [Preview]?
        let url: String?

        struct Preview: Decodable { let url: String? }
    }
}

struct AMArtistResource: Decodable {
    let id: String
    let attributes: Attributes

    struct Attributes: Decodable {
        let name: String
        let genreNames: [String]?
        let artwork: AMArtwork?
        let url: String?
    }
}

struct AMAlbumResource: Decodable {
    let id: String
    let attributes: Attributes

    struct Attributes: Decodable {
        let name: String
        let artistName: String
        let releaseDate: String?
        let trackCount: Int?
        let genreNames: [String]?
        let artwork: AMArtwork?
        let url: String?
    }
}

/// Apple Music artwork descriptor. The `url` template contains literal
/// `{w}` / `{h}` placeholders — substitute the desired pixel dimensions
/// at consumption time. Mirrors the shape consumed by
/// `PlaceholderDiscoverFeedProvider` for iTunes artwork.
struct AMArtwork: Decodable {
    let url: String?
    let width: Int?
    let height: Int?

    /// Returns a concrete URL with `{w}` / `{h}` substituted. Returns nil
    /// when the underlying template is missing.
    func resolvedURL(width: Int = 600, height: Int = 600) -> String? {
        guard let template = url, !template.isEmpty else { return nil }
        return template
            .replacingOccurrences(of: "{w}", with: String(width))
            .replacingOccurrences(of: "{h}", with: String(height))
    }
}
