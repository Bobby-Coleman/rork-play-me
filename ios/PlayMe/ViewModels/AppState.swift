import SwiftUI
import UIKit
import UserNotifications
import WidgetKit
import FirebaseFirestore
import MusicKit

/// Draft for the create-mixtape sheet. Owned by `AppState` so accidental
/// sheet dismissal (picker presentation, swipe-down, app background) does
/// not discard the user's title, description, or cropped cover image.
@MainActor
struct CreateMixtapeDraft {
    var name: String = ""
    var details: String = ""
    var coverImage: UIImage?

    mutating func clear() {
        name = ""
        details = ""
        coverImage = nil
    }
}

@Observable
@MainActor
class AppState {
    private let shareFanOutBatchSize = 8
    private let foregroundRefreshMinInterval: TimeInterval = 45
    private var lastSuccessfulShareRefreshAt: Date?
    private var isRefreshSharesInFlight = false

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
                if let avatarURL = user.avatarURL, !avatarURL.isEmpty {
                    UserDefaults.standard.set(avatarURL, forKey: "currentUserAvatarURL")
                } else {
                    UserDefaults.standard.removeObject(forKey: "currentUserAvatarURL")
                }
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
    /// Pending outgoing friend requests with enough profile data to show as
    /// send recipients before the request is accepted.
    var outgoingRequests: [AppUser] = []
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
    /// A music link shared into Riff from another app (Spotify / Apple Music)
    /// via the RiffShare Share Extension, awaiting resolution + send. Set by
    /// `ContentView`'s `playme://share-song` handler (and its foreground
    /// App-Group fallback); `ContentView` observes it, resolves the link to a
    /// `Song`, presents the send sheet, and clears it back to nil. Persists
    /// across an onboarding gate so a logged-out tap still sends once the user
    /// reaches the main app.
    var pendingExternalShareURL: String? = nil
    /// Firestore listener for incoming friend requests. Retained so we can
    /// detach on logout and reattach on sign-in.
    private var incomingRequestsListener: ListenerRegistration?
    /// Firestore listener for pending outgoing friend requests.
    private var outgoingRequestsListener: ListenerRegistration?
    /// Firestore listener for the current user's received shares. Drives
    /// real-time home-feed updates; detached on logout.
    private var receivedSharesListener: ListenerRegistration?
    /// Firestore listener for sent shares. Keeps sender-side listener rows
    /// fresh when recipients play or open a song.
    private var sentSharesListener: ListenerRegistration?
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
    /// Firestore listener for the current user's friends collection. Keeps
    /// the Friends screen live when requests are accepted or friends removed.
    private var friendsListener: ListenerRegistration?
    /// Firestore listener for the current user's global send stats
    /// (unique songs sent + send-day streak) shown in the Friends header.
    private var userStatsListener: ListenerRegistration?
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
    /// Global all-time count of UNIQUE songs this user has sent (one song
    /// sent to 10 friends counts as 1). Server-maintained on `users/{uid}`
    /// via a Cloud Function; hydrated on `loadData()` and kept fresh by a
    /// snapshot listener on the user doc.
    var uniqueSongsSentCount: Int = 0
    /// Global consecutive-day send streak (sent at least one song on a local
    /// calendar day). Server-maintained; `sendDayStreakLastDay` is the
    /// `yyyy-MM-dd` of the last send that advanced it.
    var sendDayStreakCount: Int = 0
    var sendDayStreakLastDay: String? = nil
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
    /// Last-observed MusicKit authorization status. Reads are non-prompting;
    /// the permission sheet is only requested from Apple Music onboarding.
    var musicAuthStatus: MusicAuthorization.Status = MusicAuthorization.currentStatus
    var createMixtapeDraft = CreateMixtapeDraft()

    /// Convenience for personalization-specific views that may need to surface
    /// a Settings deep-link after the user has denied Apple Music access.
    var isMusicSearchDenied: Bool { musicAuthStatus == .denied }
    var receivedShares: [SongShare] = []
    var sentShares: [SongShare] = []

    /// Full (uncapped) sent-share history backing the Songs calendar. Loaded
    /// lazily the first time the calendar appears via `loadCalendarHistory`,
    /// separate from the 50-capped `sentShares` feed window so cold launch
    /// stays cheap.
    var calendarSentShares: [SongShare] = []
    /// Full (uncapped) received-share history backing the per-friend calendar
    /// scope and the bidirectional "top person" count.
    var calendarReceivedShares: [SongShare] = []
    /// True once a calendar history load has completed at least once.
    var didLoadCalendarHistory: Bool = false
    /// True while a calendar history load is in flight (drives a spinner).
    var isLoadingCalendarHistory: Bool = false

    var discoveryFeedItems: [DiscoveryFeedItem] {
        let receivedItems = receivedShares.map(DiscoveryFeedItem.received)
        let sentItems = Dictionary(grouping: sentShares, by: { $0.song.id })
            .compactMap { _, shares -> DiscoveryFeedItem? in
                guard let latest = shares.max(by: { $0.timestamp < $1.timestamp }) else { return nil }
                let sortedShares = shares.sorted {
                    if $0.timestamp == $1.timestamp {
                        return $0.id < $1.id
                    }
                    return $0.timestamp > $1.timestamp
                }
                return .sent(SentSongHistoryItem(song: latest.song, shares: sortedShares))
            }

        return (receivedItems + sentItems).sorted {
            if $0.timestamp == $1.timestamp {
                return $0.id < $1.id
            }
            return $0.timestamp > $1.timestamp
        }
    }
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
    /// Song-level likes — the source of truth for the heart on every song
    /// card and for the synthetic Liked mixtape. A song can be liked from
    /// anywhere (search, feed, a chat message), not just from a share you
    /// received. Persisted to Firestore (`users/{uid}/likedSongs`) and
    /// mirrored to UserDefaults for instant cold-start state.
    var likedSongIds: Set<String> = [] {
        didSet {
            UserDefaults.standard.set(Array(likedSongIds), forKey: "likedSongIds")
        }
    }
    /// Resolved liked songs, newest-first, used to build the Liked mixtape.
    var likedSongs: [Song] = []
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

