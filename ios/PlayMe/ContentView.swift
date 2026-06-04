import SwiftUI
import UIKit

private let hasRequestedNotificationPermissionKey = "hasRequestedNotificationPermission"
private let didShowProfilePhotoAnnouncementKey = "didShowProfilePhotoAnnouncement"

/// Top-level tabs in their visual left-to-right order. Pinning the
/// underlying `Int` values lets us preserve the existing onboarding /
/// deep-link logic that already centers the magnifier as the "true home"
/// while still being able to reorder labels in the bar without leaking
/// magic numbers across the file.
enum MainTab: Int, CaseIterable {
    case home = 1
    case messages = 2
    case discovery = 0
    case mixtapes = 3
}

/// Why an intent enum instead of `Bool + Song?`:
/// SwiftUI's `.sheet(isPresented:)` reuses the same view identity across
/// presentations of the same sheet. `SendSongSheet` sets its initial
/// `step` from `initialSong` via `@State`'s initial value, but `@State`
/// only honors that initial value on the **first** allocation for a
/// given identity. Once the user opens the empty search sheet once,
/// every subsequent presentation (including a Shazam-with-song one)
/// reuses the existing `@State` storage at `step = 0` and the new
/// initial value is silently dropped — so the recipient picker never
/// appears.
///
/// Driving the sheet with `.sheet(item:)` on this enum forces SwiftUI to
/// rebuild `SendSongSheet` from scratch every time the intent changes
/// (different `id`), so the `_step = State(initialValue:)` line in the
/// sheet's init is honored every presentation.
private enum SendSheetIntent: Identifiable {
    case search
    case sendShazamMatch(Song)

    var id: String {
        switch self {
        case .search:
            return "search"
        case .sendShazamMatch(let song):
            return "send:\(song.id)"
        }
    }
}

struct ContentView: View {
    @State private var appState = AppState()
    @State private var sendSheetIntent: SendSheetIntent?
    @State private var showAddFriends = false
    @State private var selectedTab: Int = MainTab.discovery.rawValue
    /// Which inner page the Library (Mixtapes) tab is showing. Bound into
    /// `MixtapesView` so the top segment control and the inner `LibraryPager`
    /// stay in sync; the pager itself owns swipe handling.
    @State private var librarySegment: MixtapesSegment = .songs
    @State private var messagesNavigationResetToken: Int = 0
    @State private var miniPlayerSong: Song?
    /// Tracks whether the Discovery tab is currently showing its hero page
    /// (vs. scrolled into the history feed). Mini-player stays hidden on the
    /// hero so the CTA + ambient grid read cleanly.
    @State private var discoveryIsOnHero: Bool = true
    @Environment(\.scenePhase) private var scenePhase
    /// True only when this app session started already onboarded — used so returning users
    /// (who installed before this flow existed) never see the first-launch permission prompt
    /// from us; their status is recorded as "already asked" silently.
    @State private var sessionBeganAlreadyOnboarded = UserDefaults.standard.bool(forKey: "isOnboarded")
    /// One-time "profile pictures are here" announcement for existing users
    /// who onboarded before the feature shipped and don't have a photo yet.
    @State private var showProfilePhotoAnnouncement = false
    @State private var showProfilePhotoEditor = false
    /// True while a song shared in from Spotify/Apple Music (via the RiffShare
    /// Share Extension) is being resolved into a catalog `Song`. Drives the
    /// brief "Adding song…" HUD so the wait doesn't feel like a dead tap.
    @State private var isResolvingSharedSong = false
    /// Shown when a shared link couldn't be mapped to a sendable song.
    @State private var sharedSongImportFailed = false

