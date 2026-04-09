import SwiftUI
import WidgetKit

@Observable
@MainActor
class AppState {
    var isOnboarded: Bool = UserDefaults.standard.bool(forKey: "isOnboarded") {
        didSet { UserDefaults.standard.set(isOnboarded, forKey: "isOnboarded") }
    }

    var preferredMusicService: MusicService {
        get {
            let raw = UserDefaults.standard.string(forKey: "preferredMusicService") ?? MusicService.appleMusic.rawValue
            return MusicService(rawValue: raw) ?? .appleMusic
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "preferredMusicService")
        }
    }

    var currentUser: AppUser? {
        didSet {
            if let user = currentUser {
                UserDefaults.standard.set(user.id, forKey: "currentUserId")
                UserDefaults.standard.set(user.firstName, forKey: "currentUserFirstName")
                UserDefaults.standard.set(user.username, forKey: "currentUserUsername")
                UserDefaults.standard.set(user.phone, forKey: "currentUserPhone")
            }
        }
    }

    var friends: [AppUser] = []
    var songs: [Song] = MockData.songs
    var searchResults: [Song] = []
    var isSearchingSongs: Bool = false
    var receivedShares: [SongShare] = []
    var sentShares: [SongShare] = []
    var likedShareIds: Set<String> = [] {
        didSet {
            UserDefaults.standard.set(Array(likedShareIds), forKey: "likedShareIds")
        }
    }
    var conversations: [Conversation] = []
    var phoneNumber: String = ""
    var showSentToast = false
    var isLoading = false
    var isBackendAvailable = false
    var registrationError: String? = nil

    var likedShares: [SongShare] {
        (receivedShares + sentShares).filter { likedShareIds.contains($0.id) }
            .sorted { $0.timestamp > $1.timestamp }
    }

    init() {
        loadSavedUser()
        likedShareIds = Set(UserDefaults.standard.stringArray(forKey: "likedShareIds") ?? [])
    }

    private func loadSavedUser() {
        if let id = UserDefaults.standard.string(forKey: "currentUserId"),
           let firstName = UserDefaults.standard.string(forKey: "currentUserFirstName"),
           let username = UserDefaults.standard.string(forKey: "currentUserUsername") {
            let phone = UserDefaults.standard.string(forKey: "currentUserPhone") ?? ""
            currentUser = AppUser(id: id, firstName: firstName, username: username, phone: phone)
        }
    }

    func sendCode(phoneNumber: String) async -> Bool {
        registrationError = nil
        self.phoneNumber = phoneNumber
        let result = await FirebaseService.shared.sendVerificationCode(phoneNumber: phoneNumber)
        switch result {
        case .success:
            return true
        case .failure(let error):
            registrationError = error.localizedDescription
            return false
        }
    }

    func verifyCode(_ code: String) async -> Bool {
        registrationError = nil
        let result = await FirebaseService.shared.verifyCode(code)
        switch result {
        case .success:
            isBackendAvailable = true
            return true
        case .failure(let error):
            registrationError = error.localizedDescription
            return false
        }
    }

    func checkForExistingUser() async -> Bool {
        let firebase = FirebaseService.shared
        guard firebase.isSignedIn, let uid = firebase.firebaseUID else { return false }
        guard let profile = await firebase.loadUserProfile() else { return false }
        guard !profile.username.isEmpty else { return false }

        isBackendAvailable = true
        currentUser = AppUser(id: uid, firstName: profile.firstName,
                              username: profile.username, phone: profile.phone)
        return true
    }

    func register(username: String, firstName: String? = nil) async -> Bool {
        registrationError = nil
        let displayName = firstName ?? username
        let firebase = FirebaseService.shared

        guard firebase.isSignedIn, let uid = firebase.firebaseUID else {
            registrationError = "Not signed in. Please go back and verify your phone number."
            return false
        }

        let claimed = await firebase.claimUsernameAndCreateProfile(
            username: username,
            firstName: displayName,
            phone: phoneNumber
        )

        guard claimed else {
            registrationError = "Username is taken. Please choose another."
            return false
        }

        isBackendAvailable = true
        currentUser = AppUser(id: uid, firstName: displayName, username: username.lowercased(), phone: phoneNumber)
        return true
    }

    func loadData() async {
        guard currentUser != nil else { return }
        isLoading = true

        let firebase = FirebaseService.shared

        if !firebase.isSignedIn {
            isBackendAvailable = false
            isLoading = false
            isOnboarded = false
            return
        }

        isBackendAvailable = true

        if let uid = firebase.firebaseUID, currentUser?.id != uid {
            let oldUser = currentUser!
            currentUser = AppUser(id: uid, firstName: oldUser.firstName, username: oldUser.username, phone: oldUser.phone)
        }

        if let profile = await firebase.loadUserProfile() {
            let uid = firebase.firebaseUID ?? currentUser!.id
            currentUser = AppUser(
                id: uid,
                firstName: profile.firstName,
                username: profile.username,
                phone: profile.phone
            )
        }

        let serverLikes = await firebase.loadLikedShareIds()
        if !serverLikes.isEmpty {
            likedShareIds = serverLikes
        }

        let serverFriends = await firebase.loadFriends()
        if !serverFriends.isEmpty {
            friends = serverFriends
        } else if friends.isEmpty {
            friends = MockData.friends
        }

        let serverReceived = await firebase.loadReceivedShares()
        if !serverReceived.isEmpty {
            receivedShares = serverReceived
        } else if receivedShares.isEmpty {
            await loadSampleShares()
        }

        let serverSent = await firebase.loadSentShares()
        if !serverSent.isEmpty {
            sentShares = serverSent
        }

        await loadConversations()
        isLoading = false
    }

    func sendSong(_ song: Song, to friend: AppUser, note: String?) async {
        guard let user = currentUser else { return }

        let share = SongShare(
            song: song,
            sender: AppUser(id: user.id, firstName: user.firstName, username: user.username, phone: user.phone),
            recipient: friend,
            note: note?.isEmpty == true ? nil : note
        )
        sentShares.insert(share, at: 0)
        updateWidgetData(share: share)

        Task { await FirebaseService.shared.saveShare(share) }

        let firebase = FirebaseService.shared
        if let conv = await firebase.getOrCreateConversation(with: friend.id, friendName: friend.firstName) {
            let messageText = note?.isEmpty == false ? note! : "Sent you a song"
            await firebase.sendMessage(conversationId: conv.id, text: messageText, song: song)
            await loadConversations()
        }

        showSentToast = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            showSentToast = false
        }
    }

    func loadConversations() async {
        let firebase = FirebaseService.shared
        guard firebase.isSignedIn else { return }
        conversations = await firebase.loadConversations()
    }

    func sendMessage(conversationId: String, text: String, song: Song? = nil) async {
        await FirebaseService.shared.sendMessage(conversationId: conversationId, text: text, song: song)
        await loadConversations()
    }

    func searchSongs(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            searchResults = []
            isSearchingSongs = false
            return
        }

        isSearchingSongs = true
        do {
            searchResults = try await MusicSearchService.shared.search(term: trimmed)
        } catch {
            searchResults = []
        }
        isSearchingSongs = false
    }

    func searchFriends(query: String) -> [AppUser] {
        guard !query.isEmpty else { return friends }
        return friends.filter {
            $0.firstName.localizedCaseInsensitiveContains(query) ||
            $0.username.localizedCaseInsensitiveContains(query)
        }
    }

    func searchAllUsers(query: String) async -> [AppUser] {
        if FirebaseService.shared.isSignedIn {
            let results = await FirebaseService.shared.searchUsers(query: query)
            if !results.isEmpty { return results }
        }
        return searchFriends(query: query)
    }

    func checkUsername(_ username: String) async -> Bool? {
        try? await Task.sleep(for: .milliseconds(300))
        guard FirebaseService.shared.isSignedIn else { return nil }

        if let taken = await FirebaseService.shared.isUsernameTaken(username) {
            return !taken
        }
        return nil
    }

    func toggleLike(shareId: String) {
        if likedShareIds.contains(shareId) {
            likedShareIds.remove(shareId)
            Task { await FirebaseService.shared.removeLike(shareId: shareId) }
        } else {
            likedShareIds.insert(shareId)
            Task { await FirebaseService.shared.saveLike(shareId: shareId) }
        }
    }

    func isLiked(shareId: String) -> Bool {
        likedShareIds.contains(shareId)
    }

    func logout() {
        currentUser = nil
        friends = []
        receivedShares = []
        sentShares = []
        likedShareIds = []
        conversations = []
        isOnboarded = false
        isBackendAvailable = false
        AudioPlayerService.shared.stop()
        FirebaseService.shared.signOut()
        UserDefaults.standard.removeObject(forKey: "currentUserId")
        UserDefaults.standard.removeObject(forKey: "currentUserFirstName")
        UserDefaults.standard.removeObject(forKey: "currentUserUsername")
        UserDefaults.standard.removeObject(forKey: "currentUserPhone")
        UserDefaults.standard.removeObject(forKey: "likedShareIds")
        UserDefaults.standard.removeObject(forKey: "preferredMusicService")
    }

    func refreshShares() async {
        let firebase = FirebaseService.shared
        guard firebase.isSignedIn else { return }

        let serverReceived = await firebase.loadReceivedShares()
        if !serverReceived.isEmpty {
            receivedShares = serverReceived
        }

        let serverSent = await firebase.loadSentShares()
        if !serverSent.isEmpty {
            sentShares = serverSent
        }

        let serverLikes = await firebase.loadLikedShareIds()
        if !serverLikes.isEmpty {
            likedShareIds = serverLikes
        }
    }

    private func mapShare(_ response: APIShareResponse) -> SongShare? {
        guard let songResp = response.song,
              let senderResp = response.sender,
              let recipientResp = response.recipient else { return nil }

        let song = Song(id: songResp.id, title: songResp.title, artist: songResp.artist, albumArtURL: songResp.albumArtURL, duration: songResp.duration)
        let sender = AppUser(id: senderResp.id, firstName: senderResp.firstName, username: senderResp.username, phone: senderResp.phone)
        let recipient = AppUser(id: recipientResp.id, firstName: recipientResp.firstName, username: recipientResp.username, phone: recipientResp.phone)

        return SongShare(
            id: response.id,
            song: song,
            sender: sender,
            recipient: recipient,
            note: response.note,
            timestamp: ISO8601DateFormatter().date(from: response.createdAt) ?? Date()
        )
    }

    private func loadSampleShares() async {
        guard let user = currentUser else { return }
        let me = AppUser(id: user.id, firstName: user.firstName, username: user.username, phone: user.phone)
        let molly = MockData.friends[0]

        var feedSong = MockData.songs[0]
        if let results = try? await MusicSearchService.shared.search(term: "Blinding Lights The Weeknd", limit: 1),
           let realSong = results.first {
            feedSong = realSong
        }

        receivedShares = [
            SongShare(song: feedSong, sender: molly, recipient: me, note: "this song reminds me of you", timestamp: Date().addingTimeInterval(-300)),
        ]

        sentShares = []
    }

    private func updateWidgetData(share: SongShare) {
        let defaults = UserDefaults(suiteName: "group.app.rork.playme.shared")
        defaults?.set(share.song.title, forKey: "widgetSongTitle")
        defaults?.set(share.song.artist, forKey: "widgetSongArtist")
        defaults?.set(share.song.albumArtURL, forKey: "widgetAlbumArtURL")
        defaults?.set(share.sender.initials, forKey: "widgetSenderInitials")
        defaults?.set(share.note, forKey: "widgetNote")
        defaults?.set(share.id, forKey: "widgetShareId")
        WidgetCenter.shared.reloadAllTimelines()
    }
}
