import SwiftUI

struct SongCardView: View {
    let share: SongShare
    let isLiked: Bool
    let onSendBack: () -> Void
    let onToggleLike: () -> Void

    @State private var audioPlayer: AudioPlayerService = .shared
    @State private var isScrubbing: Bool = false
    @State private var scrubValue: Double = 0

    private var isCurrentSong: Bool {
        audioPlayer.currentSongId == share.song.id
    }

    private var isPlayingThis: Bool {
        isCurrentSong && audioPlayer.isPlaying
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                VStack(spacing: 4) {
                    Text("\(share.sender.firstName.uppercased()) SENT YOU A SONG")
                        .font(.system(size: 12, weight: .bold))
                        .tracking(1.5)
                        .foregroundStyle(.white.opacity(0.5))

                    Text(share.song.title)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)

                    Text(share.song.artist)
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .padding(.top, 16)
                .padding(.bottom, 20)

                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: UIScreen.main.bounds.width - 48)
                    .overlay {
                        AsyncImage(url: URL(string: share.song.albumArtURL)) { phase in
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
                        Button {
                            onToggleLike()
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
                    .shadow(color: .white.opacity(0.05), radius: 20, y: 10)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)

                if let note = share.note {
                    Text("\"\(note)\"")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.7))
                        .italic()
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.bottom, 12)
                }

                playerControls
                    .padding(.horizontal, 32)
                    .padding(.bottom, 12)

                Button(action: onSendBack) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 13))
                        Text("Send a song back?")
                            .font(.system(size: 14))
                    }
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.08))
                    .clipShape(.capsule)
                }
                .padding(.bottom, 24)
            }
        }
    }

    private var playerControls: some View {
        VStack(spacing: 8) {
            scrubBar
                .padding(.bottom, 2)

            HStack(spacing: 16) {
                Button {
                    audioPlayer.play(song: share.song)
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

                if share.song.spotifyURI != nil {
                    Button {
                        if let uri = share.song.spotifyURI, let url = URL(string: uri) {
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

            if audioPlayer.noPreviewAvailable && (audioPlayer.currentSongId == nil || audioPlayer.currentSongId == share.song.id) {
                Text("Preview unavailable — tap Open in Spotify")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.top, 4)
            }
        }
    }

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
                Text(isCurrentSong && audioPlayer.duration > 0 ? audioPlayer.formattedTime(audioPlayer.duration) : (share.song.duration.isEmpty ? "0:30" : share.song.duration))
                    .monospacedDigit()
            }
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.4))
        }
    }
}