    init() {
        // Hide tab titles globally so the bar stays icon-only even when iOS
        // would otherwise fall back to showing a default label.
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        let clearTitle: [NSAttributedString.Key: Any] = [.foregroundColor: UIColor.clear]
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = clearTitle
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = clearTitle
        appearance.inlineLayoutAppearance.normal.titleTextAttributes = clearTitle
        appearance.inlineLayoutAppearance.selected.titleTextAttributes = clearTitle
        appearance.compactInlineLayoutAppearance.normal.titleTextAttributes = clearTitle
        appearance.compactInlineLayoutAppearance.selected.titleTextAttributes = clearTitle
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some View {
        ZStack {
            // Global background driven by the user's chosen RIFF theme.
            // Painting it behind the main UI gives every screen a tinted
            // backdrop without each surface re-implementing the swap.
            // Foreground elements still render in their existing white-on-
            // dark style; cross-screen accent recoloring is a follow-up.
            appState.appTheme.bg.ignoresSafeArea()

            Group {
                if appState.isOnboarded {
                    mainTabView
                        .task {
                            await appState.loadData()
                            maybeShowProfilePhotoAnnouncement()
                            // Cold-launch case: a share link may have arrived
                            // (deep link or App Group) before the main UI was
                            // ready to resolve it.
                            consumePendingSharedSong(maxAgeSeconds: 60)
                            processPendingSharedSongIfPossible()
                        }
                        .task {
                            await requestNotificationPermissionOnceIfNeeded()
                        }
                        .sheet(isPresented: $showProfilePhotoAnnouncement) {
                            ProfilePhotoAnnouncementView(
                                initials: announcementInitials,
                                onAddPhoto: {
                                    showProfilePhotoAnnouncement = false
                                    showProfilePhotoEditor = true
                                },
                                onDismiss: { showProfilePhotoAnnouncement = false }
                            )
                            .presentationBackground(.black)
                            .presentationDetents([.large])
                        }
                        .sheet(isPresented: $showProfilePhotoEditor) {
                            ProfilePhotoEditorView(appState: appState)
                                .presentationBackground(.black)
                                .presentationDetents([.large])
                                .presentationDragIndicator(.visible)
                        }
                } else {
                    OnboardingView(appState: appState) {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            appState.isOnboarded = true
                        }
                        // Force the Discovery (magnifier) tab on first landing.
                        // Despite the new Home tab being to its left visually,
                        // the magnifier is still the "true home" of the app
                        // and we want returning + brand-new users alike to
                        // land there.
                        selectedTab = MainTab.discovery.rawValue
                        Task { await appState.loadData() }
                    }
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            // Foreground fallback: if the Share Extension's `openURL` was
            // throttled, the link still lands in the App Group. Pick it up
            // only when fresh (< 60 s) so we never replay a stale share.
            consumePendingSharedSong(maxAgeSeconds: 60)
            processPendingSharedSongIfPossible()
            guard appState.isOnboarded else { return }
            Task { await appState.refreshShares(force: false) }
        }
        .onOpenURL { url in
            handleIncomingURL(url)
        }
        .onChange(of: appState.pendingExternalShareURL) { _, _ in
            processPendingSharedSongIfPossible()
        }
        .onChange(of: appState.isOnboarded) { _, isOn in
            // A link shared before sign-in is held until the user lands in the
            // app; process it the moment onboarding completes.
            if isOn { processPendingSharedSongIfPossible() }
        }
        .overlay {
            if isResolvingSharedSong {
                sharedSongLoadingHUD
            }
        }
        .alert("Couldn't add that song", isPresented: $sharedSongImportFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("We couldn't find that track. Try sharing it again, or search for it in Riff.")
        }
    }

    /// Lightweight blocking HUD shown while a shared link resolves. Kept
    /// minimal (dimmed scrim + spinner) since resolution is usually < 1 s.
    private var sharedSongLoadingHUD: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
                Text("Adding song…")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(28)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        }
        .transition(.opacity)
    }

