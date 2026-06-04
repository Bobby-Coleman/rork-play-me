import SwiftUI

/// Locket-style viewer for a single calendar day's songs. Presented when a
/// day cell is tapped. Songs page horizontally (with the neighbors peeking
/// at the edges as a swipe cue) and a thumbnail strip at the bottom lets the
/// user jump between them. Each card is a full player: artwork, the sender's
/// avatar + the message they sent (no quotes), and a play / like / open /
/// send action row.
struct DayCarouselView: View {
    let shares: [SongShare]
    let appState: AppState
    var startIndex: Int = 0

    @Environment(\.dismiss) private var dismiss
    @State private var currentShareId: String?
    @State private var sendShare: SongShare?

    private var audioPlayer: AudioPlayerService { AudioPlayerService.shared }

    init(shares: [SongShare], appState: AppState, startIndex: Int = 0) {
        self.shares = shares
        self.appState = appState
        self.startIndex = startIndex
        let safe = min(max(0, startIndex), max(0, shares.count - 1))
        let seed = shares.indices.contains(safe) ? shares[safe].id : nil
        _currentShareId = State(initialValue: seed)
    }

    var body: some View {
        GeometryReader { geo in
            let cardWidth = max(0, geo.size.width - 80)

            ZStack(alignment: .top) {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    header
                        .padding(.top, 12)
                        .padding(.bottom, 18)

                    pager(cardWidth: cardWidth)

                    thumbnailStrip
                        .padding(.top, 16)
                        .padding(.bottom, 8)
                }

                closeButton
                    .padding(.top, 10)
                    .padding(.leading, 16)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { playCurrent() }
        .onChange(of: currentShareId) { _, _ in playCurrent() }
        .sheet(item: $sendShare) { share in
            SongActionSheet(song: share.song, appState: appState, share: share)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 2) {
            if let date = shares.first?.timestamp {
                Text(Self.yearFormatter.string(from: date))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
                Text(Self.dateFormatter.string(from: date))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 36, height: 36)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
        }
        .accessibilityLabel("Close")
    }

    // MARK: - Pager

    private func pager(cardWidth: CGFloat) -> some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 16) {
                ForEach(shares) { share in
                    card(share, width: cardWidth)
                        .frame(width: cardWidth)
                        .id(share.id)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $currentShareId)
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, 40, for: .scrollContent)
    }

    @ViewBuilder
    private func card(_ share: SongShare, width: CGFloat) -> some View {
        let song = share.song
        let trimmedNote = share.note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        VStack(spacing: 14) {
            if !trimmedNote.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    AppUserAvatar(user: share.sender, size: 26, background: Color.white.opacity(0.16))
                    Text(trimmedNote)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 4)
            }

            AlbumArtSquare(url: song.albumArtURL, cornerRadius: 22, showsShadow: true)
                .frame(width: width, height: width)
                .overlay(alignment: .topTrailing) {
                    likeButton(song: song, share: share)
                        .padding(12)
                }

            Text(share.timestamp, format: .dateTime.hour().minute())
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))

            VStack(spacing: 3) {
                Text(song.title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(song.artist)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)
            }

            actionRow(song: song, share: share)
        }
    }

    // MARK: - Actions

    private func likeButton(song: Song, share: SongShare) -> some View {
        let liked = appState.isLikedSong(song.id)
        return Button {
            appState.toggleLikeSong(song, share: share)
        } label: {
            Image(systemName: liked ? "heart.fill" : "heart")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(liked ? AnyShapeStyle(AppAccentGradient.button) : AnyShapeStyle(Color.white.opacity(0.85)))
                .padding(10)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: liked)
    }

    private func actionRow(song: Song, share: SongShare) -> some View {
        HStack(spacing: 12) {
            Button {
                audioPlayer.play(song: song)
                recordListenIfReceived(share, source: "preview")
            } label: {
                Image(systemName: isPlaying(song) ? "pause.fill" : "play.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .foregroundStyle(.black)
                    .frame(width: 52, height: 40)
                    .background(.white)
                    .clipShape(.capsule)
            }
            .sensoryFeedback(.impact(weight: .light), trigger: isPlaying(song))

            openInServiceButton(
                song: song,
                service: appState.preferredMusicService,
                shareId: share.id,
                onOpened: { recordListenIfReceived(share, source: "service") }
            )

            Button {
                sendShare = share
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.08))
                    .clipShape(.capsule)
            }
        }
    }

    // MARK: - Thumbnail strip

    private var thumbnailStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(shares) { share in
                        let isCurrent = share.id == currentShareId
                        Button {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                currentShareId = share.id
                            }
                        } label: {
                            AlbumArtSquare(
                                url: share.song.albumArtURL,
                                cornerRadius: 8,
                                showsPlaceholderProgress: false,
                                showsShadow: false,
                                targetDecodeSide: 60
                            )
                            .frame(width: 44, height: 44)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(AppAccentGradient.button, lineWidth: isCurrent ? 2.5 : 0)
                            )
                            .opacity(isCurrent ? 1 : 0.5)
                        }
                        .buttonStyle(.plain)
                        .id("thumb-\(share.id)")
                    }
                }
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)
            .onChange(of: currentShareId) { _, newValue in
                guard let newValue else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo("thumb-\(newValue)", anchor: .center)
                }
            }
        }
    }

    // MARK: - Helpers

    private func isPlaying(_ song: Song) -> Bool {
        audioPlayer.currentSongId == song.id && audioPlayer.isPlaying
    }

    private func playCurrent() {
        guard let id = currentShareId,
              let share = shares.first(where: { $0.id == id }) else { return }
        if audioPlayer.currentSongId != share.song.id {
            audioPlayer.play(song: share.song)
        }
        recordListenIfReceived(share, source: "preview")
    }

    private func recordListenIfReceived(_ share: SongShare, source: String) {
        guard let me = appState.currentUser?.id,
              share.recipient.id == me, share.sender.id != me else { return }
        Task { await FirebaseService.shared.markShareListened(shareId: share.id, source: source) }
    }

    // MARK: - Formatters

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM d"
        return f
    }()

    private static let yearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy"
        return f
    }()
}
