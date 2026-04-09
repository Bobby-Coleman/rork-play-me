import SwiftUI

struct SongDetailSheet: View {
    let song: Song
    let appState: AppState
    var share: SongShare?
    var onDismiss: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    private var audioPlayer: AudioPlayerService { AudioPlayerService.shared }
    @State private var showShareFlow: Bool = false
    @State private var resolvedSpotifyURL: String?
    @State private var replyText: String = ""
    @State private var showSentConfirmation: Bool = false
    @State private var isSendingReply: Bool = false

    private var isCurrentSong: Bool {
        audioPlayer.currentSongId == song.id
    }

    private var isPlayingThis: Bool {
        isCurrentSong && audioPlayer.isPlaying
    }

    private var isLiked: Bool {
        guard let share else { return false }
        return appState.isLiked(shareId: share.id)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        headerSection
                        albumArtSection
                        if let share {
                            HStack(spacing: 6) {
                                Text(share.sender.firstName)
                                    .font(.system(size: 13, weight: .medium))
                                Text("·")
                                Text(share.timestamp, format: .dateTime.month(.abbreviated).day())
                            }
                            .foregroundStyle(.white.opacity(0.5))
                            .font(.system(size: 13))
                            .padding(.top, 12)
                        }
                        playerControls
                            .padding(.horizontal, 32)
                            .padding(.top, 16)
                            .padding(.bottom, 12)
                        actionButtons
                            .padding(.bottom, 32)
                    }
                }
                .scrollIndicators(.hidden)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                        onDismiss?()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(width: 32, height: 32)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Circle())
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .presentationBackground(.black)
        .task {
            if appState.preferredMusicService == .spotify, let amURL = song.appleMusicURL {
                resolvedSpotifyURL = await MusicSearchService.shared.resolveSpotifyURL(appleMusicURL: amURL)
            }
        }
        .sheet(isPresented: $showShareFlow) {
            NavigationStack {
                FriendSelectorView(
                    song: song,
                    appState: appState,
                    onBack: { showShareFlow = false },
                    onSent: {
                        showShareFlow = false
                        dismiss()
                        onDismiss?()
                    }
                )
            }
            .presentationBackground(.black)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 4) {
            if let share {
                Text("\(share.sender.firstName.uppercased()) SENT YOU A SONG")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(.white.opacity(0.5))
            }

            Text(song.title)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Text(song.artist)
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(.top, 16)
        .padding(.bottom, 20)
        .padding(.horizontal, 24)
    }

    // MARK: - Album Art

    private var albumArtSection: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: UIScreen.main.bounds.width - 48)
            .overlay {
                AsyncImage(url: URL(string: song.albumArtURL)) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else if phase.error != nil {
                        Color(.systemGray5)
                    } else {
                        Color(.systemGray6)
                            .overlay { ProgressView().tint(.white) }
                    }
                }
                .allowsHitTesting(false)
            }
            .clipShape(.rect(cornerRadius: 16))
            .overlay(alignment: .topTrailing) {
                if share != nil {
                    Button {
                        if let share {
                            appState.toggleLike(shareId: share.id)
                        }
                    } label: {
                        Image(systemName: isLiked ? "heart.fill" : "heart")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(isLiked ? .pink : .white.opacity(0.8))
                            .padding(10)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                    .sensoryFeedback(.impact(weight: .medium), trigger: isLiked)
                    .padding(12)
                }
            }
            .shadow(color: .white.opacity(0.05), radius: 20, y: 10)
            .padding(.horizontal, 24)
    }

    // MARK: - Player Controls

    private var playerControls: some View {
        VStack(spacing: 8) {
            ScrubBarView(songId: song.id, fallbackDuration: song.duration)
                .padding(.bottom, 2)

            HStack(spacing: 12) {
                Button {
                    audioPlayer.play(song: song)
                } label: {
                    ZStack {
                        if isCurrentSong && audioPlayer.isLoading {
                            ProgressView()
                                .tint(.black)
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: isPlayingThis ? "pause.fill" : "play.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .contentTransition(.symbolEffect(.replace))
                        }
                    }
                    .foregroundStyle(.black)
                    .frame(width: 52, height: 40)
                    .background(.white)
                    .clipShape(.capsule)
                }
                .sensoryFeedback(.impact(weight: .light), trigger: isPlayingThis)

                openInServiceButton(song: song, service: appState.preferredMusicService, resolvedSpotifyURL: resolvedSpotifyURL)

                Button {
                    showShareFlow = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 40, height: 40)
                        .background(Color.white.opacity(0.08))
                        .clipShape(.capsule)
                }
            }

            if let error = audioPlayer.error,
               audioPlayer.currentSongId == nil || audioPlayer.currentSongId == song.id {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.top, 4)
            }
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 10) {
            if let share {
                replyBar(for: share)
                    .padding(.horizontal, 24)
            }
        }
    }

    private func replyBar(for share: SongShare) -> some View {
        ZStack {
            if showSentConfirmation {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.green)
                    Text("Sent!")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .transition(.opacity)
            } else {
                HStack(spacing: 8) {
                    TextField("Reply to \(share.sender.firstName)...", text: $replyText)
                        .font(.system(size: 14))
                        .foregroundStyle(.white)
                        .tint(.white)

                    if !replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button {
                            sendReply(to: share)
                        } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 26))
                                .foregroundStyle(Color(red: 0.76, green: 0.38, blue: 0.35))
                        }
                        .disabled(isSendingReply)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.08))
                .clipShape(.capsule)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showSentConfirmation)
    }

    private func sendReply(to share: SongShare) {
        let text = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isSendingReply = true
        let capturedText = text
        replyText = ""

        Task {
            var success = false
            if let conv = await FirebaseService.shared.getOrCreateConversation(
                with: share.sender.id,
                friendName: share.sender.firstName
            ) {
                await appState.sendMessage(conversationId: conv.id, text: capturedText, song: song)
                success = true
            }
            isSendingReply = false
            if success {
                showSentConfirmation = true
                try? await Task.sleep(for: .seconds(1.5))
                showSentConfirmation = false
            }
        }
    }
}

// MARK: - Open in Service Button

@MainActor
func openInServiceButton(song: Song, service: MusicService, resolvedSpotifyURL: String? = nil) -> some View {
    Button {
        let url = externalURL(for: song, service: service, resolvedSpotifyURL: resolvedSpotifyURL)
        if let url {
            UIApplication.shared.open(url)
        }
    } label: {
        HStack(spacing: 6) {
            Image(systemName: "arrow.up.right")
                .font(.system(size: 11, weight: .semibold))
            Text(service == .spotify ? "Open in Spotify" : "Open in Apple Music")
                .font(.system(size: 13, weight: .medium))
        }
        .foregroundStyle(.white.opacity(0.6))
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.08))
        .clipShape(.capsule)
    }
}

private func externalURL(for song: Song, service: MusicService, resolvedSpotifyURL: String? = nil) -> URL? {
    switch service {
    case .appleMusic:
        if let appleMusicURL = song.appleMusicURL, let url = URL(string: appleMusicURL) {
            return url
        }
        let query = "\(song.title) \(song.artist)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "https://music.apple.com/search?term=\(query)")
    case .spotify:
        if let resolved = resolvedSpotifyURL, let url = URL(string: resolved) {
            return url
        }
        let query = "\(song.title) \(song.artist)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "https://open.spotify.com/search/\(query)")
    }
}
