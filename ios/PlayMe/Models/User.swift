import Foundation

nonisolated struct AppUser: Identifiable, Hashable, Sendable {
    let id: String
    let firstName: String
    let lastName: String
    let username: String
    let phone: String
    let avatarURL: String?

    init(id: String, firstName: String, lastName: String = "", username: String, phone: String, avatarURL: String? = nil) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.username = username
        self.phone = phone
        self.avatarURL = avatarURL
    }

    /// Single letter shown on avatar fallbacks: first letter of the first
    /// name (username as a backup for users with no first name).
    var initials: String {
        let first = firstName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1).uppercased()
        if !first.isEmpty { return first }
        let fallback = username.prefix(1).uppercased()
        return fallback.isEmpty ? "?" : fallback
    }
}
