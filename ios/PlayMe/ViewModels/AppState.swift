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
    var receivedShares: [SongShare] = []
    var sentShares: [SongShare] = []
    var likedShareIds: Set<String> = [] {
        didSet {
            UserDefaults.standard.set(Array(likedShareIds), forKey: "likedShareIds")
        }
    }
    var showSentToast = false
    var isLoading = false
    var isBackendAvailable = false

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

    func register(phone: String, firstName: String, username: String) async {
        do {
            let response = try await APIService.shared.register(phone: phone, firstName: firstName, username: username)
            currentUser = AppUser(id: response.id, firstName: response.firstName, username: response.username, phone: response.phone)
            isBackendAvailable = true
        } catch {
            let localId = UUID().uuidString
            currentUser = AppUser(id: localId, firstName: firstName, username: username, phone: phone)
            isBackendAvailable = false
        }
    }

    func loadData() async {
        guard let user = currentUser else { return }
        isLoading = true

        do {
            let remoteSongs = try await APIService.shared.getSongs()
            songs = remoteSongs.map { Song(id: $0.id, title: $0.title, artist: $0.artist, albumArtURL: $0.albumArtURL, duration: $0.duration) }
            isBackendAvailable = true
        } catch {
            songs = MockData.songs
            isBackendAvailable = false
        }

        do {
            let remoteFriends = try await APIService.shared.getFriends(userId: user.id)
            friends = remoteFriends.map { AppUser(id: $0.id, firstName: $0.firstName, username: $0.username, phone: $0.phone) }
        } catch {
            if friends.isEmpty && !isBackendAvailable {
                friends = MockData.friends
            }
        }

        do {
            let received = try await APIService.shared.getReceivedShares(userId: user.id)
            receivedShares = received.compactMap { mapShare($0) }
        } catch {
            if receivedShares.isEmpty && !isBackendAvailable {
                loadSampleShares()
            }
        }

        do {
            let sent = try await APIService.shared.getSentShares(userId: user.id)
            sentShares = sent.compactMap { mapShare($0) }
        } catch {
            // keep existing
        }

        isLoading = false
    }

    func sendSong(_ song: Song, to friend: AppUser, note: String?) async {
        guard let user = currentUser else { return }

        do {
            let response = try await APIService.shared.sendShare(
                senderId: user.id,
                recipientId: friend.id,
                songId: song.id,
                note: note?.isEmpty == true ? nil : note
            )
            if let share = mapShare(response) {
                sentShares.insert(share, at: 0)
                updateWidgetData(share: share)
            }
        } catch {
            let share = SongShare(
                song: song,
                sender: currentUser ?? AppUser(id: "me", firstName: "Me", username: "me", phone: ""),
                recipient: friend,
                note: note?.isEmpty == true ? nil : note
            )
            sentShares.insert(share, at: 0)
            updateWidgetData(share: share)
        }

        showSentToast = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            showSentToast = false
        }
    }

    func searchSongs(query: String) -> [Song] {
        guard !query.isEmpty else { return songs }
        return songs.filter {
            $0.title.localizedCaseInsensitiveContains(query) ||
            $0.artist.localizedCaseInsensitiveContains(query)
        }
    }

    func searchFriends(query: String) -> [AppUser] {
        guard !query.isEmpty else { return friends }
        return friends.filter {
            $0.firstName.localizedCaseInsensitiveContains(query) ||
            $0.username.localizedCaseInsensitiveContains(query)
        }
    }

    func searchAllUsers(query: String) async -> [AppUser] {
        guard !query.isEmpty, let user = currentUser else { return [] }
        do {
            let results = try await APIService.shared.searchUsers(query: query, excludeUserId: user.id)
            return results.map { AppUser(id: $0.id, firstName: $0.firstName, username: $0.username, phone: $0.phone) }
        } catch {
            return searchFriends(query: query)
        }
    }

    func checkUsername(_ username: String) async -> Bool? {
        do {
            return try await APIService.shared.checkUsername(username)
        } catch {
            return nil
        }
    }

    func toggleLike(shareId: String) {
        if likedShareIds.contains(shareId) {
            likedShareIds.remove(shareId)
        } else {
            likedShareIds.insert(shareId)
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
        UserDefaults.standard.removeObject(forKey: "currentUserId")
        UserDefaults.standard.removeObject(forKey: "currentUserFirstName")
        UserDefaults.standard.removeObject(forKey: "currentUserUsername")
        UserDefaults.standard.removeObject(forKey: "currentUserPhone")
        UserDefaults.standard.removeObject(forKey: "likedShareIds")
    }

    func refreshShares() async {
        guard let user = currentUser else { return }
        do {
            let received = try await APIService.shared.getReceivedShares(userId: user.id)
            receivedShares = received.compactMap { mapShare($0) }
            let sent = try await APIService.shared.getSentShares(userId: user.id)
            sentShares = sent.compactMap { mapShare($0) }
        } catch {}
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

        receivedShares = [
            SongShare(song: MockData.songs[0], sender: molly, recipient: me, note: "this song reminds me of you 💛", timestamp: Date().addingTimeInterval(-300)),
            SongShare(song: MockData.songs[3], sender: alice, recipient: me, note: "good lil song to wake up to", timestamp: Date().addingTimeInterval(-7200)),
            SongShare(song: MockData.songs[5], sender: ben, recipient: me, note: nil, timestamp: Date().addingTimeInterval(-86400)),
            SongShare(song: MockData.songs[7], sender: molly, recipient: me, note: "fell asleep to this and thought of u", timestamp: Date().addingTimeInterval(-172800)),
        ]

        sentShares = [
            SongShare(song: MockData.songs[1], sender: me, recipient: molly, note: "listen to this rn", timestamp: Date().addingTimeInterval(-3600)),
            SongShare(song: MockData.songs[4], sender: me, recipient: ben, note: nil, timestamp: Date().addingTimeInterval(-43200)),
        ]
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
