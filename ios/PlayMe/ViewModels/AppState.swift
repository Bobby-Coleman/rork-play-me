import SwiftUI
import WidgetKit

@Observable
@MainActor
class AppState {
    var isOnboarded: Bool = UserDefaults.standard.bool(forKey: "isOnboarded") {
        didSet { UserDefaults.standard.set(isOnboarded, forKey: "isOnboarded") }
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
    var spotifySavedSong: Song?
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

    func register(username: String) async -> Bool {
        registrationError = nil

        let firebase = FirebaseService.shared
        let uid = firebase.firebaseUID ?? UUID().uuidString
        currentUser = AppUser(id: uid, firstName: username, username: username, phone: "")

        if firebase.isSignedIn {
            isBackendAvailable = true
            let spotifyAuth = SpotifyAuthService.shared
            await firebase.createOrUpdateUserProfile(
                username: username,
                spotifyDisplayName: spotifyAuth.userDisplayName,
                spotifyId: nil
            )
        } else {
            isBackendAvailable = false
        }

        return true
    }

    func loadData() async {
        guard let user = currentUser else { return }
        isLoading = true

        let spotifyAuth = SpotifyAuthService.shared
        if spotifyAuth.isAuthenticated {
            await spotifyAuth.fetchUserProfile()
            if let savedTrack = await spotifyAuth.fetchRecentSavedTrack() {
                spotifySavedSong = savedTrack
            }

            if !FirebaseService.shared.isSignedIn, let token = spotifyAuth.accessToken {
                let signedIn = await FirebaseService.shared.signInWithSpotify(spotifyAccessToken: token)
                if signedIn {
                    isBackendAvailable = true
                }
            } else if FirebaseService.shared.isSignedIn {
                isBackendAvailable = true
            }
        }

        let firebase = FirebaseService.shared
        if firebase.isSignedIn {
            if let profile = await firebase.loadUserProfile() {
                if currentUser?.username != profile.username {
                    currentUser = AppUser(
                        id: firebase.firebaseUID ?? user.id,
                        firstName: profile.firstName,
                        username: profile.username,
                        phone: ""
                    )
                }
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
                loadSampleShares()
            }

            let serverSent = await firebase.loadSentShares()
            if !serverSent.isEmpty {
                sentShares = serverSent
            }
        } else {
            if friends.isEmpty {
                friends = MockData.friends
            }
            if receivedShares.isEmpty {
                loadSampleShares()
            }
        }

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

        showSentToast = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            showSentToast = false
        }
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
            if let token = await SpotifyAuthService.shared.validToken() {
                let results = try await MusicSearchService.shared.searchSpotify(term: trimmed, token: token)
                if !results.isEmpty {
                    searchResults = results
                } else {
                    searchResults = try await MusicSearchService.shared.search(term: trimmed)
                }
            } else {
                searchResults = try await MusicSearchService.shared.search(term: trimmed)
            }
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
        guard FirebaseService.shared.isSignedIn else { return true }

        let results = await FirebaseService.shared.searchUsers(query: username.lowercased())
        let taken = results.contains { $0.username.lowercased() == username.lowercased() }
        return !taken
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
        isOnboarded = false
        isBackendAvailable = false
        AudioPlayerService.shared.stop()
        SpotifyPlaybackService.shared.disconnect()
        SpotifyAuthService.shared.logout()
        FirebaseService.shared.signOut()
        UserDefaults.standard.removeObject(forKey: "currentUserId")
        UserDefaults.standard.removeObject(forKey: "currentUserFirstName")
        UserDefaults.standard.removeObject(forKey: "currentUserUsername")
        UserDefaults.standard.removeObject(forKey: "currentUserPhone")
        UserDefaults.standard.removeObject(forKey: "likedShareIds")
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

    private func loadSampleShares() {
        guard let user = currentUser else { return }
        let me = AppUser(id: user.id, firstName: user.firstName, username: user.username, phone: user.phone)
        let molly = MockData.friends[0]
        let alice = MockData.friends[1]
        let ben = MockData.friends[2]

        let feedSong = spotifySavedSong ?? MockData.songs[0]

        receivedShares = [
            SongShare(song: feedSong, sender: molly, recipient: me, note: "this song reminds me of you 💛", timestamp: Date().addingTimeInterval(-300)),
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
