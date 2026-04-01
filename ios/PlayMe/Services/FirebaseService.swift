import Foundation
import FirebaseAuth
import FirebaseFirestore

@Observable
@MainActor
class FirebaseService {
    static let shared = FirebaseService()

    var firebaseUID: String?
    var isSignedIn: Bool { firebaseUID != nil }

    private let db = Firestore.firestore()

    init() {
        if let user = Auth.auth().currentUser {
            firebaseUID = user.uid
        }
    }

    func signInWithSpotify(spotifyAccessToken: String) async -> Bool {
        do {
            let firebaseToken = try await fetchFirebaseCustomToken(spotifyAccessToken: spotifyAccessToken)
            let result = try await Auth.auth().signIn(withCustomToken: firebaseToken)
            firebaseUID = result.user.uid
            return true
        } catch {
            print("FirebaseService: sign-in failed: \(error.localizedDescription)")
            return false
        }
    }

    func signOut() {
        try? Auth.auth().signOut()
        firebaseUID = nil
    }

    // MARK: - User Profile

    func createOrUpdateUserProfile(username: String, spotifyDisplayName: String?, spotifyId: String?) async {
        guard let uid = firebaseUID else { return }

        let ref = db.collection("users").document(uid)
        var data: [String: Any] = [
            "username": username,
            "updatedAt": FieldValue.serverTimestamp(),
        ]
        if let spotifyDisplayName {
            data["spotifyDisplayName"] = spotifyDisplayName
        }
        if let spotifyId {
            data["spotifyId"] = spotifyId
        }

        do {
            let doc = try await ref.getDocument()
            if doc.exists {
                try await ref.updateData(data)
            } else {
                data["createdAt"] = FieldValue.serverTimestamp()
                try await ref.setData(data)
            }
        } catch {
            print("FirebaseService: profile write failed: \(error.localizedDescription)")
        }
    }

