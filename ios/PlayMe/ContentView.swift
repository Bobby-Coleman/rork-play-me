import SwiftUI

struct ContentView: View {
    @State private var appState = AppState()
    @State private var showSendSheet = false
    @State private var showAddFriends = false
    @State private var selectedTab: Int = 0

    var body: some View {
        if appState.isOnboarded {
            mainTabView
                .task {
                    await appState.loadData()
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

    private var mainTabView: some View {
        TabView(selection: $selectedTab) {
            Tab(value: 0) {
                HomeFeedView(shares: appState.receivedShares, appState: appState, onSendSong: { showSendSheet = true }, onAddFriends: { showAddFriends = true })
            } label: {
                Image(systemName: "house.fill")
                Text("Home")
            }

            Tab(value: 1) {
                Color.black
            } label: {
                Image(systemName: "paperplane.fill")
                Text("Send")
            }

            Tab(value: 2) {
                MessagesListView(appState: appState)
            } label: {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                Text("Messages")
            }
            .badge(appState.totalUnreadCount)

            Tab(value: 3) {
                ProfileView(appState: appState)
            } label: {
                Image(systemName: "person.fill")
                Text("Profile")
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
