import SwiftUI
import UIKit

private let hasRequestedNotificationPermissionKey = "hasRequestedNotificationPermission"

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

    init() {
        // Configure the tab-bar appearance once with the saved theme's
        // backdrop. Hide tab titles globally so the bar stays icon-only
        // even when iOS would otherwise fall back to showing a default
        // label. Live theme swaps re-run `applyTabBarAppearance` in
        // `.onChange(of: appTheme)`.
        let theme = RiffTheme.byId(
            UserDefaults.standard.string(forKey: "appTheme") ?? RiffTheme.black.id
        )
        Self.applyTabBarAppearance(theme: theme)
    }

    /// Build a `UITabBarAppearance` driven by the active RIFF theme and
    /// apply it as the global standard + scroll-edge appearance. Called
    /// from `init()` (cold start) and on `.onChange(of: appTheme)` so
    /// the bar tints in real time when the user re-picks a theme.
    private static func applyTabBarAppearance(theme: RiffTheme) {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = theme.bgUIColor
        // Drop the default subtle separator on light themes so the bar
        // reads as a continuation of the backdrop rather than a tray.
        appearance.shadowColor = .clear

        let clearTitle: [NSAttributedString.Key: Any] = [.foregroundColor: UIColor.clear]
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = clearTitle
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = clearTitle
        appearance.inlineLayoutAppearance.normal.titleTextAttributes = clearTitle
        appearance.inlineLayoutAppearance.selected.titleTextAttributes = clearTitle
        appearance.compactInlineLayoutAppearance.normal.titleTextAttributes = clearTitle
        appearance.compactInlineLayoutAppearance.selected.titleTextAttributes = clearTitle

        // Tint the icons themselves. SwiftUI's `.tint()` modifier is
        // applied per-TabView, but the unselected color comes from
        // UIKit's appearance system on iOS 17+. We use the theme
        // foreground for selected icons and a faded variant for the
        // unselected state so the active tab remains obvious on any
        // backdrop (especially the saturated red and forest themes).
        let fgUIColor = UIColor(theme.fg)
        appearance.stackedLayoutAppearance.normal.iconColor = fgUIColor.withAlphaComponent(0.35)
        appearance.stackedLayoutAppearance.selected.iconColor = fgUIColor
        appearance.inlineLayoutAppearance.normal.iconColor = fgUIColor.withAlphaComponent(0.35)
        appearance.inlineLayoutAppearance.selected.iconColor = fgUIColor
        appearance.compactInlineLayoutAppearance.normal.iconColor = fgUIColor.withAlphaComponent(0.35)
        appearance.compactInlineLayoutAppearance.selected.iconColor = fgUIColor

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some View {
        ZStack {
            // Global background driven by the user's chosen RIFF theme.
            // Painting it behind the main UI gives every screen a tinted
            // backdrop without each surface re-implementing the swap.
            appState.appTheme.bg.ignoresSafeArea()

            Group {
                if appState.isOnboarded {
                    mainTabView
                        .task {
                            await appState.loadData()
                        }
                        .task {
                            await requestNotificationPermissionOnceIfNeeded()
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
        .riffTheme(appState.appTheme)
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active, appState.isOnboarded else { return }
            Task { await appState.refreshShares() }
        }
        .onChange(of: appState.appTheme) { _, newTheme in
            // Re-tint the global tab-bar appearance when the user swaps
            // themes mid-session (Settings → Appearance). SwiftUI's
            // `.tint()` modifier handles the selected-icon color, but
            // the bar background + unselected icons live on UIKit's
            // `UITabBar.appearance()` and need an explicit refresh.
            Self.applyTabBarAppearance(theme: newTheme)
        }
        .onOpenURL { url in
            handleIncomingURL(url)
        }
    }

    /// Routes incoming custom-scheme URLs. Currently handles the widget
    /// deep link (`playme://share/<shareId>`): tapping the home-screen
    /// widget should open the feed at the same song the widget was
    /// showing, not the hero. Unknown URLs fall through to the
    /// `.onOpenURL` attached at the app level (ChottuLink / Firebase
    /// auth), so other deep links are unaffected.
    private func handleIncomingURL(_ url: URL) {
        guard url.scheme?.lowercased() == "playme" else { return }
        guard url.host?.lowercased() == "share" else { return }
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
                MixtapesView(appState: appState)
            } label: {
                Image(systemName: "rectangle.stack.fill")
            }
        }
        .tint(appState.appTheme.fg)
        .preferredColorScheme(appState.appTheme.isLight ? .light : .dark)
        .simultaneousGesture(
            DragGesture(minimumDistance: 50)
                .onEnded { value in
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
