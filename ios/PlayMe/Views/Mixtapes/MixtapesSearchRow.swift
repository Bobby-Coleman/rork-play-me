import SwiftUI

/// Slim list row for `Song`-only search results in `MixtapesView` (e.g.
/// a song saved into a mixtape that doesn't have an associated
/// `SongShare`). Mirrors `ProfileSongRow`'s art / title / caption layout
/// so the unified search list reads as one consistent list — but drops
/// the heart button (no share id to like against) and the trailing
/// timestamp (no share metadata).
struct MixtapesSearchRow: View {
    let song: Song
    /// Caller-provided context label rendered under the song title —
    /// e.g. "From mixtape: Workout". Kept generic so the row doesn't
    /// need to know about mixtape vs. share semantics.
    let contextLabel: String
    let onTap: () -> Void

    private var audioPlayer: AudioPlayerService { AudioPlayerService.shared }

    private var isPlaying: Bool {
        audioPlayer.currentSongId == song.id && audioPlayer.isPlaying
    }

    private var isLoading: Bool {
        audioPlayer.currentSongId == song.id && audioPlayer.isLoading
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Color(.systemGray5)
                    .frame(width: 48, height: 48)
                    .overlay {
                        AsyncImage(url: URL(string: song.albumArtURL)) { phase in
                            if let image = phase.image {
                                image.resizable().aspectRatio(contentMode: .fill)
                            }
                        }
                        .allowsHitTesting(false)
                    }
                    .clipShape(.rect(cornerRadius: 6))

                Button {
                    audioPlayer.play(song: song)
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
                Text(song.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(contextLabel)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
    }
}
