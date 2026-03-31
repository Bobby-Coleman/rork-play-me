import SwiftUI

struct SongDetailSheet: View {
    let song: Song
    let appState: AppState
    var share: SongShare?
    var onDismiss: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var audioPlayer: AudioPlayerService = .shared
    @State private var isScrubbing: Bool = false
    @State private var scrubValue: Double = 0
    @State private var showShareFlow: Bool = false

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
            scrubBar
                .padding(.bottom, 2)

            HStack(spacing: 16) {
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

                if song.spotifyURI != nil {
                    Button {
                        if let uri = song.spotifyURI, let url = URL(string: uri) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Open in Spotify")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.08))
                        .clipShape(.capsule)
                    }
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

    // MARK: - Scrub Bar

    private var scrubBar: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                let width = geo.size.width
                let progressValue = isScrubbing ? scrubValue : (isCurrentSong ? audioPlayer.progress : 0)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.15))
                        .frame(height: 4)

                    Capsule()
                        .fill(Color.white.opacity(0.9))
                        .frame(width: max(0, width * progressValue), height: 4)

                    Circle()
                        .fill(.white)
                        .frame(width: isScrubbing ? 14 : 10, height: isScrubbing ? 14 : 10)
                        .offset(x: max(0, min(width * progressValue - (isScrubbing ? 7 : 5), width - (isScrubbing ? 14 : 10))))
                        .animation(.spring(duration: 0.2), value: isScrubbing)
                }
                .frame(height: 14)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isScrubbing = true
                            let fraction = max(0, min(1, value.location.x / width))
                            scrubValue = fraction
                        }
                        .onEnded { value in
                            let fraction = max(0, min(1, value.location.x / width))
                            if isCurrentSong {
                                let seekTime = fraction * audioPlayer.duration
                                audioPlayer.seek(to: seekTime)
                            }
                            isScrubbing = false
                        }
                )
            }
            .frame(height: 14)

            HStack {
                Text(isCurrentSong ? audioPlayer.formattedTime(audioPlayer.currentTime) : "0:00")
                    .monospacedDigit()
                Spacer()
                Text(isCurrentSong && audioPlayer.duration > 0 ? audioPlayer.formattedTime(audioPlayer.duration) : (song.duration.isEmpty ? "0:30" : song.duration))
                    .monospacedDigit()
            }
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.4))
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        Button {
            showShareFlow = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 13))
                Text("Share this song")
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Color(red: 0.76, green: 0.38, blue: 0.35))
            .clipShape(.capsule)
        }
        .sensoryFeedback(.impact(weight: .light), trigger: showShareFlow)
    }
}
