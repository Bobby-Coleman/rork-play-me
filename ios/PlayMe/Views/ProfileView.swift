import SwiftUI

enum ProfileTab: String, CaseIterable {
    case received = "Received"
    case sent = "Sent"
    case liked = "Liked"
}

struct ProfileView: View {
    @Bindable var appState: AppState

    @State private var selectedTab: ProfileTab = .received
    @State private var detailShare: SongShare?
    @State private var showSettings: Bool = false

    private var user: AppUser? { appState.currentUser }

    private var currentShares: [SongShare] {
        switch selectedTab {
        case .received: appState.receivedShares
        case .sent: appState.sentShares
        case .liked: appState.likedShares
        }
    }

    var body: some View {
        NavigationStack {
            profileContent
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 17))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        .accessibilityLabel("Settings")
                    }
                }
                .toolbarColorScheme(.dark, for: .navigationBar)
                .toolbarBackground(.black, for: .navigationBar)
                .sheet(isPresented: $showSettings) {
                    NavigationStack {
                        SettingsView(appState: appState)
                    }
                    .presentationBackground(.black)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                }
        }
    }

    private var profileContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 10) {
                    Text(user?.initials ?? "?")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 80, height: 80)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())

                    Text(user?.firstName ?? "")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)

                    Text("@\(user?.username ?? "")")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.4))

                    HStack(spacing: 6) {
                        Image(systemName: "music.note.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(appState.preferredMusicService == .spotify ? .green : .pink)
                        Text(appState.preferredMusicService == .spotify ? "Spotify listener" : "Apple Music listener")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .padding(.top, 4)

                    if !appState.isBackendAvailable {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(.orange)
                                .frame(width: 6, height: 6)
                            Text("Offline mode")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.3))
                        }
                        .padding(.top, 2)
                    }
                }
                .padding(.top, 32)

                tabPicker
                    .padding(.horizontal, 20)

                LazyVStack(spacing: 0) {
                    if currentShares.isEmpty {
                        emptyState
                    } else {
                        ForEach(currentShares) { share in
                            ProfileSongRow(
                                share: share,
                                personLabel: personLabel(for: share),
                                isLiked: appState.isLiked(shareId: share.id),
                                onToggleLike: { appState.toggleLike(shareId: share.id) },
                                onTap: { detailShare = share }
                            )

                            if share.id != currentShares.last?.id {
                                Divider()
                                    .background(Color.white.opacity(0.06))
                                    .padding(.horizontal, 20)
                            }
                        }
                    }
                }

                Color.clear.frame(height: 40)
            }
        }
        .scrollIndicators(.hidden)
        .background(Color.black)
        .refreshable {
            await appState.refreshShares()
        }
        .sheet(item: $detailShare) { share in
            SongActionSheet(song: share.song, appState: appState, share: share)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    private func personLabel(for share: SongShare) -> String {
        switch selectedTab {
        case .received: share.sender.firstName
        case .sent: share.recipient.firstName
        case .liked:
            if share.sender.id == appState.currentUser?.id {
                "To \(share.recipient.firstName)"
            } else {
                "From \(share.sender.firstName)"
            }
        }
    }

    private var tabPicker: some View {
        HStack(spacing: 0) {
            ForEach(ProfileTab.allCases, id: \.self) { tab in
                let count: Int = {
                    switch tab {
                    case .received: appState.receivedShares.count
                    case .sent: appState.sentShares.count
                    case .liked: appState.likedShares.count
                    }
                }()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 6) {
                        HStack(spacing: 4) {
                            if tab == .liked {
                                Image(systemName: "heart.fill")
                                    .font(.system(size: 11))
                            }
                            Text(tab.rawValue)
                                .font(.system(size: 14, weight: .semibold))
                            Text("\(count)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(selectedTab == tab ? .white.opacity(0.5) : .white.opacity(0.2))
                        }

                        Rectangle()
                            .fill(selectedTab == tab ? Color.white : Color.clear)
                            .frame(height: 2)
                    }
                    .foregroundStyle(selectedTab == tab ? .white : .white.opacity(0.35))
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            let (icon, text): (String, String) = {
                switch selectedTab {
                case .received: ("music.note", "No songs received yet")
                case .sent: ("paperplane", "No songs sent yet")
                case .liked: ("heart", "No liked songs yet")
                }
            }()

            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundStyle(.white.opacity(0.15))
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.3))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}

// MARK: - ProfileSongRow (isolates audioPlayer observation per row)

private struct ProfileSongRow: View {
    let share: SongShare
    let personLabel: String
    let isLiked: Bool
    let onToggleLike: () -> Void
    let onTap: () -> Void

    private var audioPlayer: AudioPlayerService { AudioPlayerService.shared }

    private var isPlaying: Bool {
        audioPlayer.currentSongId == share.song.id && audioPlayer.isPlaying
    }

    private var isLoading: Bool {
        audioPlayer.currentSongId == share.song.id && audioPlayer.isLoading
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Color(.systemGray5)
                    .frame(width: 48, height: 48)
                    .overlay {
                        AsyncImage(url: URL(string: share.song.albumArtURL)) { phase in
                            if let image = phase.image {
                                image.resizable().aspectRatio(contentMode: .fill)
                            }
                        }
                        .allowsHitTesting(false)
                    }
                    .clipShape(.rect(cornerRadius: 6))

                Button {
                    audioPlayer.play(song: share.song)
                } label: {
                    ZStack {
                        Circle()
                            .fill(.black.opacity(0.45))
                            .frame(width: 28, height: 28)

                        if isLoading {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.5)
                        } else {
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white)
                                .contentTransition(.symbolEffect(.replace))
                        }
                    }
                }
                .sensoryFeedback(.impact(weight: .light), trigger: isPlaying)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(share.song.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(personLabel)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.4))
            }

            Spacer()

            Button {
                onToggleLike()
            } label: {
                Image(systemName: isLiked ? "heart.fill" : "heart")
                    .font(.system(size: 16))
                    .foregroundStyle(isLiked ? .pink : .white.opacity(0.25))
            }
            .sensoryFeedback(.impact(weight: .light), trigger: isLiked)

            Text(share.timestamp.formatted(.relative(presentation: .named)))
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.25))
                .frame(width: 70, alignment: .trailing)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
    }
}
