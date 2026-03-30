import SwiftUI

struct SongCardView: View {
    let share: SongShare
    let isLiked: Bool
    let player: AudioPlayerService
    let onSendBack: () -> Void
    let onToggleLike: () -> Void

    private var isThisSongPlaying: Bool {
        player.currentSong?.id == share.song.id && player.isPlaying
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
                    .overlay(alignment: .center) {
                        if share.song.previewURL != nil {
                            Button {
                                player.play(song: share.song)
                            } label: {
                                Image(systemName: isThisSongPlaying ? "pause.circle.fill" : "play.circle.fill")
                                    .font(.system(size: 56))
                                    .foregroundStyle(.white)
                                    .shadow(color: .black.opacity(0.5), radius: 12)
                                    .contentTransition(.symbolEffect(.replace))
                            }
                            .sensoryFeedback(.impact(weight: .medium), trigger: isThisSongPlaying)
                        }
                    }
                    .shadow(color: .white.opacity(0.05), radius: 20, y: 10)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)

                if let note = share.note {
                    Text("\"\(note)\"")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.7))
                        .italic()
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.bottom, 16)
                }

                HStack(spacing: 12) {
                    if share.song.previewURL != nil {
                        Button {
                            player.play(song: share.song)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: isThisSongPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 13))
                                    .contentTransition(.symbolEffect(.replace))
                                Text(isThisSongPlaying ? "Pause" : "Play")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .foregroundStyle(.black)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(.white)
                            .clipShape(.capsule)
                        }
                        .sensoryFeedback(.impact(weight: .light), trigger: isThisSongPlaying)
                    }

                    if share.song.spotifyID != nil {
                        Button {
                            player.openInSpotify(song: share.song)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 12, weight: .bold))
                                Text("Spotify")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundStyle(Color(red: 0.11, green: 0.73, blue: 0.33))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(Color(red: 0.11, green: 0.73, blue: 0.33).opacity(0.15))
                            .clipShape(.capsule)
                        }
                    }
                }
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
}
