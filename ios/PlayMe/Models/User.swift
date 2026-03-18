import Foundation

nonisolated struct AppUser: Identifiable, Hashable, Sendable {
    let id: String
    let firstName: String
    let username: String
    let phone: String

    var initials: String {
        let first = firstName.prefix(1).uppercased()
        let last = username.prefix(1).uppercased()
        return "\(first)\(last)"
    }
}