    func loadUserProfile() async -> (username: String, firstName: String)? {
        guard let uid = firebaseUID else { return nil }

        do {
            let doc = try await db.collection("users").document(uid).getDocument()
            guard let data = doc.data() else { return nil }
            let username = data["username"] as? String ?? ""
            let firstName = data["firstName"] as? String ?? username
            return (username: username, firstName: firstName)
        } catch {
            print("FirebaseService: profile load failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Likes

    func saveLike(shareId: String) async {
        guard let uid = firebaseUID else { return }
        do {
            try await db.collection("users").document(uid).collection("likes")
                .document(shareId).setData(["timestamp": FieldValue.serverTimestamp()])
        } catch {
            print("FirebaseService: save like failed: \(error.localizedDescription)")
        }
    }

    func removeLike(shareId: String) async {
        guard let uid = firebaseUID else { return }
        do {
            try await db.collection("users").document(uid).collection("likes")
                .document(shareId).delete()
        } catch {
            print("FirebaseService: remove like failed: \(error.localizedDescription)")
        }
    }

    func loadLikedShareIds() async -> Set<String> {
        guard let uid = firebaseUID else { return [] }
        do {
            let snapshot = try await db.collection("users").document(uid).collection("likes").getDocuments()
            return Set(snapshot.documents.map { $0.documentID })
        } catch {
            print("FirebaseService: load likes failed: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Shares

    func saveShare(_ share: SongShare) async -> String? {
        guard let uid = firebaseUID else { return nil }

        let data: [String: Any] = [
            "senderId": uid,
            "recipientId": share.recipient.id,
            "recipientUsername": share.recipient.username,
            "note": share.note as Any,
            "timestamp": FieldValue.serverTimestamp(),
            "song": [
                "id": share.song.id,
                "title": share.song.title,
                "artist": share.song.artist,
                "albumArtURL": share.song.albumArtURL,
                "duration": share.song.duration,
                "spotifyURI": share.song.spotifyURI as Any,
                "previewURL": share.song.previewURL as Any,
            ],
            "sender": [
                "id": uid,
                "firstName": share.sender.firstName,
                "username": share.sender.username,
            ],
            "recipient": [
                "id": share.recipient.id,
                "firstName": share.recipient.firstName,
                "username": share.recipient.username,
            ],
        ]

        do {
            let ref = try await db.collection("shares").addDocument(data: data)
            return ref.documentID
        } catch {
            print("FirebaseService: save share failed: \(error.localizedDescription)")
            return nil
        }
    }

    func loadSentShares() async -> [SongShare] {
        guard let uid = firebaseUID else { return [] }
        do {
            let snapshot = try await db.collection("shares")
                .whereField("senderId", isEqualTo: uid)
                .order(by: "timestamp", descending: true)
                .limit(to: 50)
                .getDocuments()
            return snapshot.documents.compactMap { parseShare(from: $0) }
        } catch {
            print("FirebaseService: load sent shares failed: \(error.localizedDescription)")
            return []
        }
    }

    func loadReceivedShares() async -> [SongShare] {
        guard let uid = firebaseUID else { return [] }
        do {
            let snapshot = try await db.collection("shares")
                .whereField("recipientId", isEqualTo: uid)
                .order(by: "timestamp", descending: true)
                .limit(to: 50)
                .getDocuments()
            return snapshot.documents.compactMap { parseShare(from: $0) }
        } catch {
            print("FirebaseService: load received shares failed: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Friends

    func addFriend(friendUID: String, friendUsername: String, friendFirstName: String) async {
        guard let uid = firebaseUID else { return }
        do {
            try await db.collection("users").document(uid).collection("friends")
                .document(friendUID).setData([
                    "username": friendUsername,
                    "firstName": friendFirstName,
                    "addedAt": FieldValue.serverTimestamp(),
                ])
            try await db.collection("users").document(friendUID).collection("friends")
                .document(uid).setData([
                    "username": UserDefaults.standard.string(forKey: "currentUserUsername") ?? "",
                    "firstName": UserDefaults.standard.string(forKey: "currentUserFirstName") ?? "",
                    "addedAt": FieldValue.serverTimestamp(),
                ])
        } catch {
            print("FirebaseService: add friend failed: \(error.localizedDescription)")
        }
    }

    func loadFriends() async -> [AppUser] {
        guard let uid = firebaseUID else { return [] }
        do {
            let snapshot = try await db.collection("users").document(uid).collection("friends").getDocuments()
            return snapshot.documents.compactMap { doc -> AppUser? in
                let data = doc.data()
                guard let username = data["username"] as? String,
                      let firstName = data["firstName"] as? String else { return nil }
                return AppUser(id: doc.documentID, firstName: firstName, username: username, phone: "")
            }
        } catch {
            print("FirebaseService: load friends failed: \(error.localizedDescription)")
            return []
        }
    }

    func searchUsers(query: String) async -> [AppUser] {
        guard !query.isEmpty else { return [] }
        let lowered = query.lowercased()
        do {
            let snapshot = try await db.collection("users")
                .whereField("username", isGreaterThanOrEqualTo: lowered)
                .whereField("username", isLessThanOrEqualTo: lowered + "\u{f8ff}")
                .limit(to: 20)
                .getDocuments()
            return snapshot.documents.compactMap { doc -> AppUser? in
                guard doc.documentID != firebaseUID else { return nil }
                let data = doc.data()
                let username = data["username"] as? String ?? ""
                let firstName = data["firstName"] as? String ?? username
                return AppUser(id: doc.documentID, firstName: firstName, username: username, phone: "")
            }
        } catch {
            print("FirebaseService: search users failed: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Private

    private nonisolated func fetchFirebaseCustomToken(spotifyAccessToken: String) async throws -> String {
        let authURL = "\(Config.firebaseFunctionsBaseURL)/auth"
        var request = URLRequest(url: URL(string: authURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var body = URLComponents()
        body.queryItems = [
            URLQueryItem(name: "access_token", value: spotifyAccessToken),
        ]
        request.httpBody = body.query?.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        struct AuthResponse: Codable {
            let firebase_token: String
            let spotify_uid: String
            let display_name: String
        }

        let authResponse = try JSONDecoder().decode(AuthResponse.self, from: data)
        return authResponse.firebase_token
    }

    private func parseShare(from doc: QueryDocumentSnapshot) -> SongShare? {
        let data = doc.data()
        guard let songData = data["song"] as? [String: Any],
              let senderData = data["sender"] as? [String: Any],
              let recipientData = data["recipient"] as? [String: Any] else { return nil }

        let song = Song(
            id: songData["id"] as? String ?? doc.documentID,
            title: songData["title"] as? String ?? "",
            artist: songData["artist"] as? String ?? "",
            albumArtURL: songData["albumArtURL"] as? String ?? "",
            duration: songData["duration"] as? String ?? "",
            spotifyURI: songData["spotifyURI"] as? String,
            previewURL: songData["previewURL"] as? String
        )

        let sender = AppUser(
            id: senderData["id"] as? String ?? "",
            firstName: senderData["firstName"] as? String ?? "",
            username: senderData["username"] as? String ?? "",
            phone: ""
        )

        let recipient = AppUser(
            id: recipientData["id"] as? String ?? "",
            firstName: recipientData["firstName"] as? String ?? "",
            username: recipientData["username"] as? String ?? "",
            phone: ""
        )

        let timestamp: Date
        if let ts = data["timestamp"] as? Timestamp {
            timestamp = ts.dateValue()
        } else {
            timestamp = Date()
        }

        return SongShare(
            id: doc.documentID,
            song: song,
            sender: sender,
            recipient: recipient,
            note: data["note"] as? String,
            timestamp: timestamp
        )
    }
}
