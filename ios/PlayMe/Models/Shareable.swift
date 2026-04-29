import Foundation

/// Anything that can be sent to one or more friends through the unified
/// share view (`FriendSelectorView`). Songs, whole albums, and whole
/// mixtapes all flow through the same picker — only the artwork, title
/// strip, preview affordance, and final dispatch differ — so this enum
/// is the type-erased payload that lets the share view render and send
/// without caring which kind it is.
///
/// Identity is encoded with a kind prefix so a song and a mixtape that
/// happen to share an underlying String id never collide in
/// `.sheet(item:)` or `Set<Shareable>` containers.
enum Shareable: Identifiable, Hashable {
    case song(Song)
    case album(Album)
    case mixtape(Mixtape)

    var id: String {
        switch self {
        case .song(let s):    return "song:\(s.id)"
        case .album(let a):   return "album:\(a.id)"
        case .mixtape(let m): return "mixtape:\(m.id)"
        }
    }

    /// Primary line shown under the artwork (song title / album name /
    /// mixtape name). Always non-empty by construction.
    var title: String {
        switch self {
        case .song(let s):    return s.title
        case .album(let a):   return a.name
        case .mixtape(let m): return m.name
        }
    }

    /// Secondary line: artist for song/album, song-count caption for a
    /// mixtape. Returns an empty string when there's nothing meaningful
    /// to render so callers can skip the row without an extra branch.
    var subtitle: String {
        switch self {
        case .song(let s):
            return s.artist
        case .album(let a):
            return a.artistName ?? ""
        case .mixtape(let m):
            return "\(m.songCount) song\(m.songCount == 1 ? "" : "s")"
        }
    }

    /// Square artwork URL. Songs use `albumArtURL`, albums use
    /// `artworkURL`, mixtapes have no single image (they composite from
    /// their songs in `MixtapeCoverView`) so this returns nil for
    /// mixtapes — the share view branches on `case .mixtape` and uses
    /// `MixtapeCoverView` directly.
    var artworkURL: String? {
        switch self {
        case .song(let s):    return s.albumArtURL
        case .album(let a):   return a.artworkURL
        case .mixtape:        return nil
        }
    }

    /// Convenience: type kind for switch-only call sites that don't
    /// need the associated value (e.g. "is the preview-controls row
    /// visible?").
    var kind: Kind {
        switch self {
        case .song:    return .song
        case .album:   return .album
        case .mixtape: return .mixtape
        }
    }

    enum Kind { case song, album, mixtape }

    /// Underlying `Song` if this shareable wraps a song, else nil. Used
    /// by the preview-controls row, which only audition songs.
    var song: Song? {
        if case .song(let s) = self { return s }
        return nil
    }
}
