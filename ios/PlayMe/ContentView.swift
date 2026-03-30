import SwiftUI

struct ContentView: View {
    @State private var appState = AppState()
    @State private var showSendSheet = false
    @State private var selectedTab: Int = 0
    @State private var showFullPlayer = false

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
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                Tab(value: 0) {
                    HomeFeedView(shares: appState.receivedShares, appState: appState, onSendSong: { showSendSheet = true })
                } label: {
                    Image(systemName: "house.fill")
                    Text("Home")
                }

                Tab(value: 1) {
                    Color.black
                        .onAppear { showSendSheet = true }
                } label: {
                    Image(systemName: "paperplane.fill")
                    Text("Send")
                }

                Tab(value: 2) {
                    ProfileView(appState: appState)
                } label: {
                    Image(systemName: "person.fill")
                    Text("Profile")
                }
            }
            .tint(.white)
            .preferredColorScheme(.dark)
            .sheet(isPresented: $showSendSheet) {
                if selectedTab == 1 { selectedTab = 0 }
            } content: {
                SendSongSheet(appState: appState)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }

            if appState.audioPlayer.currentSong != nil {
                NowPlayingBar(player: appState.audioPlayer) {
                    showFullPlayer = true
                }
                .padding(.bottom, 50)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(duration: 0.3), value: appState.audioPlayer.currentSong?.id)
            }
        }
        .sheet(isPresented: $showFullPlayer) {
            NowPlayingFullView(player: appState.audioPlayer)
                .presentationBackground(.black)
                .presentationDragIndicator(.visible)
        }
    }
}