    /// Real PlayMe accounts with pending outgoing requests, suitable for every
    /// send selector. This intentionally lives in AppState so artist pages,
    /// search sheets, feed cards, and onboarding all share the same recipient
    /// source and dedupe rules.
    func pendingSendRecipients(including extraUsers: [AppUser] = []) -> [AppUser] {
        // Pending (not-yet-accepted) recipients are only offered during
        // onboarding's first-song step. Once onboarded, songs may only be
        // sent to accepted friends, so we never surface pending people here.
        // This prevents abuse of sends to users who never accepted a request.
        guard !isOnboarded else { return [] }
        let friendIds = Set(friends.map(\.id))
        var seen = Set<String>()
        return (outgoingRequests + onboardingRequestedUsers + extraUsers).filter { user in
            !friendIds.contains(user.id)
                && !blockedUserIds.contains(user.id)
                && seen.insert(user.id).inserted
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
    private var inFlightDirectSendKeys = Set<String>()
    private var pendingDirectShares: [String: SongShare] = [:]

    // MARK: - Onboarding-only state (cleared after onboarding completes)
    /// Contacts the user texted invites to during OnboardingInviteView.
    /// Surfaced in the SendFirstSongView friend carousel so first songs can be
    /// queued for them via `sendSongToPendingContact`.
    var invitedContacts: [SimpleContact] = []
    /// Existing PlayMe users the new user added by username during
    /// onboarding. A sent friend request is not an accepted friendship yet,
    /// so these users will not necessarily appear in `friends` before the
    /// first-song step. Keep the full profiles here so they remain selectable
    /// as first-song recipients.
    var onboardingRequestedUsers: [AppUser] = []
    /// One-shot signal that the onboarding first-song send completed. Set by
    /// `FriendSelectorView.commitSend` for any song-send path while the user is
    /// still onboarding (direct search, artist profile, or album detail), and
    /// observed by `SendFirstSongRiffView` to advance the step uniformly
    /// regardless of how deep the send originated. Reset when the send sheet
    /// reopens.
    var onboardingFirstSongShared: Bool = false
    /// Invite code the user submitted on the gate screen. Validated via the
    /// `validateInviteCode` Cloud Function before SMS verification, then
    /// redeemed once the profile is created. Cleared on signOut.
    var inviteCode: String = ""
    /// Last invite-code validation error message surfaced in the gate UI.
    var inviteCodeError: String? = nil
    /// Resolved kind of the validated code (personal | creator | admin).
    /// Drives kind-specific copy on the gate confirmation and the
    /// post-redeem messaging (e.g. "you'll be friends with X" vs
    /// "joined via Bobby's launch code"). Nil until validation succeeds.
    var inviteCodeKind: FirebaseService.InviteCodeKind? = nil
    /// User who created the redeemed invite code. Invite codes are gateways,
    /// not automatic friendships, so this user is pinned as a suggestion.
    var inviteSuggestedUser: AppUser? = nil
    /// Contacts already signed up for Riff, matched server-side by private
    /// profile phone numbers and rendered as onboarding suggestions.
    var contactSuggestedUsers: [AppUser] = []
    /// True while a `matchContacts` lookup is in flight, so the suggestions
    /// UI can show a spinner instead of looking empty/broken during the call.
    var isLoadingContactSuggestions = false
    /// Identity of the contact set the last successful (or in-flight) match
    /// was started for. Lets us skip redundant lookups when the same contacts
    /// are passed again (e.g. PickFriends `.onChange` re-firing).
    private var lastContactSuggestionKey: Int?
    /// Genres the user picked on the taste screen. Persisted to
    /// `users/{uid}.tasteGenres` once registration succeeds.
    var tasteGenres: [String] = []
    /// Artists the user picked on the taste screen. Persisted to
    /// `users/{uid}.tasteArtists` once registration succeeds.
    var tasteArtists: [String] = []

    /// User-selected onboarding theme. Drives onboarding screens, the
    /// app-wide background color, and is persisted across launches under
    /// `appTheme` in UserDefaults. Stored property (rather than computed)
    /// so SwiftUI's `@Observable` registrar tracks reads and re-renders
    /// dependent views when the theme picker swaps it out.
    var appTheme: RiffTheme = RiffTheme.byId(
        UserDefaults.standard.string(forKey: "appTheme") ?? RiffTheme.black.id
    ) {
        didSet { UserDefaults.standard.set(appTheme.id, forKey: "appTheme") }
    }

    var likedShares: [SongShare] {
        (receivedShares + sentShares).filter { likedShareIds.contains($0.id) }
            .sorted { $0.timestamp > $1.timestamp }
    }

    init() {
        loadSavedUser()
        likedShareIds = Set(UserDefaults.standard.stringArray(forKey: "likedShareIds") ?? [])
        likedSongIds = Set(UserDefaults.standard.stringArray(forKey: "likedSongIds") ?? [])
        // Wire MixtapeStore ↔ SaveService now (before any async load), and
        // give the store a closure for `likedShares` so the synthetic
        // Liked mixtape stays reactive to per-share like toggles without
        // a separate observer hookup.
        mixtapeStore.saveService = saveService
        mixtapeStore.likedSharesProvider = { [weak self] in self?.likedShares ?? [] }
        mixtapeStore.likedSongsProvider = { [weak self] in self?.likedSongs ?? [] }
        // Fire-and-forget: cache MusicKit's current status without prompting.
        Task { [weak self] in
            let status = await AppleMusicSearchService.shared.refreshCachedAuthorizationStatus()
            await MainActor.run { self?.musicAuthStatus = status }
        }
    }

    private func loadSavedUser() {
        if let id = UserDefaults.standard.string(forKey: "currentUserId"),
           let firstName = UserDefaults.standard.string(forKey: "currentUserFirstName"),
           let username = UserDefaults.standard.string(forKey: "currentUserUsername") {
            let lastName = UserDefaults.standard.string(forKey: "currentUserLastName") ?? ""
            let phone = UserDefaults.standard.string(forKey: "currentUserPhone") ?? ""
            let avatarURL = UserDefaults.standard.string(forKey: "currentUserAvatarURL")
            currentUser = AppUser(id: id, firstName: firstName, lastName: lastName, username: username, phone: phone, avatarURL: avatarURL)
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

    /// Validates an invite code via the server callable. Stores a
    /// human-readable reason on `inviteCodeError` if validation failed
    /// so the gate UI can surface it inline. Also stashes the resolved
    /// `kind` so the gate can show kind-specific confirmation copy
    /// (e.g. "Joined via Bobby's launch code").
    func validateInviteCode(_ code: String) async -> Bool {
        inviteCodeError = nil
        let result = await FirebaseService.shared.validateInviteCode(code)
        if result.valid {
            inviteCodeKind = result.kind
            return true
        }
        inviteCodeKind = nil
        inviteCodeError = Self.message(for: result.reason)
        return false
    }

    private static func message(for reason: FirebaseService.InviteCodeReason?) -> String {
        switch reason {
        case .notFound:        return "That code isn't valid."
        case .disabled:        return "That code has been deactivated."
        case .expired:         return "That code has expired."
        case .exhausted:       return "That code is already used."
        case .missingCode:     return "Enter your invite code."
        case .rateLimited:     return "Too many attempts. Please wait a few minutes and try again."
        case .network:         return "We couldn't reach the server. Check your connection."
        case .methodNotAllowed,
             .serverError,
             .none:            return "Something went wrong. Try again."
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
                              username: profile.username, phone: profile.phone,
                              avatarURL: profile.avatarURL)

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
            phone: phoneNumber,
            tasteGenres: tasteGenres,
            tasteArtists: tasteArtists
        )

        guard claimed else {
            registrationError = "Username is taken. Please choose another."
            return false
        }

        isBackendAvailable = true
        currentUser = AppUser(id: uid, firstName: firstName, lastName: lastName, username: username.lowercased(), phone: phoneNumber)

        // Redeem the invite code now that the profile exists. Server-side
        // bumps the use count and stamps attribution, but does not create
        // friendships. The inviter comes back as a suggested person to add.
        if !inviteCode.isEmpty {
            let result = await firebase.redeemInviteCode(inviteCode)
            if let suggestedInviter = result.suggestedInviter {
                rememberInviteSuggestedUser(suggestedInviter)
            }
        }
        DeepLinkService.shared.clearPendingInviteCode()

        // The `onUserProfileCreated` Cloud Function will fire automatically from
        // the users/{uid} doc creation in `claimUsernameAndCreateProfile`. We
        // also write a claimRequest as belt-and-suspenders in case the trigger
        // missed (e.g. if the profile doc already existed from a prior signup).
        // `force: true` — registration handoff always re-claims even if a
        // previous session already ran one, because the user's phone just
        // became eligible.
        await firebase.requestPendingSharesClaim(force: true)

        return true
    }

    @discardableResult
    func updateProfilePhoto(image: UIImage?, progress: ((Double) -> Void)? = nil) async -> Bool {
        guard let user = currentUser else { return false }
        registrationError = nil

        let avatarURL: String?
        if let image {
            do {
                avatarURL = try await ProfilePhotoUploader.shared.uploadPickedImage(image, progress: progress)
            } catch {
                registrationError = error.localizedDescription
                return false
            }
        } else {
            avatarURL = nil
        }

        guard await FirebaseService.shared.updateCurrentUserAvatarURL(avatarURL) else {
            registrationError = "Could not save your profile picture. Please try again."
            return false
        }

        currentUser = AppUser(
            id: user.id,
            firstName: user.firstName,
            lastName: user.lastName,
            username: user.username,
            phone: user.phone,
            avatarURL: avatarURL
        )
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
            currentUser = AppUser(id: uid, firstName: oldUser.firstName, lastName: oldUser.lastName, username: oldUser.username, phone: oldUser.phone, avatarURL: oldUser.avatarURL)
        }

        if let profile = await firebase.loadUserProfile() {
            let uid = firebase.firebaseUID ?? currentUser!.id
            currentUser = AppUser(
                id: uid,
                firstName: profile.firstName,
                lastName: profile.lastName,
                username: profile.username,
                phone: profile.phone,
                avatarURL: profile.avatarURL
            )
        }

        let serverLikes = await firebase.loadLikedShareIds()
        likedShareIds = serverLikes

        let serverLikedSongs = await firebase.loadLikedSongs()
        likedSongs = serverLikedSongs
        likedSongIds = Set(serverLikedSongs.map(\.id))

        async let friendsFetch = firebase.loadFriends()
        async let blockedFetch = firebase.loadBlockedUserIds()
        let (serverFriends, blocked) = await (friendsFetch, blockedFetch)
        blockedUserIds = blocked
        friends = serverFriends.filter { !blockedUserIds.contains($0.id) }

        await refreshFriendRequests()
        startIncomingRequestsListener()
        startOutgoingRequestsListener()
        startReceivedSharesListener()
        startConversationsListener()
        startFriendsListener()
        startUserStatsListener()
        // Load the server-authoritative friend cap up front so the "X of Y
        // friends" label and the at-cap accept gate are correct on cold
        // launch (previously nil until the first accept/remove).
        Task { await refreshFriendCap() }

        async let notificationsFetch = firebase.loadNotificationsEnabled()
        async let receivedFetch = firebase.loadReceivedShares()
        async let conversationsFetch: () = loadConversations()
        let (notifications, serverReceived, _) = await (notificationsFetch, receivedFetch, conversationsFetch)
        notificationsEnabled = notifications
        receivedShares = serverReceived.filter { !blockedUserIds.contains($0.sender.id) }

        syncWidgetWithLatestReceivedShare()
        isLoading = false

        Task { await loadDeferredLaunchData() }
    }

    private func loadDeferredLaunchData() async {
        guard currentUser != nil else { return }

        let firebase = FirebaseService.shared
        if !firebase.isSignedIn { return }

        sendStats = await firebase.loadSendStats()

        startSentSharesListener()
        startReceivedMixtapeSharesListener()
        startReceivedAlbumSharesListener()

        let serverSent = await firebase.loadSentShares()
        sentShares = serverSent

        // One-time migration: fold any legacy per-share likes that predate
        // the song-level store into `likedSongs` (and persist them) so
        // existing users keep their Liked list and a consistent heart state.
        migrateLegacyLikesIntoSongStore()

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
        // parallel. These are tab-specific and should not block first paint.
        async let saveIndex: () = saveService.loadFromFirestore()
        async let mixtapeFetch: () = mixtapeStore.loadFromFirestore()
        _ = await (saveIndex, mixtapeFetch)

        // Late-arriving queued shares (friend queued a song AFTER this user
        // signed up) need a retry. The claimRequest doc triggers the server
        // fan-out. Keep it after first paint so it never blocks launch.
        await firebase.requestPendingSharesClaim()
    }

    func sendSong(_ song: Song, to friend: AppUser, note: String?) async {
        guard let user = currentUser else { return }

        let sendKey = "\(user.id)|\(friend.id)|\(song.id)"
        guard !inFlightDirectSendKeys.contains(sendKey) else { return }
        inFlightDirectSendKeys.insert(sendKey)
        defer { inFlightDirectSendKeys.remove(sendKey) }

        let enrichedSong = await enrichSongWithSpotifyURI(song)
        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedNote = (trimmedNote?.isEmpty ?? true) ? nil : trimmedNote

        let firebase = FirebaseService.shared
        let shareId = firebase.newShareDocumentId()
        let share = SongShare(
            id: shareId,
            song: enrichedSong,
            sender: AppUser(id: user.id, firstName: user.firstName, lastName: user.lastName, username: user.username, phone: user.phone, avatarURL: user.avatarURL),
            recipient: friend,
            note: cleanedNote
        )
        pendingDirectShares[share.id] = share
        sentShares.removeAll { $0.id == share.id }
        sentShares.insert(share, at: 0)

        guard await firebase.saveShare(share) != nil else {
            pendingDirectShares.removeValue(forKey: share.id)
            sentShares.removeAll { $0.id == share.id }
            queuedContactError = "We couldn't send that song. Try again."
            clearQueuedContactFeedbackSoon()
            return
        }

        // Bump the per-friend send counter: optimistically locally (so the
        // chip row reorders immediately) and durably in Firestore.
        let previousCount = sendStats[friend.id]?.count ?? 0
        sendStats[friend.id] = SendStat(count: previousCount + 1, lastSentAt: Date())
        Task { await FirebaseService.shared.incrementSendStat(friendUid: friend.id) }

        if let conv = await firebase.getOrCreateConversation(with: friend.id, friendName: friend.firstName) {
            let messageText = cleanedNote ?? ""
            // A song send already surfaces via its own "New Song" push and the
            // feed, so it must not also light up the Messages unread badge. The
            // message still posts to the thread (history + inbox bump), just
            // silently. Text replies (sendMessage elsewhere) still badge.
            await firebase.sendMessage(conversationId: conv.id, text: messageText, song: enrichedSong, mutationId: "share-\(shareId)", incrementUnread: false)
            // The `listenConversations` listener pushes the inbox update; no
            // manual refetch needed.
        }

        showSentToast = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            showSentToast = false
        }
    }

    @discardableResult
    func queueSongForPendingFriend(_ song: Song, to user: AppUser, note: String?) async -> Bool {
        guard let sender = currentUser else { return false }

        let enrichedSong = await enrichSongWithSpotifyURI(song)
        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedNote = (trimmedNote?.isEmpty ?? true) ? nil : trimmedNote
        let share = SongShare(
            song: enrichedSong,
            sender: AppUser(id: sender.id, firstName: sender.firstName, lastName: sender.lastName, username: sender.username, phone: sender.phone, avatarURL: sender.avatarURL),
            recipient: user,
            note: cleanedNote
        )

        guard await FirebaseService.shared.savePendingFriendShare(share) != nil else {
            queuedContactError = "We couldn't queue that song. Try again."
            clearQueuedContactFeedbackSoon()
            return false
        }

        let name = user.firstName.isEmpty ? "@\(user.username)" : user.firstName
        queuedContactToast = "We'll deliver to \(name) when they accept your request."
        clearQueuedContactFeedbackSoon()
        return true
    }

    func hasLocallySentSong(_ song: Song, to friend: AppUser) -> Bool {
        sentShares.contains { share in
            share.song.id == song.id && share.recipient.id == friend.id
        }
    }

    func duplicateSongSendRecipients(for song: Song, friends: [AppUser]) async -> [AppUser] {
        var duplicates: [AppUser] = []

        for friend in friends {
            if hasLocallySentSong(song, to: friend) {
                duplicates.append(friend)
                continue
            }

            if await FirebaseService.shared.hasSentSong(songId: song.id, to: friend.id) {
                duplicates.append(friend)
            }
        }

        return duplicates
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
            username: user.username, phone: user.phone, avatarURL: user.avatarURL
        )
        var locallyInserted: [MixtapeShare] = []
        for friend in friends {
            let shareId = FirebaseService.shared.mixtapeShareDocumentId(senderId: user.id, recipientId: friend.id, mixtapeId: snapshot.id)
            let share = MixtapeShare(
                id: shareId,
                mixtape: snapshot,
                sender: me,
                recipient: friend,
                note: cleanedNote
            )
            locallyInserted.append(share)
        }
        let localIds = Set(locallyInserted.map(\.id))
        sentMixtapeShares.removeAll { localIds.contains($0.id) }
        sentMixtapeShares.insert(contentsOf: locallyInserted, at: 0)
        showSentToast = true

        var successfulRecipientIds = Set<String>()
        for start in stride(from: 0, to: locallyInserted.count, by: shareFanOutBatchSize) {
            let end = min(start + shareFanOutBatchSize, locallyInserted.count)
            let batch = Array(locallyInserted[start..<end])
            let batchResults = await withTaskGroup(of: (String, Bool).self, returning: [(String, Bool)].self) { group in
                let firebase = FirebaseService.shared
                for share in batch {
                    group.addTask {
                        let savedId = await firebase.saveMixtapeShare(share)
                        return (share.recipient.id, savedId != nil)
                    }
                }

                var results: [(String, Bool)] = []
                for await result in group {
                    results.append(result)
                }
                return results
            }
            for (recipientId, didSave) in batchResults where didSave {
                successfulRecipientIds.insert(recipientId)
            }
        }

        if successfulRecipientIds.count < locallyInserted.count {
            let failedIds = Set(friends.map(\.id)).subtracting(successfulRecipientIds)
            sentMixtapeShares.removeAll { failedIds.contains($0.recipient.id) && $0.mixtape.id == snapshot.id }
            queuedContactError = "Some mixtape sends failed. Please try again."
            clearQueuedContactFeedbackSoon()
        }

        for friend in friends where successfulRecipientIds.contains(friend.id) {
            let prev = sendStats[friend.id]?.count ?? 0
            sendStats[friend.id] = SendStat(count: prev + 1, lastSentAt: Date())
            Task {
                await FirebaseService.shared.incrementSendStat(friendUid: friend.id)
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
            username: user.username, phone: user.phone, avatarURL: user.avatarURL
        )
        var locallyInserted: [AlbumShare] = []
        for friend in friends {
            let shareId = FirebaseService.shared.albumShareDocumentId(senderId: user.id, recipientId: friend.id, albumId: album.id)
            let share = AlbumShare(
                id: shareId,
                album: album,
                songs: tracks,
                sender: me,
                recipient: friend,
                note: cleanedNote
            )
            locallyInserted.append(share)
        }
        let localIds = Set(locallyInserted.map(\.id))
        sentAlbumShares.removeAll { localIds.contains($0.id) }
        sentAlbumShares.insert(contentsOf: locallyInserted, at: 0)
        showSentToast = true

        var successfulRecipientIds = Set<String>()
        for start in stride(from: 0, to: locallyInserted.count, by: shareFanOutBatchSize) {
            let end = min(start + shareFanOutBatchSize, locallyInserted.count)
            let batch = Array(locallyInserted[start..<end])
            let batchResults = await withTaskGroup(of: (String, Bool).self, returning: [(String, Bool)].self) { group in
                let firebase = FirebaseService.shared
                for share in batch {
                    group.addTask {
                        let savedId = await firebase.saveAlbumShare(share)
                        return (share.recipient.id, savedId != nil)
                    }
                }

                var results: [(String, Bool)] = []
                for await result in group {
                    results.append(result)
                }
                return results
            }
            for (recipientId, didSave) in batchResults where didSave {
                successfulRecipientIds.insert(recipientId)
            }
        }

        if successfulRecipientIds.count < locallyInserted.count {
            let failedIds = Set(friends.map(\.id)).subtracting(successfulRecipientIds)
            sentAlbumShares.removeAll { failedIds.contains($0.recipient.id) && $0.album.id == album.id }
            queuedContactError = "Some album sends failed. Please try again."
            clearQueuedContactFeedbackSoon()
        }

        for friend in friends where successfulRecipientIds.contains(friend.id) {
            let prev = sendStats[friend.id]?.count ?? 0
            sendStats[friend.id] = SendStat(count: prev + 1, lastSentAt: Date())
            Task {
                await FirebaseService.shared.incrementSendStat(friendUid: friend.id)
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
            #if DEBUG
            print("AppState: event=pending_share_queue_failed reason=invalid_phone raw=\(contact.phoneNumber)")
            #endif
            queuedContactError = "We couldn't read \(contact.firstName)'s phone number."
            clearQueuedContactFeedbackSoon()
            return false
        }
        #if DEBUG
        print("AppState: event=pending_share_queue_attempt contact=\(contact.fullName) raw=\(contact.phoneNumber) normalized=\(e164)")
        #else
        print("AppState: event=pending_share_queue_attempt")
        #endif

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

    /// Snapchat-style active streak: the stored streak counts only if the
    /// last send was today or yesterday (local time); otherwise a day was
    /// missed and the displayed streak is 0 until the next send.
    var effectiveSendDayStreak: Int {
        guard sendDayStreakCount > 0,
              let last = sendDayStreakLastDay, !last.isEmpty else { return 0 }
        let today = Self.localDayString(0)
        let yesterday = Self.localDayString(-1)
        return (last == today || last == yesterday) ? sendDayStreakCount : 0
    }

    static func localDayString(_ dayOffset: Int) -> String {
        let calendar = Calendar.current
        let date = calendar.date(byAdding: .day, value: dayOffset, to: Date()) ?? Date()
        return localDayString(for: date)
    }

    /// `yyyy-MM-dd` for an arbitrary date in the device timezone. Used to
    /// bucket shares into calendar days.
    static func localDayString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    // MARK: - Songs Calendar

    /// Lazily load the full sent + received share history that backs the
    /// Songs calendar. Cheap to call repeatedly: skips the network if it
    /// already loaded (unless `force`) and coalesces concurrent calls.
    func loadCalendarHistory(force: Bool = false) async {
        if isLoadingCalendarHistory { return }
        if didLoadCalendarHistory && !force { return }
        isLoadingCalendarHistory = true
        let firebase = FirebaseService.shared
        async let sent = firebase.loadAllSentShares()
        async let received = firebase.loadAllReceivedShares()
        let (sentResult, receivedResult) = await (sent, received)
        // Preserve the no-clobber behavior used elsewhere: an empty fetch
        // (e.g. transient failure) shouldn't wipe a populated calendar.
        if !sentResult.isEmpty || !didLoadCalendarHistory {
            calendarSentShares = sentResult
        }
        let filteredReceived = receivedResult.filter { !blockedUserIds.contains($0.sender.id) }
        if !filteredReceived.isEmpty || !didLoadCalendarHistory {
            calendarReceivedShares = filteredReceived
        }
        didLoadCalendarHistory = true
        isLoadingCalendarHistory = false
    }

    /// Songs bucketed by local calendar day for the calendar, deduped by
    /// song within each day — the same song sent to N friends shows up as
    /// one `DaySongGroup` carrying all N shares (so the UI can list the
    /// recipients) instead of N near-identical entries.
    /// - `friendId == nil`: every song YOU sent (to anyone), by day sent.
    /// - `friendId != nil`: every song that friend sent YOU, by day.
    func calendarSongsByDay(friendId: String?) -> [String: [DaySongGroup]] {
        let shares: [SongShare]
        if let friendId {
            shares = calendarReceivedShares.filter { $0.sender.id == friendId }
        } else {
            shares = calendarSentShares
        }
        var byDay: [String: [SongShare]] = [:]
        for share in shares {
            byDay[Self.localDayString(for: share.timestamp), default: []].append(share)
        }
        // Newest-first within each group and across a day's groups so the
        // stacked cell shows the most recent album art on top.
        var groupsByDay: [String: [DaySongGroup]] = [:]
        for (day, dayShares) in byDay {
            groupsByDay[day] = Dictionary(grouping: dayShares, by: { $0.song.id })
                .values
                .map { sameSong -> DaySongGroup in
                    let sorted = sameSong.sorted { $0.timestamp > $1.timestamp }
                    return DaySongGroup(song: sorted[0].song, shares: sorted)
                }
                .sorted { $0.timestamp > $1.timestamp }
        }
        return groupsByDay
    }

    /// Date the current user sent their very first song (across all of
    /// history), or `nil` if they've never sent one.
    var firstSongSentDate: Date? {
        calendarSentShares.map(\.timestamp).min()
    }

    /// The friend the current user has exchanged the most songs with
    /// (sent to them + received from them), all-time. Returns the friend
    /// and the combined total.
    func topPersonBetween() -> (friend: AppUser, total: Int)? {
        var counts: [String: Int] = [:]
        var users: [String: AppUser] = [:]
        for share in calendarSentShares {
            counts[share.recipient.id, default: 0] += 1
            users[share.recipient.id] = share.recipient
        }
        for share in calendarReceivedShares {
            counts[share.sender.id, default: 0] += 1
            users[share.sender.id] = share.sender
        }
        // Prefer richer profile data from the live friends list when present.
        for friend in friends { users[friend.id] = friend }
        guard let best = counts.max(by: { lhs, rhs in
            if lhs.value == rhs.value { return lhs.key > rhs.key }
            return lhs.value < rhs.value
        }), let user = users[best.key], best.value > 0 else { return nil }
        return (user, best.value)
    }

    func sendMessage(
        conversationId: String,
        text: String,
        song: Song? = nil,
        replyTo: ChatMessage? = nil,
        mutationId: String = UUID().uuidString
    ) async {
        // No post-send `loadConversations()`: the `listenConversations`
        // snapshot listener already pushes the inbox update (last message,
        // ordering, unread) in real time, and the chat thread shows the
        // message optimistically. A manual refetch here only added latency
        // and could briefly race the listener.
        await FirebaseService.shared.sendMessage(
            conversationId: conversationId,
            text: text,
            song: song,
            replyTo: replyTo,
            mutationId: mutationId
        )
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
        // Search no longer dictates `musicAuthStatus` — we hit the
        // developer-only Apple Music HTTP API, so search succeeds
        // regardless of user MusicKit authorization. The personalization
        // status is mirrored from `MusicServiceView` and the launch-time
        // `refreshCachedAuthorizationStatus` call instead.
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
        friends = serverFriends.filter { !blockedUserIds.contains($0.id) }
        // Friend cap is derived from the public user doc which is
        // updated by the `onFriendCreated` / `onFriendDeleted` Cloud
        // Function triggers. Refresh alongside the friends list so the
        // "X of Y friends" hint stays in sync without an extra round
        // trip for every screen that surfaces it.
        await refreshFriendCap()
    }

    // MARK: - Friend Requests

    /// One-shot refresh of friend-request state. Incoming requests drive the
    /// Add Friends badge; outgoing requests drive "Requested" buttons and
    /// pending send-recipient chips.
    func refreshFriendRequests() async {
        let firebase = FirebaseService.shared
        guard firebase.isSignedIn else { return }
        async let incomingLoad = firebase.loadIncomingRequests()
        async let outgoingLoad = firebase.loadOutgoingRequests()
        let incoming = await incomingLoad
        let outgoing = await outgoingLoad
        incomingRequests = incoming.filter { !blockedUserIds.contains($0.id) }
        outgoingRequests = outgoing.filter { !blockedUserIds.contains($0.id) }
        outgoingRequestUIDs = Set(outgoingRequests.map(\.id))
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

    private func startOutgoingRequestsListener() {
        outgoingRequestsListener?.remove()
        outgoingRequestsListener = FirebaseService.shared.listenOutgoingRequests { [weak self] requests in
            Task { @MainActor in
                guard let self else { return }
                self.outgoingRequests = requests.filter { !self.blockedUserIds.contains($0.id) }
                self.outgoingRequestUIDs = Set(self.outgoingRequests.map(\.id))
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

    private func startSentSharesListener() {
        sentSharesListener?.remove()
        sentSharesListener = FirebaseService.shared.listenSentShares { [weak self] shares in
            Task { @MainActor in
                guard let self else { return }
                self.applySentSharesSnapshot(shares)
            }
        }
    }

    private func applySentSharesSnapshot(_ shares: [SongShare]) {
        let persistedIds = Set(shares.map(\.id))
        for id in Array(pendingDirectShares.keys) where persistedIds.contains(id) {
            pendingDirectShares.removeValue(forKey: id)
        }

        var byId = Dictionary(uniqueKeysWithValues: shares.map { ($0.id, $0) })
        for (id, share) in pendingDirectShares where byId[id] == nil {
            byId[id] = share
        }
        sentShares = byId.values.sorted { $0.timestamp > $1.timestamp }
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
    /// Attach (or reattach) the snapshot listener that keeps the friends
    /// list in sync with Firestore in real time. Idempotent.
    private func startFriendsListener() {
        friendsListener?.remove()
        friendsListener = FirebaseService.shared.listenFriends { [weak self] friends in
            Task { @MainActor in
                guard let self else { return }
                self.friends = friends.filter { !self.blockedUserIds.contains($0.id) }
            }
        }
    }

    /// Attach (or reattach) the snapshot listener for the user's global
    /// send stats so the Friends header pills update in real time as the
    /// onNewShare Cloud Function increments them. Idempotent.
    private func startUserStatsListener() {
        userStatsListener?.remove()
        userStatsListener = FirebaseService.shared.listenUserStats { [weak self] unique, streak, lastDay in
            Task { @MainActor in
                guard let self else { return }
                self.uniqueSongsSentCount = unique
                self.sendDayStreakCount = streak
                self.sendDayStreakLastDay = lastDay
            }
        }
    }

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
        rememberOutgoingRequestUser(user)
        let ok = await FirebaseService.shared.sendFriendRequest(
            toUID: user.id,
            username: me.username,
            firstName: me.firstName,
            lastName: me.lastName,
            avatarURL: me.avatarURL,
            targetUsername: user.username,
            targetFirstName: user.firstName,
            targetLastName: user.lastName,
            targetAvatarURL: user.avatarURL
        )
        if ok {
            if !isOnboarded {
                rememberOnboardingRequestedUser(user)
            }
            let handle = user.username.isEmpty ? user.firstName : "@\(user.username)"
            friendRequestToast = "Request sent to \(handle)"
        } else {
            outgoingRequestUIDs.remove(user.id)
            outgoingRequests.removeAll { $0.id == user.id }
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
        await FirebaseService.shared.deletePendingFriendShares(toUID: user.id)
        outgoingRequestUIDs.remove(user.id)
        outgoingRequests.removeAll { $0.id == user.id }
        onboardingRequestedUsers.removeAll { $0.id == user.id }
    }

    private func rememberOutgoingRequestUser(_ user: AppUser) {
        outgoingRequests.removeAll { $0.id == user.id }
        outgoingRequests.append(user)
    }

    func rememberOnboardingRequestedUser(_ user: AppUser) {
        guard !isOnboarded else { return }
        onboardingRequestedUsers.removeAll { $0.id == user.id }
        onboardingRequestedUsers.append(user)
    }

    func rememberInviteSuggestedUser(_ user: AppUser) {
        guard !isOnboarded else { return }
        inviteSuggestedUser = user
        contactSuggestedUsers.removeAll { $0.id == user.id }
    }

    /// Matches device contacts against existing Riff users. Safe to call from
    /// several places (contact-permission prefetch, PickFriends `.task`/
    /// `.onChange`): it dedupes by contact-set identity so the expensive
    /// server lookup runs at most once per distinct set unless `force` is set.
    func refreshContactSuggestions(from contacts: [SimpleContact], force: Bool = false) async {
        guard !isOnboarded else { return }

        let key = Self.contactSuggestionKey(for: contacts)
        // Skip if the same contacts are already loaded or being loaded.
        if !force, key == lastContactSuggestionKey,
           isLoadingContactSuggestions || !contactSuggestedUsers.isEmpty {
            return
        }
        lastContactSuggestionKey = key

        isLoadingContactSuggestions = true
        let matched = await FirebaseService.shared.matchContacts(contacts)
        let excluded = Set(
            friends.map(\.id)
                + outgoingRequests.map(\.id)
                + onboardingRequestedUsers.map(\.id)
                + [currentUser?.id, inviteSuggestedUser?.id].compactMap { $0 }
        )
        contactSuggestedUsers = matched.filter { user in
            !excluded.contains(user.id) && !blockedUserIds.contains(user.id)
        }
        isLoadingContactSuggestions = false
    }

    /// Order-independent identity for a contact set, used to dedupe lookups.
    private static func contactSuggestionKey(for contacts: [SimpleContact]) -> Int {
        var hasher = Hasher()
        for id in contacts.map(\.id).sorted() {
            hasher.combine(id)
        }
        return hasher.finalize()
    }

    /// Accept an incoming friend request; refreshes `friends` so the
    /// accepted user shows up in the friends list right away. Returns
    /// the result so the calling view can surface a "you're at your
    /// friend limit" upsell when the per-user cap is hit.
    @discardableResult
    func acceptFriendRequest(_ user: AppUser) async -> FirebaseService.AcceptFriendResult {
        let result = await FirebaseService.shared.acceptFriendRequestChecked(from: user)
        switch result {
        case .success:
            incomingRequests.removeAll { $0.id == user.id }
            // Optimistically reflect the new friend immediately so the list
            // and count update without waiting for the refetch / server-side
            // friendCount increment. The friends listener + refreshFriendCap
            // reconcile the authoritative values right after.
            if !friends.contains(where: { $0.id == user.id }) {
                friends.append(user)
            }
            if let cap = friendCap {
                friendCap = FirebaseService.FriendCapStatus(count: cap.count + 1, limit: cap.limit)
            }
            await refreshFriends()
            await refreshFriendCap()
        case .atCap(let limit):
            // Surface a soft message — leave the request in the inbox
            // so the user can either decline it or remove an existing
            // friend and retry.
            friendCapMessage = "You've reached your \(limit)-friend limit. Remove a friend or upgrade to add more."
            clearFriendCapMessageSoon()
        case .failed:
            break
        }
        return result
    }

    /// Live snapshot of the current user's friend cap status. Defaults
    /// to `nil` until the first refresh lands. Used by AddFriends and
    /// the request list to gate the accept button. Tracked by the
    /// `@Observable` macro on the enclosing class — no `@Published`
    /// needed.
    var friendCap: FirebaseService.FriendCapStatus?

    /// Current user's friend limit. Sourced from the server `friendLimit`
    /// field (via `friendCap`), falling back to the default cap before the
    /// first cap refresh lands.
    var friendLimit: Int { friendCap?.limit ?? Config.DEFAULT_FRIEND_LIMIT }

    /// Live friend count for display and the cap gate. Derived from the
    /// real-time `friends` listener rather than the eventually-consistent
    /// server `friendCount` field. The server field is decremented by the
    /// `onFriendDeleted` Cloud Function asynchronously, so reading it right
    /// after a remove/add briefly returns a stale value — which previously
    /// made the counter drop and then pop back up. The local friends list
    /// reflects the change instantly and stays correct.
    var friendCountDisplay: Int { friends.count }

    /// Whether the user is at their friend limit, derived from the live
    /// friend count so it never flickers against a stale server count.
    var isAtFriendCap: Bool { friendCountDisplay >= friendLimit }

    /// User-facing toast surfaced when an accept attempt fails because
    /// of the friend cap. Auto-cleared after a few seconds.
    var friendCapMessage: String?

    private var friendCapMessageClearTask: Task<Void, Never>?

    private func clearFriendCapMessageSoon() {
        friendCapMessageClearTask?.cancel()
        friendCapMessageClearTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(5))
            self?.friendCapMessage = nil
        }
    }

    func refreshFriendCap() async {
        if let cap = await FirebaseService.shared.loadFriendCapStatus() {
            self.friendCap = cap
        }
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

    // MARK: - Song-level likes

    /// Whether the given song is in the user's Liked list. Drives the heart
    /// on every song card, regardless of where the song came from.
    func isLikedSong(_ songId: String) -> Bool {
        likedSongIds.contains(songId)
    }

    /// Likes/unlikes a song everywhere it appears. The optional `share`
    /// is the contextual share the card was opened from (a chat message,
    /// a feed row); when it's a song someone sent ME, liking also fires
    /// the per-share social signal so the sender sees my avatar + heart and
    /// gets notified (and unliking clears it).
    func toggleLikeSong(_ song: Song, share: SongShare? = nil) {
        if likedSongIds.contains(song.id) {
            likedSongIds.remove(song.id)
            likedSongs.removeAll { $0.id == song.id }
            Task { await FirebaseService.shared.removeLikedSong(songId: song.id) }
            for shareId in shareIdsForSocialSignal(songId: song.id, contextShare: share)
            where likedShareIds.contains(shareId) {
                likedShareIds.remove(shareId)
                Task { await FirebaseService.shared.removeLike(shareId: shareId) }
            }
        } else {
            likedSongIds.insert(song.id)
            likedSongs.insert(song, at: 0)
            Task { await FirebaseService.shared.saveLikedSong(song) }
            for shareId in shareIdsForSocialSignal(songId: song.id, contextShare: share)
            where !likedShareIds.contains(shareId) {
                likedShareIds.insert(shareId)
                Task { await FirebaseService.shared.saveLike(shareId: shareId) }
            }
        }
    }

    /// The set of share ids whose sender should be notified that I liked
    /// their send. Only shares where I am the recipient qualify (you don't
    /// signal a like on a song you sent). Prefers the contextual share when
    /// it is one I received; otherwise every received share of this song.
    private func shareIdsForSocialSignal(songId: String, contextShare: SongShare?) -> [String] {
        let myId = currentUser?.id
        if let share = contextShare, share.recipient.id == myId {
            return [share.id]
        }
        return receivedShares.filter { $0.song.id == songId }.map(\.id)
    }

    /// Folds legacy per-share likes into the song-level store once, so users
    /// who liked songs before song-level likes existed keep their Liked list.
    private func migrateLegacyLikesIntoSongStore() {
        guard !likedShareIds.isEmpty else { return }
        let legacy = (receivedShares + sentShares).filter { likedShareIds.contains($0.id) }
        var added: [Song] = []
        for share in legacy where !likedSongIds.contains(share.song.id) {
            likedSongIds.insert(share.song.id)
            added.append(share.song)
        }
        guard !added.isEmpty else { return }
        likedSongs.insert(contentsOf: added, at: 0)
        for song in added {
            Task { await FirebaseService.shared.saveLikedSong(song) }
        }
    }

    func logout() {
        incomingRequestsListener?.remove()
        incomingRequestsListener = nil
        outgoingRequestsListener?.remove()
        outgoingRequestsListener = nil
        receivedSharesListener?.remove()
        receivedSharesListener = nil
        sentSharesListener?.remove()
        sentSharesListener = nil
        receivedMixtapeSharesListener?.remove()
        receivedMixtapeSharesListener = nil
        receivedAlbumSharesListener?.remove()
        receivedAlbumSharesListener = nil
        conversationsListener?.remove()
        conversationsListener = nil
        friendsListener?.remove()
        friendsListener = nil
        userStatsListener?.remove()
        userStatsListener = nil
        widgetReloadTask?.cancel()
        widgetReloadTask = nil
        currentUser = nil
        friends = []
        incomingRequests = []
        outgoingRequestUIDs = []
        outgoingRequests = []
        invitedContacts = []
        onboardingRequestedUsers = []
        blockedUserIds = []
        sendStats = [:]
        inFlightDirectSendKeys = []
        pendingDirectShares = [:]
        receivedShares = []
        sentShares = []
        receivedMixtapeShares = []
        sentMixtapeShares = []
        receivedAlbumShares = []
        sentAlbumShares = []
        likedShareIds = []
        likedSongIds = []
        likedSongs = []
        conversations = []
        saveService.clear()
        mixtapeStore.clear()
        isOnboarded = false
        isBackendAvailable = false
        // Phase B: reset invite-code onboarding state so a returning
        // user starting a new signup on this device doesn't inherit a
        // stale gate value or pending deep-link code.
        inviteCode = ""
        inviteCodeError = nil
        inviteCodeKind = nil
        inviteSuggestedUser = nil
        contactSuggestedUsers = []
        DeepLinkService.shared.clearPendingInviteCode()
        DeepLinkService.shared.clearPendingReferrer()
        AudioPlayerService.shared.stop()
        FirebaseService.shared.signOut()
        UserDefaults.standard.removeObject(forKey: "currentUserId")
        UserDefaults.standard.removeObject(forKey: "currentUserFirstName")
        UserDefaults.standard.removeObject(forKey: "currentUserLastName")
        UserDefaults.standard.removeObject(forKey: "currentUserUsername")
        UserDefaults.standard.removeObject(forKey: "currentUserPhone")
        UserDefaults.standard.removeObject(forKey: "currentUserAvatarURL")
        UserDefaults.standard.removeObject(forKey: "likedShareIds")
        UserDefaults.standard.removeObject(forKey: "likedSongIds")
        UserDefaults.standard.removeObject(forKey: "preferredMusicService")
        clearWidgetSharedState()
    }

    func refreshShares(force: Bool = true) async {
        let firebase = FirebaseService.shared
        guard firebase.isSignedIn else { return }
        guard !isRefreshSharesInFlight else { return }
        if !force,
           let lastSuccessfulShareRefreshAt,
           Date().timeIntervalSince(lastSuccessfulShareRefreshAt) < foregroundRefreshMinInterval {
            return
        }

        isRefreshSharesInFlight = true
        defer { isRefreshSharesInFlight = false }

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

        let serverLikedSongs = await firebase.loadLikedSongs()
        if !serverLikedSongs.isEmpty {
            likedSongs = serverLikedSongs
            likedSongIds = Set(serverLikedSongs.map(\.id))
        }

        // Refresh saves + mixtapes alongside shares so the Mixtapes screen
        // reflects new saves made on another device since last refresh.
        async let saveIndex: () = saveService.loadFromFirestore()
        async let mixtapeFetch: () = mixtapeStore.loadFromFirestore()
        _ = await (saveIndex, mixtapeFetch)

        syncWidgetWithLatestReceivedShare()
        lastSuccessfulShareRefreshAt = Date()
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
        if let avatarURL = latest.sender.avatarURL, !avatarURL.isEmpty {
            defaults?.set(avatarURL, forKey: WidgetSharedConstants.Key.senderAvatarURL)
        } else {
            defaults?.removeObject(forKey: WidgetSharedConstants.Key.senderAvatarURL)
        }
        if let note = latest.note, !note.isEmpty {
            defaults?.set(note, forKey: WidgetSharedConstants.Key.note)
        } else {
            defaults?.removeObject(forKey: WidgetSharedConstants.Key.note)
        }
        defaults?.set(latest.id, forKey: WidgetSharedConstants.Key.shareId)

        Task.detached {
            await Self.downloadWidgetImage(urlString: latest.song.albumArtURL, fileURL: WidgetSharedConstants.albumArtFileURL(), label: "album art")
            await Self.downloadWidgetImage(urlString: latest.sender.avatarURL ?? "", fileURL: WidgetSharedConstants.senderAvatarFileURL(), label: "sender avatar")
        }
    }

    private static func downloadWidgetImage(urlString: String, fileURL: URL?, label: String) async {
        guard let imageFile = fileURL else { return }

        guard let url = URL(string: urlString), !urlString.isEmpty else {
            try? FileManager.default.removeItem(at: imageFile)
            await MainActor.run { WidgetCenter.shared.reloadAllTimelines() }
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            try data.write(to: imageFile, options: .atomic)
        } catch {
            print("Widget \(label) download failed: \(error.localizedDescription)")
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
        if let avatarFile = WidgetSharedConstants.senderAvatarFileURL() {
            try? FileManager.default.removeItem(at: avatarFile)
        }
    }
}
