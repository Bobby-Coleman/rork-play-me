import Contacts

struct SimpleContact: Identifiable, Hashable {
    let id: String
    let firstName: String
    let lastName: String
    let phoneNumber: String
    let thumbnailData: Data?

    init(id: String, firstName: String, lastName: String, phoneNumber: String, thumbnailData: Data? = nil) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.phoneNumber = phoneNumber
        self.thumbnailData = thumbnailData
    }

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
            CNContactThumbnailImageDataKey as CNKeyDescriptor,
        ]
        let request = CNContactFetchRequest(keysToFetch: keys)

        var results: [SimpleContact] = []
        do {
            try store.enumerateContacts(with: request) { contact, _ in
                guard let phone = contact.phoneNumbers.first?.value.stringValue else { return }
                let c = SimpleContact(
                    id: contact.identifier,
                    firstName: contact.givenName,
                    lastName: contact.familyName,
                    phoneNumber: phone,
                    thumbnailData: contact.thumbnailImageData
                )
                results.append(c)
            }
        } catch {
            print("ContactsService: fetchContacts failed: \(error.localizedDescription)")
        }
        return results.suggestedInviteOrder()
    }
}

extension Array where Element == SimpleContact {
    /// Privacy-safe invite ordering. Apple does not expose iMessage frequency
    /// or "closest contacts" data to third-party apps, so we preserve the
    /// phone-provided order and only boost contacts that are clearly actionable.
    func suggestedInviteOrder(prioritizedContactIds: Set<String> = []) -> [SimpleContact] {
        enumerated()
            .sorted { lhs, rhs in
                let l = inviteRank(lhs.element, originalIndex: lhs.offset, prioritizedContactIds: prioritizedContactIds)
                let r = inviteRank(rhs.element, originalIndex: rhs.offset, prioritizedContactIds: prioritizedContactIds)
                if l.bucket != r.bucket { return l.bucket < r.bucket }
                if l.digitRank != r.digitRank { return l.digitRank < r.digitRank }
                return l.originalIndex < r.originalIndex
            }
            .map(\.element)
    }
}

private func inviteRank(
    _ contact: SimpleContact,
    originalIndex: Int,
    prioritizedContactIds: Set<String>
) -> (bucket: Int, digitRank: Int, originalIndex: Int) {
    let hasName = !contact.fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    let digitCount = contact.phoneNumber.filter(\.isNumber).count
    let bucket: Int
    if prioritizedContactIds.contains(contact.id) {
        bucket = 0
    } else if hasName && digitCount >= 10 {
        bucket = 1
    } else if digitCount >= 10 {
        bucket = 2
    } else {
        bucket = 3
    }
    return (bucket, -digitCount, originalIndex)
}
