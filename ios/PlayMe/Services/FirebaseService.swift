import Foundation
import FirebaseAuth
import FirebaseFirestore
import CryptoKit

@Observable
@MainActor
class FirebaseService {
    static let shared = FirebaseService()

    var firebaseUID: String?
    var isSignedIn: Bool { firebaseUID != nil }

    private let db = Firestore.firestore()
    private var verificationID: String?
    private let friendRequestReadLimit = 50

    private func deterministicId(parts: [String]) -> String {
        let joined = parts.joined(separator: "|")
        let digest = SHA256.hash(data: Data(joined.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    func shareDocumentId(senderId: String, recipientId: String, songId: String) -> String {
        deterministicId(parts: ["share", senderId, recipientId, songId])
    }

    func newShareDocumentId() -> String {
        db.collection("shares").document().documentID
    }

    func mixtapeShareDocumentId(senderId: String, recipientId: String, mixtapeId: String) -> String {
        deterministicId(parts: ["mixtapeShare", senderId, recipientId, mixtapeId])
    }

    func albumShareDocumentId(senderId: String, recipientId: String, albumId: String) -> String {
        deterministicId(parts: ["albumShare", senderId, recipientId, albumId])
    }

    private static var localDayFormatter: DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }

    private static func localDateString(for date: Date = Date()) -> String {
        Self.localDayFormatter.string(from: date)
    }

    private static func localYesterdayDateString(from date: Date = Date()) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let start = cal.startOfDay(for: date)
        guard let y = cal.date(byAdding: .day, value: -1, to: start) else {
            return Self.localDateString(for: date)
        }
        return Self.localDayFormatter.string(from: y)
    }

    /// Snapchat-style active streak display: a stored streak remains active
    /// on the day of the last song send and the following day. If an entire
    /// local calendar day passes with no song from either participant, the
    /// displayed streak drops to zero until the next song send starts it over.
    private static func effectiveSongStreak(count: Int, lastDay: String?) -> Int {
        guard count > 0, let lastDay, !lastDay.isEmpty else { return 0 }
        let today = localDateString()
        let yesterday = localYesterdayDateString()
        return (lastDay == today || lastDay == yesterday) ? count : 0
    }

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
            try await db.collection("users").document(uid)
                .collection("private").document("profile")
                .setData(["fcmToken": token, "updatedAt": FieldValue.serverTimestamp()], merge: true)
        } catch {
            print("FirebaseService: saveFCMToken failed: \(error.localizedDescription)")
        }
    }

    func removeFCMToken() async {
        guard let uid = firebaseUID else { return }
        do {
            try await db.collection("users").document(uid)
                .collection("private").document("profile")
                .updateData(["fcmToken": FieldValue.delete(), "updatedAt": FieldValue.serverTimestamp()])
        } catch {
            print("FirebaseService: removeFCMToken failed: \(error.localizedDescription)")
        }
    }

    // MARK: - User Profile

    func claimUsernameAndCreateProfile(username: String, firstName: String, lastName: String = "", phone: String) async -> Bool {
        guard let uid = firebaseUID else { return false }
        let lowered = username.lowercased()
        // Store phone in canonical E.164 so the server-side claim trigger
        // (onUserProfileCreated) matches the same key used by saveQueuedShare.
        let normalizedPhone = PhoneNormalizer.normalize(phone) ?? phone
        let usernameRef = db.collection("usernames").document(lowered)
        let userRef = db.collection("users").document(uid)
        let privateRef = userRef.collection("private").document("profile")

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
                    "phone": FieldValue.delete(),
                    "createdAt": FieldValue.serverTimestamp(),
                    "updatedAt": FieldValue.serverTimestamp(),
                ], forDocument: userRef, merge: true)

                transaction.setData([
                    "phone": normalizedPhone,
                    "updatedAt": FieldValue.serverTimestamp(),
                ], forDocument: privateRef, merge: true)

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
            "phone": FieldValue.delete(),
        ]
        var privateData: [String: Any] = ["updatedAt": FieldValue.serverTimestamp()]
        if let phone { privateData["phone"] = PhoneNormalizer.normalize(phone) ?? phone }

        do {
            let doc = try await ref.getDocument()
            if doc.exists {
                try await ref.updateData(data)
            } else {
                data["createdAt"] = FieldValue.serverTimestamp()
                data.removeValue(forKey: "phone")
                try await ref.setData(data)
            }
            if privateData["phone"] != nil {
                try await ref.collection("private").document("profile").setData(privateData, merge: true)
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
            let privateDoc = try? await db.collection("users").document(uid)
                .collection("private").document("profile")
                .getDocument()
            let phone = privateDoc?.data()?["phone"] as? String ?? data["phone"] as? String ?? ""
            return (username: username, firstName: firstName, lastName: lastName, phone: phone)
        } catch {
            print("FirebaseService: profile load failed: \(error.localizedDescription)")
            return nil
        }
    }

    func fetchUserProfile(uid: String) async -> (username: String, firstName: String, lastName: String)? {
        do {
            let doc = try await db.collection("users").document(uid).getDocument()
            guard let data = doc.data() else { return nil }
            let username = data["username"] as? String ?? ""
            let firstName = data["firstName"] as? String ?? username
            let lastName = data["lastName"] as? String ?? ""
            return (username: username, firstName: firstName, lastName: lastName)
        } catch {
            print("FirebaseService: fetch user profile failed: \(error.localizedDescription)")
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
                "artistId": share.song.artistId as Any,
                "albumId": share.song.albumId as Any,
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
            let shareId = share.id
            guard !shareId.isEmpty else { return nil }
            let ref = db.collection("shares").document(shareId)
            try await ref.setData(data)
            return shareId
        } catch {
            print("FirebaseService: save share failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Writes a freshly resolved Spotify URI back onto the share doc so
    /// every other device that opens this share skips song.link entirely.
    /// Called after `MusicSearchService.resolveSpotifyURL` succeeds for a
    /// share that was persisted without a URI (usually because send-time
    /// enrichment was rate-limited). The caller should pass the canonical
    /// `spotify:track:<id>` URI, not the https URL.
    func patchShareSpotifyURI(shareId: String, spotifyURI: String) async {
        guard !shareId.isEmpty else { return }
        do {
            try await db.collection("shares").document(shareId).updateData([
                "song.spotifyURI": spotifyURI
            ])
            print("FirebaseService: event=share_spotify_uri_patched shareId=\(shareId) uri=\(spotifyURI)")
        } catch {
            print("FirebaseService: event=share_spotify_uri_patch_failed shareId=\(shareId) error=\(error.localizedDescription)")
        }
    }

    func markShareListened(shareId: String, source: String) async {
        guard let uid = firebaseUID, !shareId.isEmpty, !source.isEmpty else { return }
        let ref = db.collection("shares").document(shareId)

        do {
            let doc = try await ref.getDocument()
            guard let data = doc.data(),
                  data["recipientId"] as? String == uid else {
                return
            }

            try await ref.updateData([
                "recipientListenedAt": FieldValue.serverTimestamp(),
                "recipientListenSources": FieldValue.arrayUnion([source])
            ])
        } catch {
            print("FirebaseService: mark share listened failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Global Spotify Resolution Cache
    //
    // `spotifyResolutions/{sha256(normalizedAmURL)}` is a global,
    // user-base-wide cache of Apple-Music → Spotify resolutions. The iOS
    // client checks it before any network resolve and writes to it on
    // every success. This turns a per-share writeback into a per-SONG
    // writeback: the very first successful resolution of "Love on the
    // Brain" anywhere in the world serves every subsequent viewer
    // regardless of which share they received. Offloads essentially all
    // Odesli / Spotify /search traffic onto a Firestore read once the
    // catalog has warmed.

    /// Cached decode target for the global resolution collection.
    struct SpotifyResolution {
        let trackId: String
        let spotifyURL: String
        let resolvedAt: Date?
        let source: String?
    }

    /// Deterministic Firestore document ID for a given Apple Music URL.
    /// Must match exactly across reads and writes — the client-side
    /// `MusicSearchService.normalizeAppleMusicURL` produces the input.
    private static func resolutionDocId(forNormalizedAmURL normalized: String) -> String {
        let digest = SHA256.hash(data: Data(normalized.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Reads a cached resolution for the given Apple Music URL. Returns
    /// `nil` on miss or any error; callers should treat nil as "not
    /// cached, proceed to network resolve". Safe to call every resolve
    /// — Firestore reads are cheap and the alternative (song.link /
    /// Spotify /search) is far more expensive and rate-limited.
    func fetchSpotifyResolution(normalizedAmURL: String) async -> SpotifyResolution? {
        guard firebaseUID != nil else { return nil }
        let docId = Self.resolutionDocId(forNormalizedAmURL: normalizedAmURL)
        do {
            let snap = try await db.collection("spotifyResolutions").document(docId).getDocument()
            guard snap.exists, let data = snap.data(),
                  let trackId = data["trackId"] as? String,
                  let spotifyURL = data["spotifyURL"] as? String,
                  !trackId.isEmpty, !spotifyURL.isEmpty else {
                return nil
            }
            let resolvedAt = (data["resolvedAt"] as? Timestamp)?.dateValue()
            let source = data["source"] as? String
            return SpotifyResolution(trackId: trackId, spotifyURL: spotifyURL, resolvedAt: resolvedAt, source: source)
        } catch {
            print("FirebaseService: event=spotify_resolution_fetch_failed docId=\(docId) error=\(error.localizedDescription)")
            return nil
        }
    }

    /// Upserts a resolution into the global cache. Idempotent — calling
    /// it twice for the same URL just overwrites the metadata (resolvedAt
    /// / source) without changing the trackId. `source` is freeform ("spotify_api",
    /// "songlink") and exists purely for debugging / analytics.
    func writeSpotifyResolution(
        normalizedAmURL: String,
        trackId: String,
        spotifyURL: String,
        source: String
    ) async {
        guard firebaseUID != nil else { return }
        guard !trackId.isEmpty, !spotifyURL.isEmpty, !normalizedAmURL.isEmpty else { return }
        let docId = Self.resolutionDocId(forNormalizedAmURL: normalizedAmURL)
        let payload: [String: Any] = [
            "trackId": trackId,
            "spotifyURL": spotifyURL,
            "resolvedAt": FieldValue.serverTimestamp(),
            "source": source,
            "amURL": normalizedAmURL
        ]
        do {
            try await db.collection("spotifyResolutions").document(docId).setData(payload, merge: true)
            print("FirebaseService: event=spotify_resolution_written docId=\(docId) source=\(source) trackId=\(trackId)")
        } catch {
            print("FirebaseService: event=spotify_resolution_write_failed docId=\(docId) error=\(error.localizedDescription)")
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

    func listenSentShares(onChange: @escaping @Sendable ([SongShare]) -> Void) -> ListenerRegistration? {
        guard let uid = firebaseUID else { return nil }
        return db.collection("shares")
            .whereField("senderId", isEqualTo: uid)
            .order(by: "timestamp", descending: true)
            .limit(to: 50)
            .addSnapshotListener { [weak self] snapshot, error in
                if let error {
                    print("FirebaseService: listen sent shares failed: \(error.localizedDescription)")
                    return
                }
                guard let self, let docs = snapshot?.documents else { return }
                let shares = docs.compactMap { self.parseShare(from: $0) }
                onChange(shares)
            }
    }

    func hasSentSong(songId: String, to recipientId: String) async -> Bool {
        guard let uid = firebaseUID, !songId.isEmpty, !recipientId.isEmpty else { return false }
        do {
            let snapshot = try await db.collection("shares")
                .whereField("senderId", isEqualTo: uid)
                .whereField("recipientId", isEqualTo: recipientId)
                .whereField("song.id", isEqualTo: songId)
                .limit(to: 1)
                .getDocuments()
            return !snapshot.documents.isEmpty
        } catch {
            print("FirebaseService: duplicate sent song check failed: \(error.localizedDescription)")
            return false
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

    /// Real-time listener for the current user's received shares. Fires on
    /// every Firestore change so the home feed updates instantly when a new
    /// song arrives. Caller is responsible for `.remove()` on sign-out.
    func listenReceivedShares(onChange: @escaping @Sendable ([SongShare]) -> Void) -> ListenerRegistration? {
        guard let uid = firebaseUID else { return nil }
        return db.collection("shares")
            .whereField("recipientId", isEqualTo: uid)
            .order(by: "timestamp", descending: true)
            .limit(to: 50)
            .addSnapshotListener { [weak self] snapshot, error in
                if let error {
                    print("FirebaseService: listen received shares failed: \(error.localizedDescription)")
                    return
                }
                guard let self, let docs = snapshot?.documents else { return }
                let shares = docs.compactMap { self.parseShare(from: $0) }
                onChange(shares)
            }
    }

    // MARK: - Mixtape Shares

    /// Persists one row per recipient in `mixtapeShares/{id}`. Returns
    /// the new doc IDs in `recipient.id` order so the caller can map
    /// back to who got what (rarely needed, but cheap to surface).
    /// Snapshot semantics match `saveShare`: the full mixtape payload —
    /// name, description, embedded songs — is frozen into the share
    /// doc so the recipient's view never needs a cross-account read.
    @discardableResult
    func saveMixtapeShare(_ share: MixtapeShare) async -> String? {
        guard let uid = firebaseUID else { return nil }
        let payload: [String: Any] = [
            "senderId": uid,
            "recipientId": share.recipient.id,
            "recipientUsername": share.recipient.username,
            "note": share.note as Any,
            "timestamp": FieldValue.serverTimestamp(),
            "mixtape": [
                "id": share.mixtape.id,
                "ownerId": share.mixtape.ownerId,
                "name": share.mixtape.name,
                "description": share.mixtape.description as Any,
                "coverImageURL": share.mixtape.coverImageURL as Any,
                "isPrivate": share.mixtape.isPrivate,
                "createdAt": Timestamp(date: share.mixtape.createdAt),
                "updatedAt": Timestamp(date: share.mixtape.updatedAt),
                "songs": share.mixtape.songs.map(Self.embedSong),
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
            let shareId = mixtapeShareDocumentId(senderId: uid, recipientId: share.recipient.id, mixtapeId: share.mixtape.id)
            let ref = db.collection("mixtapeShares").document(shareId)
            _ = try await db.runTransaction { transaction, errorPointer -> Any? in
                do {
                    if try transaction.getDocument(ref).exists {
                        return NSNumber(value: true)
                    }
                    transaction.setData(payload, forDocument: ref)
                    return NSNumber(value: true)
                } catch let transactionError as NSError {
                    errorPointer?.pointee = transactionError
                    return nil
                }
            }
            return shareId
        } catch {
            print("FirebaseService: saveMixtapeShare failed: \(error.localizedDescription)")
            return nil
        }
    }

    func loadReceivedMixtapeShares() async -> [MixtapeShare] {
        guard let uid = firebaseUID else { return [] }
        do {
            let snap = try await db.collection("mixtapeShares")
                .whereField("recipientId", isEqualTo: uid)
                .order(by: "timestamp", descending: true)
                .limit(to: 50)
                .getDocuments()
            return snap.documents.compactMap { Self.parseMixtapeShare(from: $0) }
        } catch {
            print("FirebaseService: loadReceivedMixtapeShares failed: \(error.localizedDescription)")
            return []
        }
    }

    func loadSentMixtapeShares() async -> [MixtapeShare] {
        guard let uid = firebaseUID else { return [] }
        do {
            let snap = try await db.collection("mixtapeShares")
                .whereField("senderId", isEqualTo: uid)
                .order(by: "timestamp", descending: true)
                .limit(to: 50)
                .getDocuments()
            return snap.documents.compactMap { Self.parseMixtapeShare(from: $0) }
        } catch {
            print("FirebaseService: loadSentMixtapeShares failed: \(error.localizedDescription)")
            return []
        }
    }

    func listenReceivedMixtapeShares(onChange: @escaping @Sendable ([MixtapeShare]) -> Void) -> ListenerRegistration? {
        guard let uid = firebaseUID else { return nil }
        return db.collection("mixtapeShares")
            .whereField("recipientId", isEqualTo: uid)
            .order(by: "timestamp", descending: true)
            .limit(to: 50)
            .addSnapshotListener { snapshot, error in
                if let error {
                    print("FirebaseService: listen mixtape shares failed: \(error.localizedDescription)")
                    return
                }
                guard let docs = snapshot?.documents else { return }
                onChange(docs.compactMap { Self.parseMixtapeShare(from: $0) })
            }
    }

    // MARK: - Album Shares

    /// Persists one row per recipient in `albumShares/{id}`. Same
    /// snapshot semantics as song / mixtape shares — full track list
    /// is frozen into the doc so the recipient view is self-contained.
    @discardableResult
    func saveAlbumShare(_ share: AlbumShare) async -> String? {
        guard let uid = firebaseUID else { return nil }
        let payload: [String: Any] = [
            "senderId": uid,
            "recipientId": share.recipient.id,
            "recipientUsername": share.recipient.username,
            "note": share.note as Any,
            "timestamp": FieldValue.serverTimestamp(),
            "album": [
                "id": share.album.id,
                "name": share.album.name,
                "artworkURL": share.album.artworkURL,
                "releaseYear": share.album.releaseYear as Any,
                "trackCount": share.album.trackCount as Any,
                "primaryGenre": share.album.primaryGenre as Any,
                "artistName": share.album.artistName as Any,
            ],
            "songs": share.songs.map(Self.embedSong),
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
            let shareId = albumShareDocumentId(senderId: uid, recipientId: share.recipient.id, albumId: share.album.id)
            let ref = db.collection("albumShares").document(shareId)
            _ = try await db.runTransaction { transaction, errorPointer -> Any? in
                do {
                    if try transaction.getDocument(ref).exists {
                        return NSNumber(value: true)
                    }
                    transaction.setData(payload, forDocument: ref)
                    return NSNumber(value: true)
                } catch let transactionError as NSError {
                    errorPointer?.pointee = transactionError
                    return nil
                }
            }
            return shareId
        } catch {
            print("FirebaseService: saveAlbumShare failed: \(error.localizedDescription)")
            return nil
        }
    }

    func loadReceivedAlbumShares() async -> [AlbumShare] {
        guard let uid = firebaseUID else { return [] }
        do {
            let snap = try await db.collection("albumShares")
                .whereField("recipientId", isEqualTo: uid)
                .order(by: "timestamp", descending: true)
                .limit(to: 50)
                .getDocuments()
            return snap.documents.compactMap { Self.parseAlbumShare(from: $0) }
        } catch {
            print("FirebaseService: loadReceivedAlbumShares failed: \(error.localizedDescription)")
            return []
        }
    }

    func loadSentAlbumShares() async -> [AlbumShare] {
        guard let uid = firebaseUID else { return [] }
        do {
            let snap = try await db.collection("albumShares")
                .whereField("senderId", isEqualTo: uid)
                .order(by: "timestamp", descending: true)
                .limit(to: 50)
                .getDocuments()
            return snap.documents.compactMap { Self.parseAlbumShare(from: $0) }
        } catch {
            print("FirebaseService: loadSentAlbumShares failed: \(error.localizedDescription)")
            return []
        }
    }

    func listenReceivedAlbumShares(onChange: @escaping @Sendable ([AlbumShare]) -> Void) -> ListenerRegistration? {
        guard let uid = firebaseUID else { return nil }
        return db.collection("albumShares")
            .whereField("recipientId", isEqualTo: uid)
            .order(by: "timestamp", descending: true)
            .limit(to: 50)
            .addSnapshotListener { snapshot, error in
                if let error {
                    print("FirebaseService: listen album shares failed: \(error.localizedDescription)")
                    return
                }
                guard let docs = snapshot?.documents else { return }
                onChange(docs.compactMap { Self.parseAlbumShare(from: $0) })
            }
    }

    // MARK: - Share parse helpers (mixtape / album)

    /// Embed a `Song` value into a Firestore-friendly map. Centralised
    /// so the song-share, mixtape-share, and album-share writers all
    /// agree on shape, which keeps `parseEmbeddedSong` (used for
    /// reads) the single source of truth.
    private static func embedSong(_ song: Song) -> [String: Any] {
        [
            "id": song.id,
            "title": song.title,
            "artist": song.artist,
            "albumArtURL": song.albumArtURL,
            "duration": song.duration,
            "spotifyURI": song.spotifyURI as Any,
            "previewURL": song.previewURL as Any,
            "appleMusicURL": song.appleMusicURL as Any,
            "artistId": song.artistId as Any,
            "albumId": song.albumId as Any,
        ]
    }

    private static func parseMixtapeShare(from doc: QueryDocumentSnapshot) -> MixtapeShare? {
        let data = doc.data()
        guard let mixtapeData = data["mixtape"] as? [String: Any],
              let senderData = data["sender"] as? [String: Any],
              let recipientData = data["recipient"] as? [String: Any] else { return nil }

        let mixtape = parseMixtapeFromShare(mixtapeData)
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
        let timestamp = (data["timestamp"] as? Timestamp)?.dateValue() ?? Date()

        return MixtapeShare(
            id: doc.documentID,
            mixtape: mixtape,
            sender: sender,
            recipient: recipient,
            note: data["note"] as? String,
            timestamp: timestamp
        )
    }

    private static func parseMixtapeFromShare(_ data: [String: Any]) -> Mixtape {
        let id = data["id"] as? String ?? ""
        let ownerId = data["ownerId"] as? String ?? ""
        let name = data["name"] as? String ?? "Untitled mixtape"
        let description = (data["description"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? createdAt
        let rawSongs = data["songs"] as? [[String: Any]] ?? []
        let songs = rawSongs.compactMap { parseEmbeddedSong(from: $0) }
        let coverImageURL = (data["coverImageURL"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let isPrivate = data["isPrivate"] as? Bool ?? false
        return Mixtape(
            id: id,
            ownerId: ownerId,
            name: name,
            description: description,
            coverImageURL: coverImageURL,
            isPrivate: isPrivate,
            createdAt: createdAt,
            updatedAt: updatedAt,
            songs: songs
        )
    }

    private static func parseAlbumShare(from doc: QueryDocumentSnapshot) -> AlbumShare? {
        let data = doc.data()
        guard let albumData = data["album"] as? [String: Any],
              let senderData = data["sender"] as? [String: Any],
              let recipientData = data["recipient"] as? [String: Any] else { return nil }

        let album = Album(
            id: albumData["id"] as? String ?? "",
            name: albumData["name"] as? String ?? "Untitled album",
            artworkURL: albumData["artworkURL"] as? String ?? "",
            releaseYear: albumData["releaseYear"] as? String,
            trackCount: albumData["trackCount"] as? Int,
            primaryGenre: albumData["primaryGenre"] as? String,
            artistName: albumData["artistName"] as? String
        )
        let rawSongs = data["songs"] as? [[String: Any]] ?? []
        let songs = rawSongs.compactMap { parseEmbeddedSong(from: $0) }

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
        let timestamp = (data["timestamp"] as? Timestamp)?.dateValue() ?? Date()

        return AlbumShare(
            id: doc.documentID,
            album: album,
            songs: songs,
            sender: sender,
            recipient: recipient,
            note: data["note"] as? String,
            timestamp: timestamp
        )
    }

    // MARK: - Friends

    /// Remove a bidirectional friendship. Deletes both sides so neither user
    /// sees the other in their friends list anymore.
    func removeFriend(friendUID: String) async {
        guard let uid = firebaseUID else { return }
        do {
            let batch = db.batch()
            batch.deleteDocument(db.collection("users").document(uid).collection("friends").document(friendUID))
            batch.deleteDocument(db.collection("users").document(friendUID).collection("friends").document(uid))
            try await batch.commit()
        } catch {
            print("FirebaseService: remove friend failed: \(error.localizedDescription)")
        }
    }

    func addFriend(friendUID: String, friendUsername: String, friendFirstName: String, friendLastName: String = "") async {
        guard let uid = firebaseUID else { return }
        do {
            let batch = db.batch()
            batch.setData([
                "username": friendUsername,
                "firstName": friendFirstName,
                "lastName": friendLastName,
                "addedAt": FieldValue.serverTimestamp(),
            ], forDocument: db.collection("users").document(uid).collection("friends").document(friendUID))
            batch.setData([
                "username": UserDefaults.standard.string(forKey: "currentUserUsername") ?? "",
                "firstName": UserDefaults.standard.string(forKey: "currentUserFirstName") ?? "",
                "lastName": UserDefaults.standard.string(forKey: "currentUserLastName") ?? "",
                "addedAt": FieldValue.serverTimestamp(),
            ], forDocument: db.collection("users").document(friendUID).collection("friends").document(uid))
            try await batch.commit()
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

    // MARK: - Friend Requests

    /// Send a pending friend request to `toUID`. Writes
    /// `/users/{toUID}/friendRequests/{myUID}` with the sender's profile so
    /// the recipient can render the row without an extra lookup.
    func sendFriendRequest(
        toUID: String,
        username: String,
        firstName: String,
        lastName: String = "",
        targetUsername: String,
        targetFirstName: String,
        targetLastName: String = ""
    ) async -> Bool {
        guard let uid = firebaseUID, uid != toUID else { return false }
        let myUsername = username.isEmpty ? (UserDefaults.standard.string(forKey: "currentUserUsername") ?? "") : username
        let myFirst = firstName.isEmpty ? (UserDefaults.standard.string(forKey: "currentUserFirstName") ?? "") : firstName
        let myLast = lastName.isEmpty ? (UserDefaults.standard.string(forKey: "currentUserLastName") ?? "") : lastName
        do {
            let batch = db.batch()
            let incomingRef = db.collection("users").document(toUID)
                .collection("friendRequests").document(uid)
            let outgoingRef = db.collection("users").document(uid)
                .collection("outgoingFriendRequests").document(toUID)

            batch.setData([
                "username": myUsername,
                "firstName": myFirst,
                "lastName": myLast,
                "createdAt": FieldValue.serverTimestamp(),
            ], forDocument: incomingRef)

            batch.setData([
                "username": targetUsername,
                "firstName": targetFirstName,
                "lastName": targetLastName,
                "createdAt": FieldValue.serverTimestamp(),
            ], forDocument: outgoingRef)

            try await batch.commit()
            return true
        } catch {
            print("FirebaseService: send friend request failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Cancel an outgoing pending request that the caller previously sent.
    func cancelOutgoingRequest(toUID: String) async {
        guard let uid = firebaseUID else { return }
        do {
            let batch = db.batch()
            batch.deleteDocument(
                db.collection("users").document(toUID)
                    .collection("friendRequests").document(uid)
            )
            batch.deleteDocument(
                db.collection("users").document(uid)
                    .collection("outgoingFriendRequests").document(toUID)
            )
            try await batch.commit()
        } catch {
            print("FirebaseService: cancel outgoing request failed: \(error.localizedDescription)")
        }
    }

    /// Accept an incoming request by creating the bidirectional friendship
    /// and deleting the request document.
    func acceptFriendRequest(from user: AppUser) async {
        guard let uid = firebaseUID else { return }
        do {
            let batch = db.batch()
            batch.setData([
                "username": user.username,
                "firstName": user.firstName,
                "lastName": user.lastName,
                "acceptedBy": uid,
                "addedAt": FieldValue.serverTimestamp(),
            ], forDocument: db.collection("users").document(uid).collection("friends").document(user.id))
            batch.setData([
                "username": UserDefaults.standard.string(forKey: "currentUserUsername") ?? "",
                "firstName": UserDefaults.standard.string(forKey: "currentUserFirstName") ?? "",
                "lastName": UserDefaults.standard.string(forKey: "currentUserLastName") ?? "",
                "acceptedBy": uid,
                "addedAt": FieldValue.serverTimestamp(),
            ], forDocument: db.collection("users").document(user.id).collection("friends").document(uid))
            batch.deleteDocument(
                db.collection("users").document(uid)
                    .collection("friendRequests").document(user.id)
            )
            batch.deleteDocument(
                db.collection("users").document(user.id)
                    .collection("outgoingFriendRequests").document(uid)
            )
            try await batch.commit()
        } catch {
            print("FirebaseService: delete accepted request failed: \(error.localizedDescription)")
        }
    }

    /// Decline an incoming request (simply deletes the request doc).
    func declineFriendRequest(fromUID: String) async {
        guard let uid = firebaseUID else { return }
        do {
            let batch = db.batch()
            batch.deleteDocument(
                db.collection("users").document(uid)
                    .collection("friendRequests").document(fromUID)
            )
            batch.deleteDocument(
                db.collection("users").document(fromUID)
                    .collection("outgoingFriendRequests").document(uid)
            )
            try await batch.commit()
        } catch {
            print("FirebaseService: decline friend request failed: \(error.localizedDescription)")
        }
    }

    /// One-shot load of incoming friend requests for the current user.
    func loadIncomingRequests() async -> [AppUser] {
        guard let uid = firebaseUID else { return [] }
        do {
            let snapshot = try await db.collection("users").document(uid)
                .collection("friendRequests")
                .order(by: "createdAt", descending: true)
                .limit(to: friendRequestReadLimit)
                .getDocuments()
            return snapshot.documents.compactMap { doc -> AppUser? in
                let data = doc.data()
                let username = data["username"] as? String ?? ""
                let firstName = data["firstName"] as? String ?? username
                let lastName = data["lastName"] as? String ?? ""
                return AppUser(id: doc.documentID, firstName: firstName, lastName: lastName, username: username, phone: "")
            }
        } catch {
            print("FirebaseService: load incoming requests failed: \(error.localizedDescription)")
            return []
        }
    }

    /// One-shot load of the current user's pending outgoing friend requests.
    func loadOutgoingRequests() async -> [AppUser] {
        guard let uid = firebaseUID else { return [] }
        do {
            let snapshot = try await db.collection("users").document(uid)
                .collection("outgoingFriendRequests")
                .order(by: "createdAt", descending: true)
                .limit(to: friendRequestReadLimit)
                .getDocuments()
            return snapshot.documents.compactMap(parseRequestUser)
        } catch {
            print("FirebaseService: load outgoing requests failed: \(error.localizedDescription)")
            return []
        }
    }

    /// Returns true if the caller already has a pending outgoing request to
    /// `toUID`. Used to hydrate search result chip state on view open.
    func hasOutgoingRequest(toUID: String) async -> Bool {
        guard let uid = firebaseUID else { return false }
        do {
            let mirror = try await db.collection("users").document(uid)
                .collection("outgoingFriendRequests").document(toUID).getDocument()
            if mirror.exists { return true }

            let doc = try await db.collection("users").document(toUID)
                .collection("friendRequests").document(uid).getDocument()
            return doc.exists
        } catch {
            return false
        }
    }

    /// Live listener for incoming friend requests — mirrors the message
    /// listener pattern. Used to drive the pill badge on the home feed.
    func listenIncomingRequests(onChange: @escaping @Sendable ([AppUser]) -> Void) -> ListenerRegistration? {
        guard let uid = firebaseUID else { return nil }
        return db.collection("users").document(uid)
            .collection("friendRequests")
            .order(by: "createdAt", descending: true)
            .limit(to: friendRequestReadLimit)
            .addSnapshotListener { snapshot, _ in
                guard let docs = snapshot?.documents else { return }
                let requests = docs.map { doc -> AppUser in
                    let data = doc.data()
                    let username = data["username"] as? String ?? ""
                    let firstName = data["firstName"] as? String ?? username
                    let lastName = data["lastName"] as? String ?? ""
                    return AppUser(id: doc.documentID, firstName: firstName, lastName: lastName, username: username, phone: "")
                }
                onChange(requests)
            }
    }

    /// Live listener for pending outgoing requests so the send sheet can offer
    /// pending real accounts as recipients everywhere, not just during onboarding.
    func listenOutgoingRequests(onChange: @escaping @Sendable ([AppUser]) -> Void) -> ListenerRegistration? {
        guard let uid = firebaseUID else { return nil }
        return db.collection("users").document(uid)
            .collection("outgoingFriendRequests")
            .order(by: "createdAt", descending: true)
            .limit(to: friendRequestReadLimit)
            .addSnapshotListener { [weak self] snapshot, error in
                if let error {
                    print("FirebaseService: listen outgoing requests failed: \(error.localizedDescription)")
                    return
                }
                guard let self, let docs = snapshot?.documents else { return }
                onChange(docs.compactMap(self.parseRequestUser))
            }
    }

    private func parseRequestUser(from doc: QueryDocumentSnapshot) -> AppUser? {
        let data = doc.data()
        let username = data["username"] as? String ?? ""
        let firstName = data["firstName"] as? String ?? username
        let lastName = data["lastName"] as? String ?? ""
        return AppUser(id: doc.documentID, firstName: firstName, lastName: lastName, username: username, phone: "")
    }

    func searchUsers(query: String) async -> [AppUser] {
        // Normalize: drop whitespace + leading '@', lowercase. Matches how
        // usernames are stored via claimUsernameAndCreateProfile.
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let stripped = trimmed.hasPrefix("@") ? String(trimmed.dropFirst()) : trimmed
        let q = stripped.lowercased()
        guard !q.isEmpty else { return [] }

        var results: [AppUser] = []
        var seen: Set<String> = []
        if let me = firebaseUID { seen.insert(me) }

        // Prefix range query against /users for autocomplete.
        do {
            let snapshot = try await db.collection("users")
                .whereField("username", isGreaterThanOrEqualTo: q)
                .whereField("username", isLessThanOrEqualTo: q + "\u{f8ff}")
                .limit(to: 20)
                .getDocuments()
            for doc in snapshot.documents {
                guard !seen.contains(doc.documentID) else { continue }
                let data = doc.data()
                let username = data["username"] as? String ?? ""
                let firstName = data["firstName"] as? String ?? username
                let lastName = data["lastName"] as? String ?? ""
                results.append(AppUser(id: doc.documentID, firstName: firstName, lastName: lastName, username: username, phone: ""))
                seen.insert(doc.documentID)
            }
        } catch {
            print("FirebaseService: search users failed: \(error.localizedDescription)")
        }

        // Exact-match fallback via canonical /usernames mapping. Covers
        // accounts whose /users doc lacks a searchable `username` field.
        do {
            let mapping = try await db.collection("usernames").document(q).getDocument()
            if let uid = mapping.data()?["uid"] as? String, !seen.contains(uid) {
                if let profile = await fetchUserProfile(uid: uid) {
                    results.append(AppUser(
                        id: uid,
                        firstName: profile.firstName,
                        lastName: profile.lastName,
                        username: profile.username.isEmpty ? q : profile.username,
                        phone: ""
                    ))
                    seen.insert(uid)
                }
            }
        } catch {
            print("FirebaseService: username exact lookup failed: \(error.localizedDescription)")
        }

        return results
    }

    // MARK: - Blocking

    /// Block another user. Writes `users/{me}/blocked/{uid}` and also deletes
    /// any bidirectional friendship so the blocked user no longer appears in
    /// either party's friends list.
    func blockUser(_ targetUID: String) async {
        guard let uid = firebaseUID, targetUID != uid else { return }
        do {
            try await db.collection("users").document(uid).collection("blocked")
                .document(targetUID).setData([
                    "blockedAt": FieldValue.serverTimestamp(),
                ])
            // Best-effort cleanup of either side of the friendship. Errors are
            // non-fatal — the block itself is what matters.
            try? await db.collection("users").document(uid).collection("friends")
                .document(targetUID).delete()
            try? await db.collection("users").document(targetUID).collection("friends")
                .document(uid).delete()
        } catch {
            print("FirebaseService: block user failed: \(error.localizedDescription)")
        }
    }

    func unblockUser(_ targetUID: String) async {
        guard let uid = firebaseUID else { return }
        do {
            try await db.collection("users").document(uid).collection("blocked")
                .document(targetUID).delete()
        } catch {
            print("FirebaseService: unblock user failed: \(error.localizedDescription)")
        }
    }

    /// Loads the set of UIDs the current user has blocked, along with the
    /// latest profile snapshot for each (for the "Blocked users" settings
    /// screen).
    func loadBlockedUsers() async -> [AppUser] {
        guard let uid = firebaseUID else { return [] }
        do {
            let snapshot = try await db.collection("users").document(uid)
                .collection("blocked").getDocuments()
            var result: [AppUser] = []
            for doc in snapshot.documents {
                if let profile = await fetchUserProfile(uid: doc.documentID) {
                    result.append(AppUser(
                        id: doc.documentID,
                        firstName: profile.firstName,
                        lastName: profile.lastName,
                        username: profile.username,
                        phone: ""
                    ))
                } else {
                    result.append(AppUser(
                        id: doc.documentID,
                        firstName: "User",
                        lastName: "",
                        username: "",
                        phone: ""
                    ))
                }
            }
            return result
        } catch {
            print("FirebaseService: load blocked users failed: \(error.localizedDescription)")
            return []
        }
    }

    func loadBlockedUserIds() async -> Set<String> {
        guard let uid = firebaseUID else { return [] }
        do {
            let snapshot = try await db.collection("users").document(uid)
                .collection("blocked").getDocuments()
            return Set(snapshot.documents.map { $0.documentID })
        } catch {
            print("FirebaseService: load blocked ids failed: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Send Stats (per-friend send counter for activity ranking)

    /// Atomically bump the caller's private send counter for a given recipient.
    /// Used to rank friends in the send sheet chip row by interaction
    /// frequency. Fire-and-forget on the call site; errors are only logged.
    func incrementSendStat(friendUid: String) async {
        guard let uid = firebaseUID else { return }
        do {
            try await db.collection("users").document(uid)
                .collection("sendStats").document(friendUid)
                .setData([
                    "count": FieldValue.increment(Int64(1)),
                    "lastSentAt": FieldValue.serverTimestamp(),
                ], merge: true)
        } catch {
            print("FirebaseService: increment send stat failed: \(error.localizedDescription)")
        }
    }

    /// One-shot read of every sendStats entry for the current user.
    func loadSendStats() async -> [String: SendStat] {
        guard let uid = firebaseUID else { return [:] }
        do {
            let snapshot = try await db.collection("users").document(uid)
                .collection("sendStats").getDocuments()
            var result: [String: SendStat] = [:]
            for doc in snapshot.documents {
                let data = doc.data()
                let count = (data["count"] as? Int) ?? Int((data["count"] as? Int64) ?? 0)
                let lastSentAt = (data["lastSentAt"] as? Timestamp)?.dateValue()
                result[doc.documentID] = SendStat(count: count, lastSentAt: lastSentAt)
            }
            return result
        } catch {
            print("FirebaseService: load send stats failed: \(error.localizedDescription)")
            return [:]
        }
    }

    // MARK: - Reports

    enum ReportTargetType: String {
        case user
        case share
        case message
    }

    /// Submit a user/content report. Reports are write-only for clients and
    /// readable only to the moderation backend (Cloud Functions / admins).
    func submitReport(
        targetUid: String,
        targetType: ReportTargetType,
        targetId: String?,
        reason: String,
        note: String?
    ) async -> Bool {
        guard let uid = firebaseUID else { return false }
        var data: [String: Any] = [
            "reporterUid": uid,
            "targetUid": targetUid,
            "targetType": targetType.rawValue,
            "reason": reason,
            "createdAt": FieldValue.serverTimestamp(),
        ]
        if let targetId { data["targetId"] = targetId }
        if let note, !note.isEmpty { data["note"] = note }

        do {
            _ = try await db.collection("reports").addDocument(data: data)
            return true
        } catch {
            print("FirebaseService: submit report failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Notification preferences

    /// Persists the user's master notifications toggle. The Cloud Function
    /// push triggers read this flag and skip delivery when false.
    func setNotificationsEnabled(_ enabled: Bool) async {
        guard let uid = firebaseUID else { return }
        do {
            try await db.collection("users").document(uid)
                .setData(["notificationsEnabled": enabled], merge: true)
        } catch {
            print("FirebaseService: set notifications flag failed: \(error.localizedDescription)")
        }
    }

    func loadNotificationsEnabled() async -> Bool {
        guard let uid = firebaseUID else { return true }
        do {
            let doc = try await db.collection("users").document(uid).getDocument()
            return (doc.data()?["notificationsEnabled"] as? Bool) ?? true
        } catch {
            return true
        }
    }

    // MARK: - Account Deletion

    enum DeleteAccountError: Error, LocalizedError {
        case notSignedIn
        case tokenUnavailable
        case network(String)
        case serverRejected(Int, String)

        var errorDescription: String? {
            switch self {
            case .notSignedIn: return "You're not signed in."
            case .tokenUnavailable: return "Couldn't verify your session. Please sign in again."
            case .network(let msg): return "Network error: \(msg)"
            case .serverRejected(_, let msg): return msg
            }
        }
    }

    /// Region used when composing the deleteAccount endpoint URL. Matches the
    /// default region of the other onRequest functions in this project.
    private static let functionsRegion = "us-central1"

    private static let cachedProjectId: String? = {
        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: path),
              let projectId = dict["PROJECT_ID"] as? String else { return nil }
        return projectId
    }()

    private var deleteAccountEndpoint: URL? {
        guard let projectId = Self.cachedProjectId else { return nil }
        let urlString = "https://\(Self.functionsRegion)-\(projectId).cloudfunctions.net/deleteAccount"
        return URL(string: urlString)
    }

    /// Calls the server-side `deleteAccount` HTTPS function with the current
    /// user's Firebase ID token. The function runs the Firestore cascade and
    /// then deletes the Auth user, which invalidates this client's session.
    func deleteAccount() async -> Result<Void, DeleteAccountError> {
        guard let user = Auth.auth().currentUser else { return .failure(.notSignedIn) }

        let idToken: String
        do {
            idToken = try await user.getIDToken()
        } catch {
            return .failure(.tokenUnavailable)
        }

        guard let url = deleteAccountEndpoint else {
            return .failure(.network("Missing Firebase project ID"))
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = "{}".data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                return .failure(.network("Invalid response"))
            }
            if http.statusCode != 200 {
                let body = String(data: data, encoding: .utf8) ?? "Delete failed"
                return .failure(.serverRejected(http.statusCode, body))
            }
            // Server has deleted the Auth user; make sure local state is cleared.
            try? Auth.auth().signOut()
            firebaseUID = nil
            verificationID = nil
            return .success(())
        } catch {
            return .failure(.network(error.localizedDescription))
        }
    }

    // MARK: - Pending Shares (queued for not-yet-signed-up contacts)

    enum QueuedShareError: Error, LocalizedError {
        case notSignedIn
        case invalidPhone
        case writeFailed(String)

        var errorDescription: String? {
            switch self {
            case .notSignedIn: return "Please sign in to send a song."
            case .invalidPhone: return "We couldn't read that contact's phone number."
            case .writeFailed(let msg): return msg
            }
        }
    }

    /// Queue a song to be delivered when a contact with `phoneE164` signs up.
    /// Stored at `pendingShares/{phoneE164}/shares/{autoId}`. Idempotent by
    /// document ID — callers can retry with the same payload.
    func saveQueuedShare(
        phoneE164: String,
        contactDisplayName: String,
        song: Song,
        note: String?
    ) async -> Result<String, QueuedShareError> {
        guard let uid = firebaseUID else { return .failure(.notSignedIn) }

        let senderFirst = UserDefaults.standard.string(forKey: "currentUserFirstName") ?? ""
        let senderLast = UserDefaults.standard.string(forKey: "currentUserLastName") ?? ""
        let senderUsername = UserDefaults.standard.string(forKey: "currentUserUsername") ?? ""

        let collection = db.collection("pendingShares")
            .document(phoneE164)
            .collection("shares")
        // Deterministic doc ref so retries are safe; the server-side claim
        // function mirrors this ID onto shares/{id} for end-to-end idempotency.
        let ref = collection.document()

        let data: [String: Any] = [
            "senderId": uid,
            "senderFirstName": senderFirst,
            "senderLastName": senderLast,
            "senderUsername": senderUsername,
            "contactDisplayName": contactDisplayName,
            "note": note as Any,
            "createdAt": FieldValue.serverTimestamp(),
            "delivered": false,
            "song": [
                "id": song.id,
                "title": song.title,
                "artist": song.artist,
                "albumArtURL": song.albumArtURL,
                "duration": song.duration,
                "spotifyURI": song.spotifyURI as Any,
                "previewURL": song.previewURL as Any,
                "appleMusicURL": song.appleMusicURL as Any,
                "artistId": song.artistId as Any,
                "albumId": song.albumId as Any,
            ],
        ]

        do {
            try await ref.setData(data)
            print("FirebaseService: event=pending_share_queued phoneE164=\(phoneE164) senderId=\(uid) id=\(ref.documentID)")
            return .success(ref.documentID)
        } catch {
            print("FirebaseService: event=pending_share_queue_failed phoneE164=\(phoneE164) senderId=\(uid) error=\(error.localizedDescription)")
            return .failure(.writeFailed(error.localizedDescription))
        }
    }

    /// Ask the server to run the pending-shares claim for the current user.
    /// Writes a `claimRequests/{id}` doc that triggers the `onClaimRequest`
    /// Cloud Function — clients never read `pendingShares` directly.
    ///
    /// Safe to call on every app foreground / loadData: the trigger deletes
    /// the request doc when done, and the claim itself is idempotent.
    func requestPendingSharesClaim() async {
        guard let uid = firebaseUID else { return }

        let reqId = "\(uid)_\(UUID().uuidString)"
        let ref = db.collection("claimRequests").document(reqId)
        do {
            try await ref.setData([
                "uid": uid,
                "createdAt": FieldValue.serverTimestamp(),
            ])
            print("FirebaseService: event=pending_share_claim_requested uid=\(uid) reqId=\(reqId)")
        } catch {
            print("FirebaseService: event=pending_share_claim_request_failed uid=\(uid) error=\(error.localizedDescription)")
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
                "songStreakCount": 0,
            ]
            try await ref.setData(data)
            print("FirebaseService: conversation \(convId) created successfully")

            return Conversation(
                id: convId,
                participants: participants,
                participantNames: names,
                lastMessageText: "",
                lastMessageTimestamp: Date(),
                unreadCount: 0,
                songStreakCount: 0,
                lastReadAt: [:]
            )
        } catch {
            print("FirebaseService: getOrCreateConversation FAILED: \(error)")
            return nil
        }
    }

    func sendMessage(
        conversationId: String,
        text: String,
        song: Song? = nil,
        replyTo: ChatMessage? = nil,
        mutationId: String = UUID().uuidString
    ) async {
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
                "spotifyURI": song.spotifyURI as Any,
                "previewURL": song.previewURL as Any,
                "appleMusicURL": song.appleMusicURL as Any,
                "artistId": song.artistId as Any,
                "albumId": song.albumId as Any,
            ]
        }

        if let replyTo {
            // Embed a compact snapshot of the parent message so the
            // quoted-reply chip on this bubble renders even after the
            // parent has scrolled out of the live tail window. Text is
            // truncated to 80 chars to keep doc size small; the song
            // title (if any) is preserved verbatim because titles are
            // short and bear high signal value.
            msgData["replyToMessageId"] = replyTo.id
            var preview: [String: Any] = [
                "messageId": replyTo.id,
                "senderId": replyTo.senderId,
                "textSnippet": String(replyTo.text.prefix(80)),
            ]
            if let songTitle = replyTo.song?.title {
                preview["songTitle"] = songTitle
            }
            msgData["replyToPreview"] = preview
        }

        do {
            let convRef = db.collection("conversations").document(conversationId)
            let msgRef = convRef.collection("messages").document(mutationId)

            let result = try await db.runTransaction { transaction, errorPointer -> Any? in
                let snapshot: DocumentSnapshot
                let existingMessage: DocumentSnapshot
                do {
                    snapshot = try transaction.getDocument(convRef)
                    existingMessage = try transaction.getDocument(msgRef)
                } catch let e as NSError {
                    errorPointer?.pointee = e
                    return nil
                }
                if existingMessage.exists {
                    return NSNumber(value: false)
                }
                guard let data = snapshot.data() else {
                    let err = NSError(domain: "PlayMe", code: -2, userInfo: [NSLocalizedDescriptionKey: "Missing conversation"])
                    errorPointer?.pointee = err
                    return nil
                }

                let participants = data["participants"] as? [String] ?? []
                let lastMessageText = text.isEmpty ? (song?.title ?? "") : text
                var updates: [String: Any] = [
                    "lastMessageText": lastMessageText,
                    "lastMessageTimestamp": FieldValue.serverTimestamp(),
                ]
                for p in participants where p != uid {
                    updates["unreadCount_\(p)"] = FieldValue.increment(Int64(1))
                }

                if song != nil {
                    let today = Self.localDateString()
                    let yesterday = Self.localYesterdayDateString()
                    let lastDay = data["songStreakLastDay"] as? String
                    let count = data["songStreakCount"] as? Int ?? 0

                    if lastDay != today {
                        let newCount: Int
                        if lastDay == nil || (lastDay?.isEmpty ?? true) {
                            newCount = 1
                        } else if lastDay == yesterday {
                            newCount = count + 1
                        } else {
                            newCount = 1
                        }
                        updates["songStreakCount"] = newCount
                        updates["songStreakLastDay"] = today
                    }
                }

                transaction.setData(msgData, forDocument: msgRef)
                transaction.updateData(updates, forDocument: convRef)
                return NSNumber(value: true)
            }
            let didWrite = (result as? NSNumber)?.boolValue ?? false
            print("FirebaseService: conversation \(conversationId) updated (transaction, messageWritten=\(didWrite))")
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

    /// Live listener for the current user's conversation inbox. Mirrors
    /// `listenForMessages` / `listenIncomingRequests` so the inbox UI
    /// updates in real time as `unreadCount_<uid>` flips or new
    /// conversations arrive. Returns `nil` when not signed in.
    func listenConversations(onChange: @escaping @Sendable ([Conversation]) -> Void) -> ListenerRegistration? {
        guard let uid = firebaseUID else { return nil }
        return db.collection("conversations")
            .whereField("participants", arrayContains: uid)
            .order(by: "lastMessageTimestamp", descending: true)
            .limit(to: 50)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self, let docs = snapshot?.documents else { return }
                let convos = docs.compactMap { self.parseConversation(id: $0.documentID, data: $0.data()) }
                onChange(convos)
            }
    }

    /// Real-time tail listener: subscribes to the most recent `limit`
    /// messages of a conversation, ordered newest → oldest by Firestore
    /// then reversed client-side so callers always receive ascending
    /// chronological order. This keeps first-paint cost O(50) regardless
    /// of how long the thread is — a critical fix for 1k+ message
    /// conversations that previously blocked rendering for seconds while
    /// the entire history streamed in.
    ///
    /// Older pages are fetched lazily via `loadEarlierMessages` when the
    /// user scrolls back. Caller is responsible for `.remove()` on
    /// dispose.
    func listenForMessageTail(
        conversationId: String,
        limit: Int = 50,
        onUpdate: @escaping @Sendable ([ChatMessage]) -> Void
    ) -> ListenerRegistration {
        db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .order(by: "timestamp", descending: true)
            .limit(to: limit)
            .addSnapshotListener { snapshot, _ in
                guard let docs = snapshot?.documents else { return }
                let messages = Array(docs.compactMap { self.parseMessage(from: $0) }.reversed())
                onUpdate(messages)
            }
    }

    /// One-shot cursor fetch of messages strictly older than `before`,
    /// returned in ascending chronological order. Used by `ChatView`'s
    /// "Loading earlier…" loader to page back through long threads
    /// without expanding the live listener's window. Returns an empty
    /// array on any error or when there are no more older messages.
    ///
    /// We cursor on `Timestamp` rather than a `DocumentSnapshot` so the
    /// caller doesn't need to retain the original snapshot — the
    /// `ChatMessage.timestamp` already on the model is enough.
    func loadEarlierMessages(
        conversationId: String,
        before: Date,
        limit: Int = 50
    ) async -> [ChatMessage] {
        do {
            let snapshot = try await db.collection("conversations")
                .document(conversationId)
                .collection("messages")
                .order(by: "timestamp", descending: true)
                .start(after: [Timestamp(date: before)])
                .limit(to: limit)
                .getDocuments()
            return Array(snapshot.documents.compactMap { parseMessage(from: $0) }.reversed())
        } catch {
            print("FirebaseService: loadEarlierMessages failed: \(error.localizedDescription)")
            return []
        }
    }

    /// Per-conversation timestamp of the last successful read receipt
    /// write, used by `markConversationRead` to enforce a 1Hz cap. Reset
    /// on sign-out.
    private var lastReadWriteAt: [String: Date] = [:]

    func markConversationRead(conversationId: String) async {
        guard let uid = firebaseUID else { return }

        // 1Hz throttle per conversation. The function is called from
        // onAppear, scenePhase active, and every incoming message
        // arrival while the chat is foregrounded — without this guard
        // a chatty thread can hammer Firestore with redundant writes
        // even though `lastReadAt_<uid>` only needs to advance to
        // "after the most recent message", not to the exact instant.
        let now = Date()
        if let last = lastReadWriteAt[conversationId], now.timeIntervalSince(last) < 1.0 {
            return
        }
        lastReadWriteAt[conversationId] = now

        do {
            // Zero the badge AND stamp `lastReadAt_<uid>` in the same
            // write so the iMessage-style "Read" indicator on the
            // sender's side flips the moment the recipient opens the
            // thread. Server timestamp keeps the comparison
            // wall-clock-monotonic vs. the message timestamps.
            try await db.collection("conversations").document(conversationId)
                .updateData([
                    "unreadCount_\(uid)": 0,
                    "lastReadAt_\(uid)": FieldValue.serverTimestamp(),
                ])
        } catch {
            print("FirebaseService: markConversationRead failed: \(error.localizedDescription)")
            // Roll back the throttle on failure so the caller can
            // retry sooner than 1s if the network is flaky.
            lastReadWriteAt[conversationId] = nil
        }
    }

    // MARK: - Reactions

    /// Set or change the current user's reaction on a message. Writes
    /// `messages/{mid}.reactions.<uid> = emoji` via a dotted-path
    /// `updateData` so the affected key set in the resulting diff is
    /// exactly `{ "reactions.<myUid>" }` — which is what the
    /// self-scoped reaction rule in `firestore.rules` checks for. This
    /// is symmetrical with `clearReaction` below and avoids the
    /// `setData(merge: true)` deep-merge ambiguity that can show up as
    /// "the rule rejects my own write" on certain field shapes. The
    /// snapshot listener observing the conversation's messages
    /// collection picks up the change and pushes it back to every
    /// connected client in real time.
    func setReaction(conversationId: String, messageId: String, emoji: String) async {
        guard let uid = firebaseUID else { return }
        guard !emoji.isEmpty else { return }
        do {
            try await db.collection("conversations").document(conversationId)
                .collection("messages").document(messageId)
                .updateData(["reactions.\(uid)": emoji])
        } catch {
            print("FirebaseService: setReaction failed: \(error.localizedDescription)")
        }
    }

    /// Remove the current user's reaction from a message (toggle-off
    /// from the tray when they re-tap their existing emoji). Deletes
    /// just their cell of the `reactions` map; other reactors are
    /// untouched.
    func clearReaction(conversationId: String, messageId: String) async {
        guard let uid = firebaseUID else { return }
        do {
            try await db.collection("conversations").document(conversationId)
                .collection("messages").document(messageId)
                .updateData(["reactions.\(uid)": FieldValue.delete()])
        } catch {
            print("FirebaseService: clearReaction failed: \(error.localizedDescription)")
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
        let storedStreak = data["songStreakCount"] as? Int ?? 0
        let streak = Self.effectiveSongStreak(
            count: storedStreak,
            lastDay: data["songStreakLastDay"] as? String
        )

        // Read receipt map: scan participants for `lastReadAt_<uid>` and
        // build a [uid: Date] dictionary. Missing entries mean that
        // participant has never opened the thread (or hasn't yet on a
        // build that supports the field), so the rendering layer treats
        // them as "no reads to display".
        var lastReadAt: [String: Date] = [:]
        for p in participants {
            if let ts = data["lastReadAt_\(p)"] as? Timestamp {
                lastReadAt[p] = ts.dateValue()
            }
        }

        return Conversation(
            id: id,
            participants: participants,
            participantNames: names,
            lastMessageText: lastText,
            lastMessageTimestamp: lastTs,
            unreadCount: unread,
            songStreakCount: streak,
            lastReadAt: lastReadAt
        )
    }

    private func parseMessage(from doc: QueryDocumentSnapshot) -> ChatMessage? {
        parseMessage(documentId: doc.documentID, data: doc.data())
    }

    /// Document-id-agnostic variant used by `parseMessage(from:)` and by
    /// any direct-document parsing path (e.g. one-shot `DocumentSnapshot`
    /// fetches that aren't `QueryDocumentSnapshot`).
    private func parseMessage(documentId: String, data: [String: Any]) -> ChatMessage? {
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
                spotifyURI: songData["spotifyURI"] as? String,
                previewURL: songData["previewURL"] as? String,
                appleMusicURL: songData["appleMusicURL"] as? String,
                artistId: songData["artistId"] as? String,
                albumId: songData["albumId"] as? String
            )
        }

        // Inline reply metadata. `replyToMessageId` may exist without
        // `replyToPreview` on legacy clients; the reverse should never
        // happen because preview is set in the same write.
        let replyToMessageId = data["replyToMessageId"] as? String
        var replyToPreview: ReplyPreview? = nil
        if let preview = data["replyToPreview"] as? [String: Any],
           let parentId = preview["messageId"] as? String,
           let parentSenderId = preview["senderId"] as? String {
            replyToPreview = ReplyPreview(
                messageId: parentId,
                senderId: parentSenderId,
                textSnippet: preview["textSnippet"] as? String ?? "",
                songTitle: preview["songTitle"] as? String
            )
        }

        // Reactions: stored as a top-level map `{ <uid>: <emoji> }`.
        // Missing or empty map both decode to an empty dictionary so
        // call sites can treat reactions as "always present".
        let reactions = (data["reactions"] as? [String: String]) ?? [:]

        return ChatMessage(
            id: documentId,
            senderId: senderId,
            text: text,
            timestamp: timestamp,
            song: song,
            replyToMessageId: replyToMessageId,
            replyToPreview: replyToPreview,
            reactions: reactions
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
            appleMusicURL: songData["appleMusicURL"] as? String,
            artistId: songData["artistId"] as? String,
            albumId: songData["albumId"] as? String
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

        let recipientListenedAt = (data["recipientListenedAt"] as? Timestamp)?.dateValue()
        let recipientListenSources = data["recipientListenSources"] as? [String] ?? []

        return SongShare(
            id: doc.documentID,
            song: song,
            sender: sender,
            recipient: recipient,
            note: data["note"] as? String,
            timestamp: timestamp,
            recipientListenedAt: recipientListenedAt,
            recipientListenSources: recipientListenSources
        )
    }

    // MARK: - Mixtapes

    /// Fetch all mixtapes owned by the signed-in user, hydrating the
    /// embedded `songs` subcollection in a single fan-out so the Mixtapes
    /// grid renders cover mosaics without per-row round-trips. Returns an
    /// empty array on any failure.
    func fetchMixtapes() async -> [Mixtape] {
        guard let uid = firebaseUID else { return [] }
        do {
            let snapshot = try await db.collection("users").document(uid)
                .collection("mixtapes")
                .order(by: "updatedAt", descending: true)
                .getDocuments()

            // Fetch the song subcollection for each mixtape in parallel.
            // For typical user-mixtape counts (tens, not hundreds) this is
            // far cheaper than serial reads and the Firestore SDK already
            // pools the connections.
            return await withTaskGroup(of: Mixtape?.self) { group in
                for doc in snapshot.documents {
                    group.addTask { [weak self] in
                        guard let self else { return nil }
                        return await self.parseMixtape(from: doc, uid: uid)
                    }
                }
                var result: [Mixtape] = []
                for await mix in group {
                    if let mix { result.append(mix) }
                }
                return result.sorted { $0.updatedAt > $1.updatedAt }
            }
        } catch {
            print("FirebaseService: fetchMixtapes failed: \(error.localizedDescription)")
            return []
        }
    }

    private func parseMixtape(from doc: QueryDocumentSnapshot, uid: String) async -> Mixtape? {
        let data = doc.data()
        guard let name = data["name"] as? String else { return nil }
        let description = (data["description"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? createdAt
        let songIds = data["songIds"] as? [String] ?? []

        // Pull the embedded songs subcollection. We could query by
        // `whereField("id", in: songIds)` but the in-place subcollection
        // is simpler and gives us the writer-controlled ordering for
        // free.
        var songs: [Song] = []
        do {
            let songSnap = try await db.collection("users").document(uid)
                .collection("mixtapes").document(doc.documentID)
                .collection("songs").getDocuments()
            songs = songSnap.documents.compactMap { snap in
                Self.parseEmbeddedSong(from: snap.data())
            }
            // Preserve the parent doc's `songIds` ordering when present —
            // it reflects the user's add-order which the subcollection
            // alone can't.
            if !songIds.isEmpty {
                let bySongId: [String: Song] = Dictionary(uniqueKeysWithValues: songs.map { ($0.id, $0) })
                songs = songIds.compactMap { bySongId[$0] }
            }
        } catch {
            print("FirebaseService: fetch mixtape songs failed for \(doc.documentID): \(error.localizedDescription)")
        }

        let coverImageURL = (data["coverImageURL"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let isPrivate = data["isPrivate"] as? Bool ?? false

        return Mixtape(
            id: doc.documentID,
            ownerId: uid,
            name: name,
            description: description,
            coverImageURL: coverImageURL,
            isPrivate: isPrivate,
            createdAt: createdAt,
            updatedAt: updatedAt,
            songs: songs
        )
    }

    /// Decodes the embedded `Song` map shape used by mixtape song
    /// subcollections. Mirrors the same fields written by `addSongToMixtape`
    /// and `saveShare`.
    private static func parseEmbeddedSong(from data: [String: Any]) -> Song? {
        guard let id = data["id"] as? String, !id.isEmpty else { return nil }
        return Song(
            id: id,
            title: data["title"] as? String ?? "",
            artist: data["artist"] as? String ?? "",
            albumArtURL: data["albumArtURL"] as? String ?? "",
            duration: data["duration"] as? String ?? "",
            spotifyURI: data["spotifyURI"] as? String,
            previewURL: data["previewURL"] as? String,
            appleMusicURL: data["appleMusicURL"] as? String,
            artistId: data["artistId"] as? String,
            albumId: data["albumId"] as? String
        )
    }

    /// Creates a new (empty) mixtape and returns its Firestore document
    /// id. `coverImageURL` must be a non-empty Firebase Storage download URL
    /// (upload happens client-side before this call). Returns nil on
    /// failure or when not signed in.
    func createMixtape(name: String, coverImageURL: String, isPrivate: Bool = false) async -> String? {
        guard let uid = firebaseUID else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let cover = coverImageURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cover.isEmpty else { return nil }
        let ref = db.collection("users").document(uid).collection("mixtapes").document()
        let payload: [String: Any] = [
            "name": trimmed,
            "coverImageURL": cover,
            "isPrivate": isPrivate,
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp(),
            "songIds": [],
        ]
        do {
            try await ref.setData(payload)
            return ref.documentID
        } catch {
            print("FirebaseService: createMixtape failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Featured Discover songs

    /// Ordered editorial song list for the left Discover/Home feed.
    /// Documents live at `featured_songs/{songId}` and are ordered by
    /// numeric `order` ascending so the feed can be curated from Firebase
    /// without shipping a new app build.
    func fetchFeaturedSongs(limit: Int = 100) async -> [Song] {
        do {
            let snapshot = try await db.collection("featured_songs")
                .order(by: "order", descending: false)
                .limit(to: limit)
                .getDocuments()
            return snapshot.documents.compactMap { Self.parseFeaturedSong(from: $0) }
        } catch {
            print("FirebaseService: fetchFeaturedSongs failed: \(error.localizedDescription)")
            return []
        }
    }

    private static func parseFeaturedSong(from doc: QueryDocumentSnapshot) -> Song? {
        var data = doc.data()
        if data["id"] == nil {
            data["id"] = doc.documentID
        }
        return parseEmbeddedSong(from: data)
    }

    // MARK: - Featured Discover mixtapes

    /// Paginated read of `featured_mixtapes` ordered by `order` ascending.
    /// Pass `startAfterDocumentId` from the previous page's last document.
    /// Returns the last Firestore document id in this page (for the next
    /// `startAfterDocumentId`), or nil when the page is empty or there is
    /// no subsequent page.
    func fetchFeaturedMixtapes(limit: Int = 20, startAfterDocumentId: String? = nil) async -> ([Mixtape], String?) {
        do {
            var query: Query = db.collection("featured_mixtapes")
                .order(by: "order", descending: false)
                .limit(to: limit)
            if let afterId = startAfterDocumentId, !afterId.isEmpty {
                let afterDoc = try await db.collection("featured_mixtapes").document(afterId).getDocument()
                if afterDoc.exists {
                    query = query.start(afterDocument: afterDoc)
                }
            }
            let snapshot = try await query.getDocuments()
            let mixtapes = snapshot.documents.compactMap { Self.parseFeaturedMixtape(from: $0) }
            let lastId = snapshot.documents.last?.documentID
            return (mixtapes, lastId)
        } catch {
            print("FirebaseService: fetchFeaturedMixtapes failed: \(error.localizedDescription)")
            return ([], nil)
        }
    }

    /// Decodes a top-level `featured_mixtapes/{id}` document into a
    /// `Mixtape` with `ownerId == Mixtape.featuredOwnerId`.
    private static func parseFeaturedMixtape(from doc: QueryDocumentSnapshot) -> Mixtape? {
        let data = doc.data()
        guard let name = data["name"] as? String else { return nil }
        let description = (data["description"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let coverImageURL = (data["coverImageURL"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let isPrivate = data["isPrivate"] as? Bool ?? false
        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? createdAt
        let rawSongs = data["songs"] as? [[String: Any]] ?? []
        let songs = rawSongs.compactMap { parseEmbeddedSong(from: $0) }
        return Mixtape(
            id: doc.documentID,
            ownerId: Mixtape.featuredOwnerId,
            name: name,
            description: description,
            coverImageURL: coverImageURL,
            isPrivate: isPrivate,
            createdAt: createdAt,
            updatedAt: updatedAt,
            songs: songs
        )
    }

    func renameMixtape(mixtapeId: String, to newName: String) async {
        guard let uid = firebaseUID else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try await db.collection("users").document(uid)
                .collection("mixtapes").document(mixtapeId)
                .updateData([
                    "name": trimmed,
                    "updatedAt": FieldValue.serverTimestamp(),
                ])
        } catch {
            print("FirebaseService: renameMixtape failed: \(error.localizedDescription)")
        }
    }

    /// Writes the owner-authored description blurb. Pass `nil` (or an
    /// empty string after trim) to clear it — we delete the field
    /// rather than store an empty string so `parseMixtape` doesn't have
    /// to special-case both nil and "".
    func updateMixtapeDescription(mixtapeId: String, to newDescription: String?) async {
        guard let uid = firebaseUID else { return }
        let trimmed = newDescription?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let payload: [String: Any] = [
            "description": trimmed.isEmpty ? FieldValue.delete() : trimmed,
            "updatedAt": FieldValue.serverTimestamp(),
        ]
        do {
            try await db.collection("users").document(uid)
                .collection("mixtapes").document(mixtapeId)
                .updateData(payload)
        } catch {
            print("FirebaseService: updateMixtapeDescription failed: \(error.localizedDescription)")
        }
    }

    /// Deletes a mixtape document and all of its embedded song entries.
    /// Also fans out a per-song update to `savedSongs/{songId}` to remove
    /// this mixtape id from each entry, so the Save index stays consistent
    /// for any client that re-loads it later.
    func deleteMixtape(mixtapeId: String) async {
        guard let uid = firebaseUID else { return }
        let mixRef = db.collection("users").document(uid)
            .collection("mixtapes").document(mixtapeId)
        do {
            // Snapshot the song ids so we can update savedSongs after the
            // delete propagates. Reading them BEFORE the delete avoids a
            // race where a concurrent write resurrects the mixtape ref
            // mid-cleanup.
            let songSnap = try await mixRef.collection("songs").getDocuments()
            let songIds = songSnap.documents.map { $0.documentID }

            for doc in songSnap.documents {
                try? await doc.reference.delete()
            }
            try await mixRef.delete()

            for songId in songIds {
                try? await db.collection("users").document(uid)
                    .collection("savedSongs").document(songId)
                    .updateData([
                        "mixtapeIds": FieldValue.arrayRemove([mixtapeId]),
                        "updatedAt": FieldValue.serverTimestamp(),
                    ])
            }
        } catch {
            print("FirebaseService: deleteMixtape failed: \(error.localizedDescription)")
        }
    }

    /// Adds a song to a mixtape, writing both the embedded song document
    /// and updating the parent's `songIds` array. Idempotent — if the song
    /// is already in the mixtape, the call collapses to a touch on
    /// `updatedAt`.
    ///
    /// Also writes through to `savedSongs/{songId}` so the
    /// "is this song saved anywhere" lookup stays an O(1) read.
    func addSongToMixtape(mixtapeId: String, song: Song) async {
        guard let uid = firebaseUID else { return }
        let mixRef = db.collection("users").document(uid)
            .collection("mixtapes").document(mixtapeId)
        let songRef = mixRef.collection("songs").document(song.id)
        let savedRef = db.collection("users").document(uid)
            .collection("savedSongs").document(song.id)

        let songPayload: [String: Any] = [
            "id": song.id,
            "title": song.title,
            "artist": song.artist,
            "albumArtURL": song.albumArtURL,
            "duration": song.duration,
            "spotifyURI": song.spotifyURI as Any,
            "previewURL": song.previewURL as Any,
            "appleMusicURL": song.appleMusicURL as Any,
            "artistId": song.artistId as Any,
            "albumId": song.albumId as Any,
            "addedAt": FieldValue.serverTimestamp(),
        ]

        do {
            try await songRef.setData(songPayload, merge: true)
            try await mixRef.updateData([
                "songIds": FieldValue.arrayUnion([song.id]),
                "updatedAt": FieldValue.serverTimestamp(),
            ])
            try await savedRef.setData([
                "mixtapeIds": FieldValue.arrayUnion([mixtapeId]),
                "updatedAt": FieldValue.serverTimestamp(),
            ], merge: true)
        } catch {
            print("FirebaseService: addSongToMixtape failed: \(error.localizedDescription)")
        }
    }

    /// Mirror of `addSongToMixtape`. Removes the embedded song doc, drops
    /// the id from the parent's `songIds`, and updates `savedSongs`.
    func removeSongFromMixtape(mixtapeId: String, songId: String) async {
        guard let uid = firebaseUID else { return }
        let mixRef = db.collection("users").document(uid)
            .collection("mixtapes").document(mixtapeId)
        let songRef = mixRef.collection("songs").document(songId)
        let savedRef = db.collection("users").document(uid)
            .collection("savedSongs").document(songId)

        do {
            try await songRef.delete()
            try await mixRef.updateData([
                "songIds": FieldValue.arrayRemove([songId]),
                "updatedAt": FieldValue.serverTimestamp(),
            ])
            try await savedRef.updateData([
                "mixtapeIds": FieldValue.arrayRemove([mixtapeId]),
                "updatedAt": FieldValue.serverTimestamp(),
            ])
        } catch {
            print("FirebaseService: removeSongFromMixtape failed: \(error.localizedDescription)")
        }
    }

    /// Fetches the per-user "saved songs" index so `SaveService` can answer
    /// "is this song saved" in O(1). Returns `[songId: Set<mixtapeId>]`.
    /// Empty entries (where the array has been cleared by a removal) are
    /// dropped so the in-memory `savedSongIds` set never claims a save
    /// the user has already undone.
    func fetchSavedSongIndex() async -> [String: Set<String>] {
        guard let uid = firebaseUID else { return [:] }
        do {
            let snapshot = try await db.collection("users").document(uid)
                .collection("savedSongs").getDocuments()
            var out: [String: Set<String>] = [:]
            for doc in snapshot.documents {
                let ids = doc.data()["mixtapeIds"] as? [String] ?? []
                if !ids.isEmpty {
                    out[doc.documentID] = Set(ids)
                }
            }
            return out
        } catch {
            print("FirebaseService: fetchSavedSongIndex failed: \(error.localizedDescription)")
            return [:]
        }
    }

    // MARK: - Curated Grid

    /// Loads the editorial curated list for the Discovery background grid
    /// from `curatedGrids/current`. Returns an empty array on any failure so
    /// the caller can fall back to its last good list without special-case
    /// error plumbing.
    ///
    /// Expected document shape:
    /// ```
    /// curatedGrids/current = {
    ///   items: [
    ///     { id: "song-1", albumArtURL: "https://...", title?: "...", artist?: "..." },
    ///     ...
    ///   ]
    /// }
    /// ```
    func fetchCuratedGrid() async -> [GridSong] {
        do {
            let doc = try await db.collection("curatedGrids").document("current").getDocument()
            guard let data = doc.data(),
                  let raw = data["items"] as? [[String: Any]] else {
                return []
            }
            return raw.compactMap { dict -> GridSong? in
                guard let id = dict["id"] as? String,
                      let albumArtURL = dict["albumArtURL"] as? String,
                      !albumArtURL.isEmpty else {
                    return nil
                }
                return GridSong(
                    id: id,
                    albumArtURL: albumArtURL,
                    title: dict["title"] as? String,
                    artist: dict["artist"] as? String
                )
            }
        } catch {
            print("FirebaseService.fetchCuratedGrid: \(error.localizedDescription)")
            return []
        }
    }
}
