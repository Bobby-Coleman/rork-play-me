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
    private var verificationID: String?

    init() {
        if let user = Auth.auth().currentUser {
            firebaseUID = user.uid
        }
    }

    // MARK: - Phone Auth

    func sendVerificationCode(phoneNumber: String) async -> Result<Void, Error> {
        do {
            let id = try await PhoneAuthProvider.provider().verifyPhoneNumber(phoneNumber, uiDelegate: nil)
            verificationID = id
            return .success(())
        } catch {
            print("FirebaseService: sendVerificationCode failed: \(error.localizedDescription)")
            return .failure(error)
        }
    }

    func verifyCode(_ code: String) async -> Result<Void, Error> {
        guard let verificationID else {
            return .failure(NSError(domain: "PlayMe", code: -1, userInfo: [NSLocalizedDescriptionKey: "No verification ID. Request a code first."]))
        }
        let credential = PhoneAuthProvider.provider().credential(withVerificationID: verificationID, verificationCode: code)
        do {
            let result = try await Auth.auth().signIn(with: credential)
            firebaseUID = result.user.uid
            self.verificationID = nil
            return .success(())
        } catch {
            print("FirebaseService: verifyCode failed: \(error.localizedDescription)")
            return .failure(error)
        }
    }

    func signInAnonymously() async -> Bool {
        if let user = Auth.auth().currentUser {
            firebaseUID = user.uid
            return true
        }
        do {
            let result = try await Auth.auth().signInAnonymously()
            firebaseUID = result.user.uid
            return true
        } catch {
            print("FirebaseService: anonymous sign-in failed: \(error.localizedDescription)")
            return false
        }
    }

    func signOut() {
        Task { await removeFCMToken() }
        try? Auth.auth().signOut()
        firebaseUID = nil
        verificationID = nil
    }

    // MARK: - FCM Token

    func saveFCMToken(_ token: String) async {
        guard let uid = firebaseUID else { return }
        do {
            try await db.collection("users").document(uid).setData(["fcmToken": token], merge: true)
        } catch {
            print("FirebaseService: saveFCMToken failed: \(error.localizedDescription)")
        }
    }

    func removeFCMToken() async {
        guard let uid = firebaseUID else { return }
        do {
            try await db.collection("users").document(uid).updateData(["fcmToken": FieldValue.delete()])
        } catch {
            print("FirebaseService: removeFCMToken failed: \(error.localizedDescription)")
        }
    }

    // MARK: - User Profile

    func claimUsernameAndCreateProfile(username: String, firstName: String, lastName: String = "", phone: String) async -> Bool {
        guard let uid = firebaseUID else { return false }
        let lowered = username.lowercased()
        let usernameRef = db.collection("usernames").document(lowered)
        let userRef = db.collection("users").document(uid)

        do {
            let result = try await db.runTransaction { transaction, errorPointer -> Any? in
                let usernameDoc: DocumentSnapshot
                do {
                    usernameDoc = try transaction.getDocument(usernameRef)
                } catch let fetchError as NSError {
                    errorPointer?.pointee = fetchError
                    return NSNumber(value: false)
                }

                if usernameDoc.exists {
                    let existingUID = usernameDoc.data()?["uid"] as? String
                    if existingUID != uid {
                        return NSNumber(value: false)
                    }
                }

                transaction.setData([
                    "uid": uid,
                    "createdAt": FieldValue.serverTimestamp(),
                ], forDocument: usernameRef)

                transaction.setData([
                    "username": lowered,
                    "firstName": firstName,
                    "lastName": lastName,
                    "phone": phone,
                    "createdAt": FieldValue.serverTimestamp(),
                    "updatedAt": FieldValue.serverTimestamp(),
                ], forDocument: userRef, merge: true)

                return NSNumber(value: true)
            }
            return (result as? NSNumber)?.boolValue ?? false
        } catch {
            print("FirebaseService: claimUsername failed: \(error.localizedDescription)")
            return false
        }
    }

    func createOrUpdateUserProfile(username: String, firstName: String? = nil, lastName: String? = nil, phone: String? = nil) async {
        guard let uid = firebaseUID else { return }

        let ref = db.collection("users").document(uid)
        var data: [String: Any] = [
            "username": username.lowercased(),
            "firstName": firstName ?? username,
            "lastName": lastName ?? "",
            "updatedAt": FieldValue.serverTimestamp(),
        ]
        if let phone { data["phone"] = phone }

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

    func isUsernameTaken(_ username: String) async -> Bool? {
        let lowered = username.lowercased()
        do {
            let doc = try await db.collection("usernames").document(lowered).getDocument()
            if doc.exists {
                let existingUID = doc.data()?["uid"] as? String
                return existingUID != firebaseUID
            }
            return false
        } catch {
            print("FirebaseService: isUsernameTaken check failed: \(error.localizedDescription)")
            return nil
        }
    }

    func loadUserProfile() async -> (username: String, firstName: String, lastName: String, phone: String)? {
        guard let uid = firebaseUID else { return nil }

        do {
            let doc = try await db.collection("users").document(uid).getDocument()
            guard let data = doc.data() else { return nil }
            let username = data["username"] as? String ?? ""
            let firstName = data["firstName"] as? String ?? username
            let lastName = data["lastName"] as? String ?? ""
            let phone = data["phone"] as? String ?? ""
            return (username: username, firstName: firstName, lastName: lastName, phone: phone)
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
                "appleMusicURL": share.song.appleMusicURL as Any,
            ],
            "sender": [
                "id": uid,
                "firstName": share.sender.firstName,
                "lastName": share.sender.lastName,
                "username": share.sender.username,
            ],
            "recipient": [
                "id": share.recipient.id,
                "firstName": share.recipient.firstName,
                "lastName": share.recipient.lastName,
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

    func addFriend(friendUID: String, friendUsername: String, friendFirstName: String, friendLastName: String = "") async {
        guard let uid = firebaseUID else { return }
        do {
            try await db.collection("users").document(uid).collection("friends")
                .document(friendUID).setData([
                    "username": friendUsername,
                    "firstName": friendFirstName,
                    "lastName": friendLastName,
                    "addedAt": FieldValue.serverTimestamp(),
                ])
            try await db.collection("users").document(friendUID).collection("friends")
                .document(uid).setData([
                    "username": UserDefaults.standard.string(forKey: "currentUserUsername") ?? "",
                    "firstName": UserDefaults.standard.string(forKey: "currentUserFirstName") ?? "",
                    "lastName": UserDefaults.standard.string(forKey: "currentUserLastName") ?? "",
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
                let lastName = data["lastName"] as? String ?? ""
                return AppUser(id: doc.documentID, firstName: firstName, lastName: lastName, username: username, phone: "")
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
                let lastName = data["lastName"] as? String ?? ""
                return AppUser(id: doc.documentID, firstName: firstName, lastName: lastName, username: username, phone: "")
            }
        } catch {
            print("FirebaseService: search users failed: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Conversations

    func conversationId(with friendId: String) -> String? {
        guard let uid = firebaseUID else { return nil }
        let sorted = [uid, friendId].sorted()
        return "\(sorted[0])_\(sorted[1])"
    }

    func getOrCreateConversation(with friendId: String, friendName: String) async -> Conversation? {
        guard let uid = firebaseUID else {
            print("FirebaseService: getOrCreateConversation - not signed in")
            return nil
        }
        let myName = UserDefaults.standard.string(forKey: "currentUserFirstName") ?? ""
        guard let convId = conversationId(with: friendId) else {
            print("FirebaseService: getOrCreateConversation - could not build convId")
            return nil
        }

        print("FirebaseService: getOrCreateConversation uid=\(uid) friendId=\(friendId) convId=\(convId)")
        let ref = db.collection("conversations").document(convId)

        do {
            let doc = try await ref.getDocument()
            if doc.exists, let data = doc.data() {
                print("FirebaseService: conversation \(convId) already exists")
                return parseConversation(id: convId, data: data)
            }

            print("FirebaseService: creating new conversation \(convId)")
            let participants = [uid, friendId].sorted()
            let names: [String: String] = [uid: myName, friendId: friendName]
            let data: [String: Any] = [
                "participants": participants,
                "participantNames": names,
                "lastMessageText": "",
                "lastMessageTimestamp": FieldValue.serverTimestamp(),
                "unreadCount_\(uid)": 0,
                "unreadCount_\(friendId)": 0,
            ]
            try await ref.setData(data)
            print("FirebaseService: conversation \(convId) created successfully")

            return Conversation(
                id: convId,
                participants: participants,
                participantNames: names,
                lastMessageText: "",
                lastMessageTimestamp: Date(),
                unreadCount: 0
            )
        } catch {
            print("FirebaseService: getOrCreateConversation FAILED: \(error)")
            return nil
        }
    }

    func sendMessage(conversationId: String, text: String, song: Song? = nil) async {
        guard let uid = firebaseUID else {
            print("FirebaseService: sendMessage - not signed in")
            return
        }

        print("FirebaseService: sendMessage convId=\(conversationId) text=\(text.prefix(30))")
        var msgData: [String: Any] = [
            "senderId": uid,
            "text": text,
            "timestamp": FieldValue.serverTimestamp(),
        ]

        if let song {
            msgData["song"] = [
                "id": song.id,
                "title": song.title,
                "artist": song.artist,
                "albumArtURL": song.albumArtURL,
                "duration": song.duration,
                "previewURL": song.previewURL as Any,
                "appleMusicURL": song.appleMusicURL as Any,
            ]
        }

        do {
            let convRef = db.collection("conversations").document(conversationId)
            try await convRef.collection("messages").addDocument(data: msgData)
            print("FirebaseService: message added to \(conversationId)")

            let convDoc = try await convRef.getDocument()
            let participants = convDoc.data()?["participants"] as? [String] ?? []
            var updates: [String: Any] = [
                "lastMessageText": text,
                "lastMessageTimestamp": FieldValue.serverTimestamp(),
            ]
            for p in participants where p != uid {
                updates["unreadCount_\(p)"] = FieldValue.increment(Int64(1))
            }
            try await convRef.updateData(updates)
            print("FirebaseService: conversation \(conversationId) updated")
        } catch {
            print("FirebaseService: sendMessage FAILED: \(error)")
        }
    }

    func loadConversations() async -> [Conversation] {
        guard let uid = firebaseUID else {
            print("FirebaseService: loadConversations - not signed in")
            return []
        }
        do {
            print("FirebaseService: loadConversations for uid=\(uid)")
            let snapshot = try await db.collection("conversations")
                .whereField("participants", arrayContains: uid)
                .order(by: "lastMessageTimestamp", descending: true)
                .limit(to: 50)
                .getDocuments()
            let convos = snapshot.documents.compactMap { doc in
                parseConversation(id: doc.documentID, data: doc.data())
            }
            print("FirebaseService: loadConversations found \(convos.count) conversations")
            return convos
        } catch {
            print("FirebaseService: loadConversations FAILED: \(error)")
            return []
        }
    }

    func loadMessages(conversationId: String) async -> [ChatMessage] {
        do {
            let snapshot = try await db.collection("conversations")
                .document(conversationId)
                .collection("messages")
                .order(by: "timestamp", descending: false)
                .limit(to: 200)
                .getDocuments()
            return snapshot.documents.compactMap { parseMessage(from: $0) }
        } catch {
            print("FirebaseService: loadMessages failed: \(error.localizedDescription)")
            return []
        }
    }

    func listenForMessages(conversationId: String, onUpdate: @escaping @Sendable ([ChatMessage]) -> Void) -> ListenerRegistration {
        db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .order(by: "timestamp", descending: false)
            .addSnapshotListener { snapshot, _ in
                guard let docs = snapshot?.documents else { return }
                let messages = docs.compactMap { self.parseMessage(from: $0) }
                onUpdate(messages)
            }
    }

    func markConversationRead(conversationId: String) async {
        guard let uid = firebaseUID else { return }
        do {
            try await db.collection("conversations").document(conversationId)
                .updateData(["unreadCount_\(uid)": 0])
        } catch {
            print("FirebaseService: markConversationRead failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Parsing

    private func parseConversation(id: String, data: [String: Any]) -> Conversation? {
        guard let participants = data["participants"] as? [String],
              let names = data["participantNames"] as? [String: String] else { return nil }

        let lastText = data["lastMessageText"] as? String ?? ""
        let lastTs: Date
        if let ts = data["lastMessageTimestamp"] as? Timestamp {
            lastTs = ts.dateValue()
        } else {
            lastTs = Date()
        }

        let uid = firebaseUID ?? ""
        let unread = data["unreadCount_\(uid)"] as? Int ?? 0

        return Conversation(
            id: id,
            participants: participants,
            participantNames: names,
            lastMessageText: lastText,
            lastMessageTimestamp: lastTs,
            unreadCount: unread
        )
    }

    private func parseMessage(from doc: QueryDocumentSnapshot) -> ChatMessage? {
        let data = doc.data()
        guard let senderId = data["senderId"] as? String,
              let text = data["text"] as? String else { return nil }

        let timestamp: Date
        if let ts = data["timestamp"] as? Timestamp {
            timestamp = ts.dateValue()
        } else {
            timestamp = Date()
        }

        var song: Song? = nil
        if let songData = data["song"] as? [String: Any] {
            song = Song(
                id: songData["id"] as? String ?? "",
                title: songData["title"] as? String ?? "",
                artist: songData["artist"] as? String ?? "",
                albumArtURL: songData["albumArtURL"] as? String ?? "",
                duration: songData["duration"] as? String ?? "",
                previewURL: songData["previewURL"] as? String,
                appleMusicURL: songData["appleMusicURL"] as? String
            )
        }

        return ChatMessage(
            id: doc.documentID,
            senderId: senderId,
            text: text,
            timestamp: timestamp,
            song: song
        )
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
            previewURL: songData["previewURL"] as? String,
            appleMusicURL: songData["appleMusicURL"] as? String
        )

        let sender = AppUser(
            id: senderData["id"] as? String ?? "",
            firstName: senderData["firstName"] as? String ?? "",
            lastName: senderData["lastName"] as? String ?? "",
            username: senderData["username"] as? String ?? "",
            phone: ""
        )

        let recipient = AppUser(
            id: recipientData["id"] as? String ?? "",
            firstName: recipientData["firstName"] as? String ?? "",
            lastName: recipientData["lastName"] as? String ?? "",
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
