import Foundation

/// Lightweight, UI-agnostic model used by the ambient album-art grid on the
/// Discovery screen. Deliberately decoupled from the richer `Song` model so the
/// grid can be driven by any source (charts, curated, algorithmic) without the
/// view knowing the origin.
struct GridSong: Identifiable, Hashable, Sendable, Codable {
    let id: String
    let albumArtURL: String
    let title: String?
    let artist: String?

    init(id: String, albumArtURL: String, title: String? = nil, artist: String? = nil) {
        self.id = id
        self.albumArtURL = albumArtURL
        self.title = title
        self.artist = artist
    }
}
