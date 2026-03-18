import Foundation

nonisolated struct Song: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let artist: String
    let albumArtURL: String
    let duration: String
}
