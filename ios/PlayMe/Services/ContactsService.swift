import Contacts

struct SimpleContact: Identifiable, Hashable {
    let id: String
    let firstName: String
    let lastName: String
    let phoneNumber: String

    var fullName: String {
        [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ")
    }

    var initials: String {
        let f = firstName.prefix(1).uppercased()
        let l = lastName.prefix(1).uppercased()
        return l.isEmpty ? f : "\(f)\(l)"
    }
}

final class ContactsService {
    static let shared = ContactsService()
    private let store = CNContactStore()

    func requestAccess() async -> Bool {
        do {
            return try await store.requestAccess(for: .contacts)
        } catch {
            print("ContactsService: requestAccess failed: \(error.localizedDescription)")
            return false
        }
    }

    func fetchContacts() -> [SimpleContact] {
        let keys: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactIdentifierKey as CNKeyDescriptor,
        ]
        let request = CNContactFetchRequest(keysToFetch: keys)
        request.sortOrder = .givenName

        var results: [SimpleContact] = []
        do {
            try store.enumerateContacts(with: request) { contact, _ in
                guard let phone = contact.phoneNumbers.first?.value.stringValue else { return }
                let c = SimpleContact(
                    id: contact.identifier,
                    firstName: contact.givenName,
                    lastName: contact.familyName,
                    phoneNumber: phone
                )
                results.append(c)
            }
        } catch {
            print("ContactsService: fetchContacts failed: \(error.localizedDescription)")
        }
        return results
    }
}