    /// Routes incoming custom-scheme URLs. Currently handles the widget
    /// deep link (`playme://share/<shareId>`): tapping the home-screen
    /// widget should open the feed at the same song the widget was
    /// showing, not the hero. Unknown URLs fall through to the
    /// `.onOpenURL` attached at the app level (ChottuLink / Firebase
    /// auth), so other deep links are unaffected.
    private func handleIncomingURL(_ url: URL) {
        guard url.scheme?.lowercased() == "playme" else { return }

        switch url.host?.lowercased() {
        case "share-song":
            // Sent by the RiffShare Share Extension after it stashes the
            // shared track link in the App Group. Pick it up regardless of
            // age (the deep link itself is the freshness signal), then
            // resolve + present the send sheet.
            consumePendingSharedSong(maxAgeSeconds: nil)
            processPendingSharedSongIfPossible()

        case "share":
            // URL.pathComponents starts with "/"; drop it to isolate the id.
            let id = url.pathComponents.filter { $0 != "/" }.first
                ?? url.lastPathComponent
            let trimmed = id.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return }
            // Force Discovery tab so the scroll target actually renders. The
            // feed observer in DiscoveryView picks up the pending id and
            // animates the scroll — this works whether the share list is
            // already hydrated or arrives a moment later on cold launch.
            selectedTab = MainTab.discovery.rawValue
            appState.pendingDiscoveryShareId = trimmed

        default:
            return
        }
    }

    /// Moves a pending shared track link out of the App Group container and
    /// into `appState.pendingExternalShareURL`. Clears the App Group keys
    /// immediately so a given share is only ever processed once. When
    /// `maxAgeSeconds` is set, links older than the window are ignored (used
    /// by the foreground fallback to avoid replaying stale shares).
    private func consumePendingSharedSong(maxAgeSeconds: TimeInterval?) {
        guard let defaults = UserDefaults(suiteName: WidgetSharedConstants.appGroup) else { return }
        guard let urlString = defaults.string(forKey: WidgetSharedConstants.Key.pendingShareSongURL),
              !urlString.isEmpty else { return }
        if let maxAgeSeconds {
            let at = defaults.double(forKey: WidgetSharedConstants.Key.pendingShareSongURLAt)
            guard at > 0, Date().timeIntervalSince1970 - at <= maxAgeSeconds else { return }
        }
        defaults.removeObject(forKey: WidgetSharedConstants.Key.pendingShareSongURL)
        defaults.removeObject(forKey: WidgetSharedConstants.Key.pendingShareSongURLAt)
        appState.pendingExternalShareURL = urlString
    }

    /// Resolves a pending shared link to a `Song` and opens the normal send
    /// sheet (reusing the Shazam intent path that skips the search step). No-op
    /// until the user is onboarded, so a link tapped before sign-in is held
    /// and processed once they reach the main app.
    private func processPendingSharedSongIfPossible() {
        guard appState.isOnboarded else { return }
        guard let raw = appState.pendingExternalShareURL, !raw.isEmpty else { return }
        guard !isResolvingSharedSong else { return }
        isResolvingSharedSong = true
        Task { @MainActor in
            let song = await ShareURLResolver.resolveSong(fromShareURL: raw)
            isResolvingSharedSong = false
            appState.pendingExternalShareURL = nil
            if let song {
                selectedTab = MainTab.discovery.rawValue
                sendSheetIntent = .sendShazamMatch(song)
            } else {
                sharedSongImportFailed = true
            }
        }
    }

    /// Fallback path that asks for notification permission once after a
    /// signed-in session lands on the main UI. The new RIFF onboarding
    /// has its own dedicated `NotificationsPermissionView` step that
    /// sets the same `hasRequestedNotificationPermission` UserDefaults
    /// key, so this fallback is a no-op for any user who completed the
    /// new flow. It still covers existing installs that completed
    /// onboarding before this rebuild shipped.
    private func requestNotificationPermissionOnceIfNeeded() async {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: hasRequestedNotificationPermissionKey) else { return }
        if sessionBeganAlreadyOnboarded {
            defaults.set(true, forKey: hasRequestedNotificationPermissionKey)
            return
        }
        let status = await NotificationPermission.requestAuthorizationAndRegister()
        let allowed = status == .authorized || status == .provisional || status == .ephemeral
        await appState.setNotificationsEnabled(allowed)
        defaults.set(true, forKey: hasRequestedNotificationPermissionKey)
    }

    /// Initials shown on the announcement's sample avatar.
    private var announcementInitials: String {
        profileInitials(
            firstName: appState.currentUser?.firstName ?? "",
            lastName: appState.currentUser?.lastName ?? ""
        )
    }

    /// Shows the profile-photo announcement exactly once, and only to users
    /// who installed before the feature existed (`sessionBeganAlreadyOnboarded`)
    /// and don't already have a photo. Brand-new users set a photo during
    /// onboarding, so they never see it. The flag is persisted the moment it
    /// shows so it can't repeat on later launches.
    private func maybeShowProfilePhotoAnnouncement() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: didShowProfilePhotoAnnouncementKey) else { return }
        guard sessionBeganAlreadyOnboarded else { return }
        let avatar = appState.currentUser?.avatarURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (avatar ?? "").isEmpty else { return }
        defaults.set(true, forKey: didShowProfilePhotoAnnouncementKey)
        showProfilePhotoAnnouncement = true
    }

    /// Tab indices that participate in horizontal swipe navigation. Ordered
    /// left-to-right to match the visual tab bar: Home, Messages, Discovery,
    /// Mixtapes.
    private static let swipeableTabs: [Int] = [
        MainTab.home.rawValue,
        MainTab.messages.rawValue,
        MainTab.discovery.rawValue,
        MainTab.mixtapes.rawValue
    ]

    /// Haptic used when entering Search from either the nav magnifier or the
    /// on-screen CTA — medium impact per spec so the transition feels
    /// intentional.
    private let searchHaptic = UIImpactFeedbackGenerator(style: .medium)

    @ViewBuilder
    private var miniPlayerOverlay: some View {
        // Hide on Home and Discovery so the staggered Pinterest grid /
        // hero CTA reads cleanly. Shows on Messages and Mixtapes so
        // in-progress playback remains recoverable from those surfaces.
        let isImmersiveTab = selectedTab == MainTab.discovery.rawValue || selectedTab == MainTab.home.rawValue
        if !isImmersiveTab, let song = AudioPlayerService.shared.currentSong {
            MiniPlayerBar(song: song) {
                miniPlayerSong = song
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 54)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    /// Custom binding that intercepts a tap on the already-selected Discovery
    /// tab. If the user is currently scrolled into the history feed the tap
    /// first animates them back to the hero page. Only a *second* tap on
    /// an already-visible hero opens Search — preventing the "scroll +
    /// search fires together" race documented in the design spec.
    private var selectedTabBinding: Binding<Int> {
        Binding(
            get: { selectedTab },
            set: { new in
                let discoveryRaw = MainTab.discovery.rawValue
                if new == discoveryRaw && selectedTab == discoveryRaw {
                    if discoveryIsOnHero {
                        openSearch()
                    } else {
                        scrollDiscoveryToHero()
                    }
                } else {
                    selectTab(new)
                }
            }
        )
    }

    private func selectTab(_ newTab: Int) {
        if newTab == MainTab.messages.rawValue {
            messagesNavigationResetToken &+= 1
        }
        selectedTab = newTab
    }

    private func openSearch() {
        searchHaptic.prepare()
        searchHaptic.impactOccurred()
        sendSheetIntent = .search
    }

    /// Bumps the shared scroll-to-hero counter. `DiscoveryView` observes it
    /// and animates its `ScrollViewReader` back to the hero page.
    private func scrollDiscoveryToHero() {
        appState.discoveryScrollToTopCounter &+= 1
    }

    private func navigateTabBySwipe(translationWidth: CGFloat) {
        let horizontal = translationWidth
        let ordered = Self.swipeableTabs
        guard let idx = ordered.firstIndex(of: selectedTab) else { return }
        if horizontal < -60 {
            guard idx + 1 < ordered.count else { return }
            withAnimation(.easeInOut(duration: 0.28)) {
                selectTab(ordered[idx + 1])
            }
        } else if horizontal > 60 {
            guard idx > 0 else { return }
            withAnimation(.easeInOut(duration: 0.28)) {
                selectTab(ordered[idx - 1])
            }
        }
    }

    private var mainTabView: some View {
        TabView(selection: selectedTabBinding) {
            // Visual order: Home | Messages | Discovery | Mixtapes.
            // SwiftUI's `Tab` API lets us decouple `value` (used by
            // selection/swipe logic) from declaration order, so we keep
            // the existing Discovery == 0 contract for onboarding /
            // deep-link routing.
            Tab(value: MainTab.home.rawValue) {
                HomeDiscoverView(appState: appState)
            } label: {
                Image(systemName: "house.fill")
            }

            Tab(value: MainTab.messages.rawValue) {
                MessagesListView(appState: appState, resetToken: messagesNavigationResetToken)
            } label: {
                Image(systemName: "bubble.left.and.bubble.right.fill")
            }
            .badge(appState.totalUnreadCount)

            Tab(value: MainTab.discovery.rawValue) {
                DiscoveryView(
                    feedItems: appState.discoveryFeedItems,
                    appState: appState,
                    onSearchTap: openSearch,
                    onShazamSongResolved: { song in
                        sendSheetIntent = .sendShazamMatch(song)
                    },
                    onAddFriends: { showAddFriends = true },
                    onHeroVisibilityChange: { isHero in
                        discoveryIsOnHero = isHero
                    }
                )
            } label: {
                Image(systemName: "magnifyingglass")
            }

            Tab(value: MainTab.mixtapes.rawValue) {
                MixtapesView(
                    appState: appState,
                    selectedSegment: $librarySegment,
                    onSendSong: { sendSheetIntent = .search },
                    onSwipeToSearch: { selectTab(MainTab.discovery.rawValue) }
                )
            } label: {
                Image(systemName: "rectangle.stack.fill")
            }
        }
        .tint(.white)
        .preferredColorScheme(.dark)
        .simultaneousGesture(
            DragGesture(minimumDistance: 50)
                .onEnded { value in
                    // The Library tab's inner `LibraryPager` owns its own
                    // swipes (Songs<->Mixtapes paging and the Songs->Search
                    // hand-off), so the global gesture must stay out of its
                    // way to avoid the old double-animation clunk.
                    guard selectedTab != MainTab.mixtapes.rawValue else { return }
                    let h = value.translation.width
                    let v = value.translation.height
                    guard abs(h) > max(72, abs(v) * 1.25) else { return }
                    navigateTabBySwipe(translationWidth: h)
                }
        )
        .onChange(of: selectedTab) { _, newValue in
            if newValue == MainTab.messages.rawValue {
                Task { await appState.loadConversations() }
            }
        }
        .sheet(item: $sendSheetIntent) { intent in
            SendSongSheet(
                appState: appState,
                initialSong: {
                    if case .sendShazamMatch(let song) = intent { return song }
                    return nil
                }()
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showAddFriends) {
            AddFriendsView(appState: appState)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $miniPlayerSong) { song in
            SongActionSheet(song: song, appState: appState)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .overlay(alignment: .bottom) {
            miniPlayerOverlay
        }
        // Deliberately no implicit animation on `selectedTab` — the tab
        // transition itself is a UIKit crossfade handled by TabView, and
        // letting SwiftUI animate dependent state in response propagates
        // spring settle into child ScrollViews (contributing to the
        // landing-page bounce the spec calls out).
        .animation(.easeInOut(duration: 0.22), value: AudioPlayerService.shared.currentSong?.id)
        // Phase B: the old `?referringUserId=` auto-friend-on-foreground
        // path was removed. Auto-friending now happens server-side
        // during `redeemInviteCode` for `personal` invite codes. An
        // already-signed-in user tapping an invite link still resolves
        // the deep link (via ChottuLink) but the embedded `?code=` is
        // ignored — they're already past the gate.
    }
}
