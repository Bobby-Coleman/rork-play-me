import Foundation

nonisolated struct AppUser: Identifiable, Hashable, Sendable {
    let id: String
    let firstName: String
    let lastName: String
    let username: String
    let phone: String

    init(id: String, firstName: String, lastName: String = "", username: String, phone: String) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.username = username
        self.phone = phone
    }

    var initials: String {
        let first = firstName.prefix(1).uppercased()
        let last = lastName.isEmpty ? username.prefix(1).uppercased() : lastName.prefix(1).uppercased()
        return "\(first)\(last)"
    }
}
