import SwiftUI
import UIKit

private let hasRequestedNotificationPermissionKey = "hasRequestedNotificationPermission"

/// Renders the profile tab's circular initials avatar into a `UIImage` so it
/// can be used directly as a `Tab` label. `.alwaysOriginal` prevents the tab
/// bar from tinting it, preserving the avatar look across selected/unselected.
private enum TabBarAvatar {
    static func image(for initials: String, size: CGFloat = 28) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        let rendered = renderer.image { ctx in
            let rect = CGRect(x: 0, y: 0, width: size, height: size)
            UIColor(white: 1.0, alpha: 0.18).setFill()
            ctx.cgContext.fillEllipse(in: rect)

            let text = initials.isEmpty ? "?" : initials
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: size * 0.42, weight: .semibold),
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraph
            ]
            let textSize = (text as NSString).size(withAttributes: attrs)
            let textRect = CGRect(x: 0, y: (size - textSize.height) / 2, width: size, height: textSize.height)
            (text as NSString).draw(in: textRect, withAttributes: attrs)
        }
        return rendered.withRenderingMode(.alwaysOriginal)
    }
}

struct ContentView: View {
    @State private var appState = AppState()
    @State private var showSendSheet = false
    @State private var showAddFriends = false
    @State private var selectedTab: Int = 0
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
                    // `selectedTab` defaults to 0 for fresh installs, but
                    // pinning it here defends against any future path that
                    // might have mutated it during onboarding, or any iOS
                    // state-restore that would otherwise drop the user on
                    // Profile/Messages.
                    selectedTab = 0
                    Task { await appState.loadData() }
                }
                .preferredColorScheme(.dark)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active, appState.isOnboarded else { return }
            Task { await appState.refreshShares() }
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
        selectedTab = 0
        appState.pendingDiscoveryShareId = trimmed
    }

    /// First-launch-after-onboarding: ask iOS directly. No custom explainer.
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
    /// left-to-right to match the visual tab bar: Messages, Discovery,
    /// Profile.
    private static let swipeableTabs: [Int] = [2, 0, 3]

    /// Haptic used when entering Search from either the nav magnifier or the
    /// on-screen CTA — medium impact per spec so the transition feels
    /// intentional.
    private let searchHaptic = UIImpactFeedbackGenerator(style: .medium)

    @ViewBuilder
    private var miniPlayerOverlay: some View {
        // Always hide on the Discovery tab — both the hero (so the CTA reads
        // cleanly) and the history card pages (so the reply pill stays
        // unobstructed). Shows on Messages and Profile so in-progress
        // playback remains recoverable.
        if selectedTab != 0, let song = AudioPlayerService.shared.currentSong {
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
                if new == 0 && selectedTab == 0 {
                    if discoveryIsOnHero {
                        openSearch()
                    } else {
                        scrollDiscoveryToHero()
                    }
                } else {
                    selectedTab = new
                }
            }
        )
    }

    private func openSearch() {
        searchHaptic.prepare()
        searchHaptic.impactOccurred()
        showSendSheet = true
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
                selectedTab = ordered[idx + 1]
            }
        } else if horizontal > 60 {
            guard idx > 0 else { return }
            withAnimation(.easeInOut(duration: 0.28)) {
                selectedTab = ordered[idx - 1]
            }
        }
    }

    private var mainTabView: some View {
        TabView(selection: selectedTabBinding) {
            Tab(value: 2) {
                MessagesListView(appState: appState)
            } label: {
                Image(systemName: "bubble.left.and.bubble.right.fill")
            }
            .badge(appState.totalUnreadCount)

            Tab(value: 0) {
                DiscoveryView(
                    shares: appState.receivedShares,
                    appState: appState,
                    onSearchTap: openSearch,
                    onAddFriends: { showAddFriends = true },
                    onHeroVisibilityChange: { isHero in
                        discoveryIsOnHero = isHero
                    }
                )
            } label: {
                Image(systemName: "magnifyingglass")
            }

            Tab(value: 3) {
                ProfileView(appState: appState)
            } label: {
                Image(uiImage: TabBarAvatar.image(for: appState.currentUser?.initials ?? "?"))
            }
        }
        .tint(.white)
        .preferredColorScheme(.dark)
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
            if newValue == 2 {
                Task { await appState.loadConversations() }
            }
        }
        .sheet(isPresented: $showSendSheet) {
            SendSongSheet(appState: appState)
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
        .onReceive(NotificationCenter.default.publisher(for: .didReceiveDeepLink)) { notification in
            guard let data = notification.userInfo as? [String: Any],
                  let referrerId = data["referringUserId"] as? String,
                  !referrerId.isEmpty,
                  let currentUID = appState.currentUser?.id,
                  referrerId != currentUID else { return }

            DeepLinkService.shared.pendingReferrerId = referrerId
            DeepLinkService.shared.pendingReferrerUsername = data["referringUsername"] as? String
            Task {
                await appState.processReferralIfNeeded(currentUID: currentUID)
            }
        }
    }
}
