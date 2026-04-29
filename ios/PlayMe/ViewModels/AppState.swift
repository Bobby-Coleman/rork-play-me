import SwiftUI
import UIKit
import UserNotifications
import WidgetKit
import FirebaseFirestore
import MusicKit

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
                UserDefaults.standard.set(user.lastName, forKey: "currentUserLastName")
                UserDefaults.standard.set(user.username, forKey: "currentUserUsername")
                UserDefaults.standard.set(user.phone, forKey: "currentUserPhone")
            }
        }
    }

    var friends: [AppUser] = []
    /// Incoming pending friend requests for the current user. Live-updated by
    /// a Firestore snapshot listener attached in `loadData`. Drives the red
    /// badge on the Add Friends pill and the "Friend Requests" section of
    /// AddFriendsView. Each mutation also recomputes the app-icon badge so
    /// pending requests are reflected alongside unread messages.
    var incomingRequests: [AppUser] = [] {
        didSet { recomputeBadge() }
    }
    /// UIDs the current user has a *pending outgoing* friend request to.
    /// Hydrated lazily per visible search result so AddFriendsView can show
    /// "Requested" instead of "Add" on re-entry.
    var outgoingRequestUIDs: Set<String> = []
    /// Transient success toast for friend-request actions (e.g. "Request sent
    /// to @ari"). Cleared automatically after a short delay.
    var friendRequestToast: String? = nil
    /// Transient error banner if a friend-request write fails (rules denied,
    /// network issue). Surfaces the failure so users know to retry.
    var friendRequestError: String? = nil
    /// Incremented by `ContentView` whenever the user taps the Discovery
    /// tab's magnifier while already on the Discovery tab but scrolled into
    /// the history feed. `DiscoveryView` observes this counter and animates
    /// its internal ScrollViewReader back to the hero page. Decoupled as a
    /// counter instead of a boolean so consecutive taps always trigger a
    /// state change (vs. a sticky `true` that needs resetting).
    var discoveryScrollToTopCounter: Int = 0
    /// Share ID to scroll to on the Discovery feed. Set by the widget
    /// deep-link handler (`playme://share/<id>`) so tapping the home-screen
    /// widget drops the user on the exact song the widget was displaying —
    /// the most recently received share — instead of the hero page.
    /// `DiscoveryView` observes this, scrolls, and clears it back to nil.
    /// On a cold launch the share list may not be hydrated yet, so
    /// `DiscoveryView` also re-checks when `receivedShares` changes.
    var pendingDiscoveryShareId: String? = nil
    /// Firestore listener for incoming friend requests. Retained so we can
    /// detach on logout and reattach on sign-in.
    private var incomingRequestsListener: ListenerRegistration?
    /// Firestore listener for the current user's received shares. Drives
    /// real-time home-feed updates; detached on logout.
    private var receivedSharesListener: ListenerRegistration?
    /// Listener for received mixtape shares (parallel collection so it
    /// doesn't compete with the song-share listener's index).
    private var receivedMixtapeSharesListener: ListenerRegistration?
    /// Listener for received album shares.
    private var receivedAlbumSharesListener: ListenerRegistration?
    /// Firestore listener for the current user's conversation inbox. Drives
    /// real-time inbox row updates (unread badge flips, new conversations,
    /// last-message preview) without requiring a manual `loadConversations`
    /// refresh call. Detached on logout.
    private var conversationsListener: ListenerRegistration?
    /// Debounce task used to coalesce bursts of widget reloads. When a batch
    /// of `receivedShares` updates lands in the same run loop (e.g. three
    /// back-to-back pushes), `syncWidgetWithLatestReceivedShare` cancels
    /// the previous task and schedules a single reload after 250ms. Keeps
    /// WidgetCenter reloads cheap during heavy listener activity.
    private var widgetReloadTask: Task<Void, Never>?
    /// UIDs the current user has blocked. Synced from Firestore on foreground;
    /// reads + list views filter against this set client-side so blocked users
    /// disappear from feeds, search results, and conversation rows.
    var blockedUserIds: Set<String> = []
    /// Per-friend send counter used to rank friends in the song send sheet by
    /// interaction frequency. Keyed by recipient UID. Hydrated from Firestore
    /// on `loadData()` and bumped optimistically inside `sendSong` so ordering
    /// updates without a refetch.
    var sendStats: [String: SendStat] = [:]
    var notificationsEnabled: Bool = true
    var songs: [Song] = []
    /// Bucketed search response for the current query, pre-ranked by
    /// Apple Music (MusicKit). View code just slices by `searchFilter`.
    /// See `SearchResults` for the shape.
    var searchResults: SearchResults = .empty
    /// Active filter tab (`All | Artists | Songs | Albums`). The service
    /// layer fetches everything every time and this just picks the slice.
    var searchFilter: SearchFilter = .all
    var isSearchingSongs: Bool = false
    /// Last-observed MusicKit authorization status. `noResultsView` gates
    /// the "Open Settings" prompt on this being `.denied`.
    var musicAuthStatus: MusicAuthorization.Status = MusicAuthorization.currentStatus

    /// Convenience for views that only need to know whether to surface
    /// the Settings deep-link (keeps `import MusicKit` out of the view
    /// layer).
    var isMusicSearchDenied: Bool { musicAuthStatus == .denied }
    var receivedShares: [SongShare] = []
    var sentShares: [SongShare] = []
    /// Mixtapes shared with the current user. Ordered newest-first to
    /// match `receivedShares`. Listener-driven once `loadData` runs.
    var receivedMixtapeShares: [MixtapeShare] = []
    /// Mixtape shares the current user authored.
    var sentMixtapeShares: [MixtapeShare] = []
    /// Albums shared with the current user, newest-first.
    var receivedAlbumShares: [AlbumShare] = []
    /// Album shares the current user authored.
    var sentAlbumShares: [AlbumShare] = []
    var likedShareIds: Set<String> = [] {
        didSet {
            UserDefaults.standard.set(Array(likedShareIds), forKey: "likedShareIds")
        }
    }
    /// Index of which user-owned mixtapes contain a given `song.id`. Used
    /// by every Save UI in the app to render the "Save" / "Saved" toggle
    /// without per-cell scans of the mixtape graph. Source of truth for
    /// the icon state; mutations route through `mixtapeStore` so both this
    /// service and Firestore stay in sync.
    let saveService = SaveService()
    /// CRUD store for the user's mixtapes plus the synthetic "Liked"
    /// mixtape derived from `likedShareIds`. `allMixtapes` recomputes the
    /// synthetic piece on every read so the Liked surface stays reactive
    /// to like-toggle changes without a separate listener.
    let mixtapeStore = MixtapeStore()
    var conversations: [Conversation] = [] {
        didSet { recomputeBadge() }
    }

    var totalUnreadCount: Int {
        conversations.reduce(0) { $0 + $1.unreadCount }
    }

    /// App-icon badge reflects both unread DMs (sum of `unreadCount_<uid>`
    /// across conversations) and pending incoming friend requests. Reasons:
    /// - Users expect the badge to represent "things waiting for me", not
    ///   just messages — friend requests fit that intent.
    /// - Opening AddFriendsView clears the request portion; opening a
    ///   thread clears that conversation's portion. Both paths converge
    ///   through this recompute, so the number never drifts.
    private func recomputeBadge() {
        let convUnread = conversations.reduce(0) { $0 + $1.unreadCount }
        let reqUnread = incomingRequests.count
        UNUserNotificationCenter.current().setBadgeCount(convUnread + reqUnread)
    }

    /// `friends` sorted by how often the current user has sent to them:
    /// 1) send count descending, 2) most-recent send descending (nil last),
    /// 3) first name ascending as the stable fallback. Used by the song send
    /// sheet chip row.
    var friendsRankedByActivity: [AppUser] {
        friends.sorted { lhs, rhs in
            let lhsStat = sendStats[lhs.id]
            let rhsStat = sendStats[rhs.id]
            let lhsCount = lhsStat?.count ?? 0
            let rhsCount = rhsStat?.count ?? 0
            if lhsCount != rhsCount { return lhsCount > rhsCount }

            switch (lhsStat?.lastSentAt, rhsStat?.lastSentAt) {
            case let (l?, r?) where l != r: return l > r
            case (_?, nil): return true
            case (nil, _?): return false
            default: break
            }

            return lhs.firstName.localizedCaseInsensitiveCompare(rhs.firstName) == .orderedAscending
        }
    }
    var phoneNumber: String = ""
    var showSentToast = false
    var isLoading = false
    var isBackendAvailable = false
    var registrationError: String? = nil
    /// Transient success toast for queued-share-to-pending-contact sends.
    /// e.g. "We'll deliver to Holli when she joins."
    var queuedContactToast: String? = nil
    /// Transient error banner if a queued-share write failed (permission
    /// denied, bad phone, network). Surfaced in SendFirstSongView.
    var queuedContactError: String? = nil

    // MARK: - Onboarding-only state (cleared after onboarding completes)
    /// Contacts the user texted invites to during OnboardingInviteView.
    /// Surfaced in the SendFirstSongView friend carousel so first songs can be
    /// queued for them via `sendSongToPendingContact`.
    var invitedContacts: [SimpleContact] = []

    var likedShares: [SongShare] {
        (receivedShares + sentShares).filter { likedShareIds.contains($0.id) }
            .sorted { $0.timestamp > $1.timestamp }
    }

    init() {
        loadSavedUser()
        likedShareIds = Set(UserDefaults.standard.stringArray(forKey: "likedShareIds") ?? [])
        // Wire MixtapeStore ↔ SaveService now (before any async load), and
        // give the store a closure for `likedShares` so the synthetic
        // Liked mixtape stays reactive to per-share like toggles without
        // a separate observer hookup.
        mixtapeStore.saveService = saveService
        mixtapeStore.likedSharesProvider = { [weak self] in self?.likedShares ?? [] }
        // Fire-and-forget: caches MusicKit's auth status off the hot
        // path so the first keystroke in search doesn't pay for it.
        Task { await AppleMusicSearchService.shared.prewarmAuthorization() }
    }

    private func loadSavedUser() {
        if let id = UserDefaults.standard.string(forKey: "currentUserId"),
           let firstName = UserDefaults.standard.string(forKey: "currentUserFirstName"),
           let username = UserDefaults.standard.string(forKey: "currentUserUsername") {
            let lastName = UserDefaults.standard.string(forKey: "currentUserLastName") ?? ""
            let phone = UserDefaults.standard.string(forKey: "currentUserPhone") ?? ""
            currentUser = AppUser(id: id, firstName: firstName, lastName: lastName, username: username, phone: phone)
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
                              lastName: profile.lastName,
                              username: profile.username, phone: profile.phone)

        // Ask the server to fan out any pending-shares waiting on this phone.
        // The Cloud Function reads users/{uid}.phone and runs the claim.
        await firebase.requestPendingSharesClaim()
        return true
    }

    func register(username: String, firstName: String, lastName: String = "") async -> Bool {
        registrationError = nil
        let firebase = FirebaseService.shared

        guard firebase.isSignedIn, let uid = firebase.firebaseUID else {
            registrationError = "Not signed in. Please go back and verify your phone number."
            return false
        }

        let claimed = await firebase.claimUsernameAndCreateProfile(
            username: username,
            firstName: firstName,
            lastName: lastName,
            phone: phoneNumber
        )

        guard claimed else {
            registrationError = "Username is taken. Please choose another."
            return false
        }

        isBackendAvailable = true
        currentUser = AppUser(id: uid, firstName: firstName, lastName: lastName, username: username.lowercased(), phone: phoneNumber)

        // The `onUserProfileCreated` Cloud Function will fire automatically from
        // the users/{uid} doc creation in `claimUsernameAndCreateProfile`. We
        // also write a claimRequest as belt-and-suspenders in case the trigger
        // missed (e.g. if the profile doc already existed from a prior signup).
        await firebase.requestPendingSharesClaim()

        await processReferralIfNeeded(currentUID: uid)

        return true
    }

    func processReferralIfNeeded(currentUID: String) async {
        guard let referrerId = DeepLinkService.shared.pendingReferrerId,
              !referrerId.isEmpty,
              referrerId != currentUID else {
            DeepLinkService.shared.clearPendingReferrer()
            return
        }

        if let profile = await FirebaseService.shared.fetchUserProfile(uid: referrerId) {
            await FirebaseService.shared.addFriend(
                friendUID: referrerId,
                friendUsername: profile.username,
                friendFirstName: profile.firstName,
                friendLastName: profile.lastName
            )
            await refreshFriends()
        }

        DeepLinkService.shared.clearPendingReferrer()
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
            currentUser = AppUser(id: uid, firstName: oldUser.firstName, lastName: oldUser.lastName, username: oldUser.username, phone: oldUser.phone)
        }

        if let profile = await firebase.loadUserProfile() {
            let uid = firebase.firebaseUID ?? currentUser!.id
            currentUser = AppUser(
                id: uid,
                firstName: profile.firstName,
                lastName: profile.lastName,
                username: profile.username,
                phone: profile.phone
            )
        }

        let serverLikes = await firebase.loadLikedShareIds()
        if !serverLikes.isEmpty {
            likedShareIds = serverLikes
        }

        let serverFriends = await firebase.loadFriends()
        blockedUserIds = await firebase.loadBlockedUserIds()
        friends = serverFriends.filter { !blockedUserIds.contains($0.id) }
        sendStats = await firebase.loadSendStats()

        await refreshFriendRequests()
        startIncomingRequestsListener()
        startReceivedSharesListener()
        startReceivedMixtapeSharesListener()
        startReceivedAlbumSharesListener()
        startConversationsListener()

        notificationsEnabled = await firebase.loadNotificationsEnabled()

        let serverReceived = await firebase.loadReceivedShares()
            .filter { !blockedUserIds.contains($0.sender.id) }
        receivedShares = serverReceived

        let serverSent = await firebase.loadSentShares()
        if !serverSent.isEmpty {
            sentShares = serverSent
        }

        // Initial paint of mixtape/album shares before the listener
        // delivers its first snapshot. Filter `blockedUserIds` so a
        // newly-blocked sender's history disappears immediately.
        async let recvMix: [MixtapeShare] = firebase.loadReceivedMixtapeShares()
        async let sentMix: [MixtapeShare] = firebase.loadSentMixtapeShares()
        async let recvAlb: [AlbumShare] = firebase.loadReceivedAlbumShares()
        async let sentAlb: [AlbumShare] = firebase.loadSentAlbumShares()
        let (rm, sm, ra, sa) = await (recvMix, sentMix, recvAlb, sentAlb)
        receivedMixtapeShares = rm.filter { !blockedUserIds.contains($0.sender.id) }
        sentMixtapeShares = sm
        receivedAlbumShares = ra.filter { !blockedUserIds.contains($0.sender.id) }
        sentAlbumShares = sa

        // Hydrate the SaveService index and the user's mixtapes in
        // parallel — they live in independent subcollections, and
        // neither blocks first-paint of the home / discovery feeds. The
        // Mixtapes screen will see populated data the moment the user
        // navigates there.
        async let saveIndex: () = saveService.loadFromFirestore()
        async let mixtapeFetch: () = mixtapeStore.loadFromFirestore()
        _ = await (saveIndex, mixtapeFetch)

        await loadConversations()
        syncWidgetWithLatestReceivedShare()
        isLoading = false

        // Late-arriving queued shares (friend queued a song AFTER this user
        // signed up) need a retry. The claimRequest doc triggers the server
        // fan-out, and is cheap enough to run on every foreground.
        Task { await firebase.requestPendingSharesClaim() }
    }

    func sendSong(_ song: Song, to friend: AppUser, note: String?) async {
        guard let user = currentUser else { return }

        let enrichedSong = await enrichSongWithSpotifyURI(song)

        let share = SongShare(
            song: enrichedSong,
            sender: AppUser(id: user.id, firstName: user.firstName, lastName: user.lastName, username: user.username, phone: user.phone),
            recipient: friend,
            note: note?.isEmpty == true ? nil : note
        )
        sentShares.insert(share, at: 0)

        Task { await FirebaseService.shared.saveShare(share) }

        // Bump the per-friend send counter: optimistically locally (so the
        // chip row reorders immediately) and durably in Firestore.
        let previousCount = sendStats[friend.id]?.count ?? 0
        sendStats[friend.id] = SendStat(count: previousCount + 1, lastSentAt: Date())
        Task { await FirebaseService.shared.incrementSendStat(friendUid: friend.id) }

        let firebase = FirebaseService.shared
        if let conv = await firebase.getOrCreateConversation(with: friend.id, friendName: friend.firstName) {
            let messageText = note?.isEmpty == false ? note! : "Sent you a song"
            await firebase.sendMessage(conversationId: conv.id, text: messageText, song: enrichedSong)
            await loadConversations()
        }

        showSentToast = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            showSentToast = false
        }
    }

    /// Fan-out send of a whole mixtape to one or more friends. Mirrors
    /// `sendSong` for songs: optimistic local insert into
    /// `sentMixtapeShares`, durable Firestore writes in parallel,
    /// `showSentToast` flicker. The mixtape payload is snapshotted at
    /// send time — the recipient sees what was sent regardless of
    /// future edits.
    func sendMixtape(_ mixtape: Mixtape, to friends: [AppUser], note: String? = nil) async {
        guard let user = currentUser, !friends.isEmpty else { return }
        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedNote = (trimmedNote?.isEmpty ?? true) ? nil : trimmedNote
        let snapshot = mixtape

        let me = AppUser(
            id: user.id, firstName: user.firstName, lastName: user.lastName,
            username: user.username, phone: user.phone
        )
        var locallyInserted: [MixtapeShare] = []
        for friend in friends {
            let share = MixtapeShare(
                mixtape: snapshot,
                sender: me,
                recipient: friend,
                note: cleanedNote
            )
            locallyInserted.append(share)
        }
        sentMixtapeShares.insert(contentsOf: locallyInserted, at: 0)
        showSentToast = true

        await withTaskGroup(of: Void.self) { group in
            let firebase = FirebaseService.shared
            for share in locallyInserted {
                group.addTask { await firebase.saveMixtapeShare(share) }
            }
            // Bump per-friend send stats so the chip row reorders.
            for friend in friends {
                group.addTask { @MainActor [weak self] in
                    guard let self else { return }
                    let prev = self.sendStats[friend.id]?.count ?? 0
                    self.sendStats[friend.id] = SendStat(count: prev + 1, lastSentAt: Date())
                    await firebase.incrementSendStat(friendUid: friend.id)
                }
            }
        }

        Task {
            try? await Task.sleep(for: .seconds(2))
            showSentToast = false
        }
    }

    /// Fan-out send of a whole album. Identical pattern to
    /// `sendMixtape`. Tracklist is fetched once via
    /// `ArtistLookupService` and reused across all recipients so we
    /// don't re-hit iTunes per friend.
    func sendAlbum(_ album: Album, to friends: [AppUser], note: String? = nil) async {
        guard let user = currentUser, !friends.isEmpty else { return }
        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedNote = (trimmedNote?.isEmpty ?? true) ? nil : trimmedNote
        let tracks = (try? await ArtistLookupService.shared.fetchAlbumTracks(albumId: album.id)) ?? []
        guard !tracks.isEmpty else { return }

        let me = AppUser(
            id: user.id, firstName: user.firstName, lastName: user.lastName,
            username: user.username, phone: user.phone
        )
        var locallyInserted: [AlbumShare] = []
        for friend in friends {
            let share = AlbumShare(
                album: album,
                songs: tracks,
                sender: me,
                recipient: friend,
                note: cleanedNote
            )
            locallyInserted.append(share)
        }
        sentAlbumShares.insert(contentsOf: locallyInserted, at: 0)
        showSentToast = true

        await withTaskGroup(of: Void.self) { group in
            let firebase = FirebaseService.shared
            for share in locallyInserted {
                group.addTask { await firebase.saveAlbumShare(share) }
            }
            for friend in friends {
                group.addTask { @MainActor [weak self] in
                    guard let self else { return }
                    let prev = self.sendStats[friend.id]?.count ?? 0
                    self.sendStats[friend.id] = SendStat(count: prev + 1, lastSentAt: Date())
                    await firebase.incrementSendStat(friendUid: friend.id)
                }
            }
        }

        Task {
            try? await Task.sleep(for: .seconds(2))
            showSentToast = false
        }
    }

    /// Adds every track of `album` to the user's mixtape as individual
    /// `Song` entries (each tagged with `albumId = album.id` so the
    /// origin is preserved). Caller is responsible for the user-facing
    /// confirmation — by the time we reach this method the user has
    /// already acknowledged "this will add N songs". Fetches the
    /// tracklist via `ArtistLookupService` (cached) so a re-add of the
    /// same album is essentially free. Returns the count actually added,
    /// or 0 on any failure.
    @discardableResult
    func addAlbumToMixtape(_ album: Album, mixtapeId: String) async -> Int {
        guard currentUser != nil else { return 0 }
        let tracks: [Song]
        do {
            tracks = try await ArtistLookupService.shared.fetchAlbumTracks(albumId: album.id)
        } catch {
            print("AppState: addAlbumToMixtape fetch failed: \(error.localizedDescription)")
            return 0
        }
        guard !tracks.isEmpty else { return 0 }

        var added = 0
        for song in tracks {
            // Make sure every persisted song carries the album id so the
            // origin survives a refetch. Most `fetchAlbumTracks` results
            // already do (the service passes `overrideAlbumId`), but
            // we belt-and-suspender here so we never persist an
            // unattributed copy.
            let tagged = song.albumId == album.id ? song : Song(
                id: song.id,
                title: song.title,
                artist: song.artist,
                albumArtURL: song.albumArtURL,
                duration: song.duration,
                spotifyURI: song.spotifyURI,
                previewURL: song.previewURL,
                appleMusicURL: song.appleMusicURL,
                artistId: song.artistId,
                albumId: album.id
            )
            await mixtapeStore.addSong(tagged, to: mixtapeId)
            added += 1
        }
        return added
    }

    /// Queue a song for a contact who hasn't signed up yet. Written to
    /// `pendingShares/{e164}/shares/{id}`; fanned out by the
    /// `onUserProfileCreated` / `onClaimRequest` Cloud Functions the moment
    /// that contact finishes their own signup.
    @discardableResult
    func sendSongToPendingContact(_ song: Song, contact: SimpleContact, note: String?) async -> Bool {
        guard currentUser != nil else { return false }
        guard let e164 = PhoneNormalizer.normalize(contact.phoneNumber) else {
            print("AppState: event=pending_share_queue_failed reason=invalid_phone raw=\(contact.phoneNumber)")
            queuedContactError = "We couldn't read \(contact.firstName)'s phone number."
            clearQueuedContactFeedbackSoon()
            return false
        }
        print("AppState: event=pending_share_queue_attempt contact=\(contact.fullName) raw=\(contact.phoneNumber) normalized=\(e164)")

        let enriched = await enrichSongWithSpotifyURI(song)
        let result = await FirebaseService.shared.saveQueuedShare(
            phoneE164: e164,
            contactDisplayName: contact.fullName,
            song: enriched,
            note: note?.isEmpty == true ? nil : note
        )
        switch result {
        case .success:
            let firstName = contact.firstName.isEmpty ? contact.fullName : contact.firstName
            queuedContactToast = "We'll deliver to \(firstName) when they join."
            clearQueuedContactFeedbackSoon()
            return true
        case .failure(let err):
            queuedContactError = err.errorDescription ?? "We couldn't queue that song. Try again."
            clearQueuedContactFeedbackSoon()
            return false
        }
    }

    private func clearQueuedContactFeedbackSoon() {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self else { return }
            self.queuedContactToast = nil
            self.queuedContactError = nil
        }
    }

    private func enrichSongWithSpotifyURI(_ song: Song) async -> Song {
        if song.spotifyURI != nil { return song }
        guard let appleMusicURL = song.appleMusicURL else { return song }
        guard let resolvedURL = await MusicSearchService.shared.resolveSpotifyURL(appleMusicURL: appleMusicURL, title: song.title, artist: song.artist) else { return song }
        guard let trackID = SpotifyDeepLinkResolver.spotifyTrackID(fromSpotifyURL: resolvedURL) else { return song }
        return song.with(spotifyURI: "spotify:track:\(trackID)")
    }

    func loadConversations() async {
        let firebase = FirebaseService.shared
        guard firebase.isSignedIn else { return }
        let uid = firebase.firebaseUID ?? ""
        let loaded = await firebase.loadConversations()
        conversations = loaded.filter { convo in
            !blockedUserIds.contains(convo.friendId(currentUserId: uid))
        }
    }

    func sendMessage(
        conversationId: String,
        text: String,
        song: Song? = nil,
        replyTo: ChatMessage? = nil
    ) async {
        await FirebaseService.shared.sendMessage(
            conversationId: conversationId,
            text: text,
            song: song,
            replyTo: replyTo
        )
        await loadConversations()
    }

    /// MusicKit catalog search. Apple Music's own ranking model drives
    /// the order of songs/artists/albums — the same ordering you'd get
    /// in the Apple Music app itself. The view layer reads
    /// `searchResults` by the active `searchFilter`; bucket ordering is
    /// authoritative and we don't re-sort client-side.
    ///
    /// Note: this works for every authorized user regardless of whether
    /// they subscribe to Apple Music. Full-track playback still flows
    /// through `AudioPlayerService` (30s previews) and deep-linking via
    /// `resolveSpotifyURL` for Spotify-preferring users.
    func searchSongs(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            searchResults = .empty
            isSearchingSongs = false
            return
        }

        isSearchingSongs = true

        // Phase 1: typeahead. This is what makes search feel instant —
        // it returns Apple's prefix-aware top results (the same data
        // backing the Apple Music app's autocomplete) and is cheap on
        // Apple's side. The user sees populated buckets and we drop the
        // spinner here, before phase 2 has even fired.
        let phase1 = await AppleMusicSearchService.shared.searchTypeahead(term: trimmed)
        if Task.isCancelled {
            isSearchingSongs = false
            return
        }
        musicAuthStatus = phase1.authStatus
        searchResults = SearchResults(
            artists: phase1.artists,
            songs: phase1.songs,
            albums: phase1.albums,
            topHit: phase1.topHit
        )
        isSearchingSongs = false

        // Phase 2: expanded full-catalog search to pad each per-tab list
        // with extra rows below the typeahead head. We never demote
        // phase 1's topHit — that's the entry the user has been looking
        // at since results appeared, and Apple's typeahead is the
        // ranking model best-suited to surface it.
        let phase2 = await AppleMusicSearchService.shared.searchExpanded(term: trimmed)
        if Task.isCancelled { return }

        searchResults = SearchResults(
            artists: AppleMusicSearchService.mergeDedupe(
                primary: phase1.artists, fallback: phase2.artists, id: \ArtistSummary.id
            ),
            songs: AppleMusicSearchService.mergeDedupe(
                primary: phase1.songs, fallback: phase2.songs, id: \Song.id
            ),
            albums: AppleMusicSearchService.mergeDedupe(
                primary: phase1.albums, fallback: phase2.albums, id: \Album.id
            ),
            topHit: searchResults.topHit
        )
    }

    func refreshFriends() async {
        let firebase = FirebaseService.shared
        blockedUserIds = await firebase.loadBlockedUserIds()
        let serverFriends = await firebase.loadFriends()
        if !serverFriends.isEmpty {
            friends = serverFriends.filter { !blockedUserIds.contains($0.id) }
        }
    }

    // MARK: - Friend Requests

    /// One-shot refresh of incoming friend requests. Outgoing state is
    /// hydrated lazily per visible search result via `hasOutgoingRequest` to
    /// avoid a full-collection scan the security rules don't allow anyway.
    func refreshFriendRequests() async {
        let firebase = FirebaseService.shared
        guard firebase.isSignedIn else { return }
        let incoming = await firebase.loadIncomingRequests()
        incomingRequests = incoming.filter { !blockedUserIds.contains($0.id) }
    }

    /// Attach (or reattach) the snapshot listener that keeps
    /// `incomingRequests` in sync with Firestore so the pill badge updates
    /// in real time. Idempotent.
    private func startIncomingRequestsListener() {
        incomingRequestsListener?.remove()
        incomingRequestsListener = FirebaseService.shared.listenIncomingRequests { [weak self] requests in
            Task { @MainActor in
                guard let self else { return }
                self.incomingRequests = requests.filter { !self.blockedUserIds.contains($0.id) }
            }
        }
    }

    /// Attach (or reattach) the snapshot listener that keeps
    /// `receivedShares` in sync with Firestore so the home feed updates in
    /// real time when a friend sends a new song. Idempotent.
    private func startReceivedSharesListener() {
        receivedSharesListener?.remove()
        receivedSharesListener = FirebaseService.shared.listenReceivedShares { [weak self] shares in
            Task { @MainActor in
                guard let self else { return }
                self.receivedShares = shares.filter { !self.blockedUserIds.contains($0.sender.id) }
                self.syncWidgetWithLatestReceivedShare()
            }
        }
    }

    /// Listener for inbound mixtape shares. Mirrors `startReceivedSharesListener`
    /// so the Received segment updates in real time when a friend sends a
    /// whole mixtape. Idempotent — detached cleanly on logout.
    private func startReceivedMixtapeSharesListener() {
        receivedMixtapeSharesListener?.remove()
        receivedMixtapeSharesListener = FirebaseService.shared.listenReceivedMixtapeShares { [weak self] shares in
            Task { @MainActor in
                guard let self else { return }
                self.receivedMixtapeShares = shares.filter { !self.blockedUserIds.contains($0.sender.id) }
            }
        }
    }

    /// Listener for inbound album shares.
    private func startReceivedAlbumSharesListener() {
        receivedAlbumSharesListener?.remove()
        receivedAlbumSharesListener = FirebaseService.shared.listenReceivedAlbumShares { [weak self] shares in
            Task { @MainActor in
                guard let self else { return }
                self.receivedAlbumShares = shares.filter { !self.blockedUserIds.contains($0.sender.id) }
            }
        }
    }

    /// Attach (or reattach) the snapshot listener that keeps the inbox
    /// (`conversations`) in sync with Firestore. Replaces the previous
    /// one-shot `loadConversations` poll model, so inbox rows reflect
    /// unread-count flips, new threads, and last-message previews the
    /// instant they happen server-side. Idempotent.
    private func startConversationsListener() {
        conversationsListener?.remove()
        conversationsListener = FirebaseService.shared.listenConversations { [weak self] convos in
            Task { @MainActor in
                guard let self else { return }
                let uid = FirebaseService.shared.firebaseUID ?? ""
                self.conversations = convos.filter { !self.blockedUserIds.contains($0.friendId(currentUserId: uid)) }
            }
        }
    }

    /// Optimistically send a friend request: flips the chip to "Requested"
    /// before awaiting the write, shows a success toast, and rolls back with
    /// an error toast if Firestore rejects the write.
    @discardableResult
    func sendFriendRequest(to user: AppUser) async -> Bool {
        guard let me = currentUser else { return false }
        outgoingRequestUIDs.insert(user.id)
        let ok = await FirebaseService.shared.sendFriendRequest(
            toUID: user.id,
            username: me.username,
            firstName: me.firstName,
            lastName: me.lastName
        )
        if ok {
            let handle = user.username.isEmpty ? user.firstName : "@\(user.username)"
            friendRequestToast = "Request sent to \(handle)"
        } else {
            outgoingRequestUIDs.remove(user.id)
            friendRequestError = "Couldn't send request. Check your connection and try again."
        }
        clearFriendRequestFeedbackSoon()
        return ok
    }

    private func clearFriendRequestFeedbackSoon() {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard let self else { return }
            self.friendRequestToast = nil
            self.friendRequestError = nil
        }
    }

    /// Cancel a pending outgoing request.
    func cancelOutgoingRequest(to user: AppUser) async {
        await FirebaseService.shared.cancelOutgoingRequest(toUID: user.id)
        outgoingRequestUIDs.remove(user.id)
    }

    /// Accept an incoming friend request; refreshes `friends` so the
    /// accepted user shows up in the friends list right away.
    func acceptFriendRequest(_ user: AppUser) async {
        await FirebaseService.shared.acceptFriendRequest(from: user)
        incomingRequests.removeAll { $0.id == user.id }
        await refreshFriends()
    }

    func declineFriendRequest(_ user: AppUser) async {
        await FirebaseService.shared.declineFriendRequest(fromUID: user.id)
        incomingRequests.removeAll { $0.id == user.id }
    }

    /// Hydrate `outgoingRequestUIDs` for a batch of user IDs. Called by
    /// AddFriendsView when search results appear so chips render the correct
    /// state on first paint. Sequential to stay on the MainActor without
    /// sendability gymnastics around the FirebaseService singleton.
    func hydrateOutgoingRequests(for userIds: [String]) async {
        let firebase = FirebaseService.shared
        guard firebase.isSignedIn else { return }
        for uid in userIds where !outgoingRequestUIDs.contains(uid) {
            if await firebase.hasOutgoingRequest(toUID: uid) {
                outgoingRequestUIDs.insert(uid)
            }
        }
    }

    // MARK: - Blocking

    func blockUser(_ user: AppUser) async {
        await FirebaseService.shared.blockUser(user.id)
        blockedUserIds.insert(user.id)
        friends.removeAll { $0.id == user.id }
        receivedShares.removeAll { $0.sender.id == user.id }
        conversations.removeAll { convo in
            let uid = FirebaseService.shared.firebaseUID ?? ""
            return convo.friendId(currentUserId: uid) == user.id
        }
    }

    func unblockUser(_ uid: String) async {
        await FirebaseService.shared.unblockUser(uid)
        blockedUserIds.remove(uid)
    }

    func isBlocked(_ uid: String) -> Bool {
        blockedUserIds.contains(uid)
    }

    // MARK: - Reports

    /// Fire-and-forget report submission. Returns true if the write succeeded
    /// so the UI can show a confirmation toast.
    @discardableResult
    func reportUser(_ targetUid: String, reason: String, note: String? = nil) async -> Bool {
        await FirebaseService.shared.submitReport(
            targetUid: targetUid,
            targetType: .user,
            targetId: nil,
            reason: reason,
            note: note
        )
    }

    @discardableResult
    func reportShare(_ share: SongShare, reason: String, note: String? = nil) async -> Bool {
        await FirebaseService.shared.submitReport(
            targetUid: share.sender.id,
            targetType: .share,
            targetId: share.id,
            reason: reason,
            note: note
        )
    }

    @discardableResult
    func reportMessage(senderUid: String, conversationId: String, messageId: String, reason: String, note: String? = nil) async -> Bool {
        await FirebaseService.shared.submitReport(
            targetUid: senderUid,
            targetType: .message,
            targetId: "\(conversationId)/\(messageId)",
            reason: reason,
            note: note
        )
    }

    // MARK: - Notification prefs

    func setNotificationsEnabled(_ enabled: Bool) async {
        notificationsEnabled = enabled
        await FirebaseService.shared.setNotificationsEnabled(enabled)
    }

    /// Settings toggle: turns Firestore flag off immediately; turning on requests iOS permission first.
    /// - Returns `true` only when the user asked for notifications but iOS is `.denied` (show “Open Settings”).
    @discardableResult
    func syncNotificationsToggleFromSettings(enabled: Bool) async -> Bool {
        if !enabled {
            await setNotificationsEnabled(false)
            return false
        }
        let before = await NotificationPermission.currentAuthorizationStatus()
        if before == .denied {
            notificationsEnabled = false
            await setNotificationsEnabled(false)
            return true
        }
        let status = await NotificationPermission.requestAuthorizationAndRegister()
        switch status {
        case .authorized, .provisional, .ephemeral:
            await setNotificationsEnabled(true)
            return false
        case .denied, .notDetermined:
            notificationsEnabled = false
            await setNotificationsEnabled(false)
            return status == .denied
        @unknown default:
            notificationsEnabled = false
            await setNotificationsEnabled(false)
            return false
        }
    }

    // MARK: - Account Deletion

    /// Deletes the user's Firebase Auth account and all associated Firestore
    /// data via the `deleteAccount` Cloud Function. On success we fall through
    /// to the local logout cleanup so the app returns to onboarding.
    func deleteAccount() async -> Result<Void, FirebaseService.DeleteAccountError> {
        let result = await FirebaseService.shared.deleteAccount()
        switch result {
        case .success:
            logout()
            return .success(())
        case .failure(let err):
            return .failure(err)
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
        if FirebaseService.shared.isSignedIn {
            let results = await FirebaseService.shared.searchUsers(query: query)
                .filter { !blockedUserIds.contains($0.id) }
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
        incomingRequestsListener?.remove()
        incomingRequestsListener = nil
        receivedSharesListener?.remove()
        receivedSharesListener = nil
        receivedMixtapeSharesListener?.remove()
        receivedMixtapeSharesListener = nil
        receivedAlbumSharesListener?.remove()
        receivedAlbumSharesListener = nil
        conversationsListener?.remove()
        conversationsListener = nil
        widgetReloadTask?.cancel()
        widgetReloadTask = nil
        currentUser = nil
        friends = []
        incomingRequests = []
        outgoingRequestUIDs = []
        blockedUserIds = []
        sendStats = [:]
        receivedShares = []
        sentShares = []
        receivedMixtapeShares = []
        sentMixtapeShares = []
        receivedAlbumShares = []
        sentAlbumShares = []
        likedShareIds = []
        conversations = []
        saveService.clear()
        mixtapeStore.clear()
        isOnboarded = false
        isBackendAvailable = false
        AudioPlayerService.shared.stop()
        FirebaseService.shared.signOut()
        UserDefaults.standard.removeObject(forKey: "currentUserId")
        UserDefaults.standard.removeObject(forKey: "currentUserFirstName")
        UserDefaults.standard.removeObject(forKey: "currentUserLastName")
        UserDefaults.standard.removeObject(forKey: "currentUserUsername")
        UserDefaults.standard.removeObject(forKey: "currentUserPhone")
        UserDefaults.standard.removeObject(forKey: "likedShareIds")
        UserDefaults.standard.removeObject(forKey: "preferredMusicService")
        clearWidgetSharedState()
    }

    func refreshShares() async {
        let firebase = FirebaseService.shared
        guard firebase.isSignedIn else { return }

        blockedUserIds = await firebase.loadBlockedUserIds()

        let serverReceived = await firebase.loadReceivedShares()
            .filter { !blockedUserIds.contains($0.sender.id) }
        if !serverReceived.isEmpty {
            receivedShares = serverReceived
        }

        let serverSent = await firebase.loadSentShares()
        if !serverSent.isEmpty {
            sentShares = serverSent
        }

        // Mixtape + album shares refresh in parallel — they live in
        // independent collections, neither blocks the song-share
        // first paint, and both are bounded to 50 docs at the
        // service.
        async let recvMix: [MixtapeShare] = firebase.loadReceivedMixtapeShares()
        async let sentMix: [MixtapeShare] = firebase.loadSentMixtapeShares()
        async let recvAlb: [AlbumShare] = firebase.loadReceivedAlbumShares()
        async let sentAlb: [AlbumShare] = firebase.loadSentAlbumShares()
        let (rm, sm, ra, sa) = await (recvMix, sentMix, recvAlb, sentAlb)
        receivedMixtapeShares = rm.filter { !blockedUserIds.contains($0.sender.id) }
        sentMixtapeShares = sm
        receivedAlbumShares = ra.filter { !blockedUserIds.contains($0.sender.id) }
        sentAlbumShares = sa

        let serverLikes = await firebase.loadLikedShareIds()
        if !serverLikes.isEmpty {
            likedShareIds = serverLikes
        }

        // Refresh saves + mixtapes alongside shares so the Mixtapes screen
        // reflects new saves made on another device since last refresh.
        async let saveIndex: () = saveService.loadFromFirestore()
        async let mixtapeFetch: () = mixtapeStore.loadFromFirestore()
        _ = await (saveIndex, mixtapeFetch)

        syncWidgetWithLatestReceivedShare()
    }

    private func mapShare(_ response: APIShareResponse) -> SongShare? {
        guard let songResp = response.song,
              let senderResp = response.sender,
              let recipientResp = response.recipient else { return nil }

        let song = Song(id: songResp.id, title: songResp.title, artist: songResp.artist, albumArtURL: songResp.albumArtURL, duration: songResp.duration)
        let sender = AppUser(id: senderResp.id, firstName: senderResp.firstName, username: senderResp.username, phone: "")
        let recipient = AppUser(id: recipientResp.id, firstName: recipientResp.firstName, username: recipientResp.username, phone: "")

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
        receivedShares = []
        sentShares = []
    }

    private static let widgetAppGroup = WidgetSharedConstants.appGroup

    /// Home screen widget shows the latest song **sent to you**, not songs
    /// you sent. Bursts of updates (e.g. three back-to-back received-shares
    /// listener events) coalesce into a single `WidgetCenter` reload via a
    /// 250ms debounce, which keeps widget refreshes cheap and avoids the
    /// "reload spam" pattern WidgetKit penalizes with throttling.
    private func syncWidgetWithLatestReceivedShare() {
        widgetReloadTask?.cancel()
        widgetReloadTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self else { return }
            await MainActor.run { self.performWidgetSync() }
        }
    }

    private func performWidgetSync() {
        let defaults = UserDefaults(suiteName: Self.widgetAppGroup)
        guard let latest = receivedShares.max(by: { $0.timestamp < $1.timestamp }) else {
            Self.clearWidgetUserDefaults(defaults)
            WidgetCenter.shared.reloadAllTimelines()
            return
        }
        defaults?.set(latest.song.title, forKey: WidgetSharedConstants.Key.songTitle)
        defaults?.set(latest.song.artist, forKey: WidgetSharedConstants.Key.songArtist)
        defaults?.set(latest.sender.firstName, forKey: WidgetSharedConstants.Key.senderFirstName)
        if let note = latest.note, !note.isEmpty {
            defaults?.set(note, forKey: WidgetSharedConstants.Key.note)
        } else {
            defaults?.removeObject(forKey: WidgetSharedConstants.Key.note)
        }
        defaults?.set(latest.id, forKey: WidgetSharedConstants.Key.shareId)

        Task.detached {
            await Self.downloadWidgetAlbumArt(urlString: latest.song.albumArtURL)
        }
    }

    private static func downloadWidgetAlbumArt(urlString: String) async {
        guard let imageFile = WidgetSharedConstants.albumArtFileURL() else { return }

        guard let url = URL(string: urlString), !urlString.isEmpty else {
            try? FileManager.default.removeItem(at: imageFile)
            await MainActor.run { WidgetCenter.shared.reloadAllTimelines() }
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            try data.write(to: imageFile, options: .atomic)
        } catch {
            print("Widget album art download failed: \(error.localizedDescription)")
        }
        await MainActor.run { WidgetCenter.shared.reloadAllTimelines() }
    }

    private func clearWidgetSharedState() {
        let defaults = UserDefaults(suiteName: Self.widgetAppGroup)
        Self.clearWidgetUserDefaults(defaults)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func clearWidgetUserDefaults(_ defaults: UserDefaults?) {
        WidgetSharedConstants.allKeys.forEach { defaults?.removeObject(forKey: $0) }
        if let imageFile = WidgetSharedConstants.albumArtFileURL() {
            try? FileManager.default.removeItem(at: imageFile)
        }
    }
}
