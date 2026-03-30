import SwiftUI

struct NowPlayingFullView: View {
    let player: AudioPlayerService
    @Environment(\.dismiss) private var dismiss

    @State private var isDragging: Bool = false
    @State private var dragProgress: Double = 0

    private var displayProgress: Double {
        isDragging ? dragProgress : player.progress
    }

    private var currentTimeString: String {
        let time = displayProgress * player.duration
        return formatTime(time)
    }

    private var remainingTimeString: String {
        let remaining = (1 - displayProgress) * player.duration
        return "-\(formatTime(remaining))"
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let song = player.currentSong {
                AsyncImage(url: URL(string: song.albumArtURL)) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .blur(radius: 60)
                .opacity(0.3)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }

            VStack(spacing: 0) {
                Capsule()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 36, height: 4)
                    .padding(.top, 10)
                    .padding(.bottom, 32)

                if let song = player.currentSong {
                    Color.clear
                        .frame(maxWidth: .infinity)
                        .frame(height: UIScreen.main.bounds.width - 64)
                        .overlay {
                            AsyncImage(url: URL(string: song.albumArtURL)) { phase in
                                if let image = phase.image {
                                    image.resizable().aspectRatio(contentMode: .fill)
                                } else {
                                    Color(.systemGray5)
                                }
                            }
                            .allowsHitTesting(false)
                        }
                        .clipShape(.rect(cornerRadius: 12))
                        .shadow(color: .black.opacity(0.4), radius: 24, y: 12)
                        .padding(.horizontal, 32)
                        .padding(.bottom, 32)

                    VStack(spacing: 4) {
                        Text(song.title)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(song.artist)
                            .font(.system(size: 16))
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 24)

                    VStack(spacing: 4) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.white.opacity(0.15))
                                    .frame(height: 4)

                                Capsule()
                                    .fill(Color.white)
                                    .frame(width: max(0, geo.size.width * displayProgress), height: 4)
                            }
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        isDragging = true
                                        dragProgress = min(max(value.location.x / geo.size.width, 0), 1)
                                    }
                                    .onEnded { value in
                                        let final = min(max(value.location.x / geo.size.width, 0), 1)
                                        player.seek(to: final)
                                        isDragging = false
                                    }
                            )
                        }
                        .frame(height: 4)

                        HStack {
                            Text(currentTimeString)
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.4))
                            Spacer()
                            Text(remainingTimeString)
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 32)

                    HStack(spacing: 48) {
                        Button {
                            player.seek(to: 0)
                        } label: {
                            Image(systemName: "backward.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(.white)
                        }

                        Button {
                            player.togglePlayPause()
                        } label: {
                            Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 64))
                                .foregroundStyle(.white)
                                .contentTransition(.symbolEffect(.replace))
                        }
                        .sensoryFeedback(.impact(weight: .medium), trigger: player.isPlaying)

                        Button {
                            player.stop()
                            dismiss()
                        } label: {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(.white)
                        }
                    }
                    .padding(.bottom, 32)

                    if song.spotifyID != nil {
                        Button {
                            player.openInSpotify(song: song)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.up.right.circle.fill")
                                    .font(.system(size: 16))
                                Text("Open in Spotify")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .foregroundStyle(Color(red: 0.11, green: 0.73, blue: 0.33))
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Color(red: 0.11, green: 0.73, blue: 0.33).opacity(0.15))
                            .clipShape(.capsule)
                        }
                    }
                }

                Spacer()
            }
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return "\(mins):\(String(format: "%02d", secs))"
    }
}
