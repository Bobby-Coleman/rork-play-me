import SwiftUI

/// Persistent mini player that anchors to the bottom of the main tab view
/// whenever `AudioPlayerService.shared.currentSong` is non-nil. Tapping the
/// body opens the detail sheet, the play/pause button toggles playback
/// without tearing down the player, and the X dismisses by calling `stop()`.
struct MiniPlayerBar: View {
    let song: Song
    let onTap: () -> Void

    @Environment(\.riffTheme) private var theme
    private let audioPlayer = AudioPlayerService.shared

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onTap) {
                HStack(spacing: 12) {
                    AsyncImage(url: URL(string: song.albumArtURL)) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().aspectRatio(contentMode: .fill)
                        default:
                            theme.fg.opacity(0.12)
                        }
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(.rect(cornerRadius: 6, style: .continuous))

                    VStack(alignment: .leading, spacing: 1) {
                        Text(song.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(theme.fg)
                            .lineLimit(1)
                        Text(song.artist)
                            .font(.system(size: 12))
                            .foregroundStyle(theme.fg.opacity(0.55))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                if audioPlayer.isPlaying {
                    audioPlayer.pause()
                } else {
                    audioPlayer.play(song: song)
                }
            } label: {
                Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(theme.fg)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                audioPlayer.stop()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(theme.fg.opacity(0.75))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(theme.border, lineWidth: 0.5)
        )
        .shadow(color: theme.bg.opacity(0.35), radius: 10, x: 0, y: 4)
    }
}
