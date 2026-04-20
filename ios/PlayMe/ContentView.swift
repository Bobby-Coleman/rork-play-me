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
                    Task { await appState.loadData() }
                }
                .preferredColorScheme(.dark)
            }
        }
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

    private var mainTabView: some View {
        TabView(selection: $selectedTab) {
            Tab(value: 0) {
                HomeFeedView(shares: appState.receivedShares, appState: appState, onSendSong: { showSendSheet = true }, onAddFriends: { showAddFriends = true })
            } label: {
                Image(systemName: "house.fill")
            }

            Tab(value: 1) {
                Color.black
            } label: {
                Image(systemName: "magnifyingglass")
            }

            Tab(value: 2) {
                MessagesListView(appState: appState)
            } label: {
                Image(systemName: "bubble.left.and.bubble.right.fill")
            }
            .badge(appState.totalUnreadCount)

            Tab(value: 3) {
                ProfileView(appState: appState)
            } label: {
                Image(uiImage: TabBarAvatar.image(for: appState.currentUser?.initials ?? "?"))
            }
        }
        .tint(.white)
        .preferredColorScheme(.dark)
        .onChange(of: selectedTab) { _, newValue in
            if newValue == 1 {
                showSendSheet = true
            }
            if newValue == 2 {
                Task { await appState.loadConversations() }
            }
        }
        .sheet(isPresented: $showSendSheet) {
            selectedTab = 0
        } content: {
            SendSongSheet(appState: appState)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showAddFriends) {
            AddFriendsView(appState: appState)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
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
