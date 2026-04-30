import SwiftUI

/// Shared list row used by the Sent / Received / Liked segments of the
/// Mixtapes screen. Lifted out of `ProfileView` verbatim (modulo
/// visibility) so the new `MixtapesView` reuses the existing layout — the
/// spec calls for those tabs to be visually unchanged from the old
/// Profile.
///
/// Tap behavior is deliberately abstracted via `onTap`: the old
/// `ProfileView` opens a `SongActionSheet` while the new `MixtapesView`
/// opens the TikTok-style `SongFullScreenFeedView`. Both flows route the
/// tap through this row without leaking either presentation choice into
/// the row itself.
struct ProfileSongRow: View {
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

    private var trimmedNote: String? {
        let note = (share.note ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return note.isEmpty ? nil : note
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
                    .lineLimit(1)
                if let trimmedNote {
                    HStack(spacing: 5) {
                        Image(systemName: "quote.opening")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white.opacity(0.35))
                        Text(trimmedNote)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.62))
                            .lineLimit(2)
                    }
                    .padding(.top, 1)
                }
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
        .padding(.vertical, trimmedNote == nil ? 10 : 12)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
    }
}
