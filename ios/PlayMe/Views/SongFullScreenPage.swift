import SwiftUI

/// One full-height page in the TikTok-style fullscreen song feed. Sized
/// to the page geometry handed in by `SongFullScreenFeedView` so every
/// device shows the same hero artwork + action row composition without
/// the snap distance disagreeing with the page height (the same
/// `containerRelativeFrame` vs `safeAreaInset` pitfall called out in
/// `DiscoveryView`).
///
/// Action row order: `Play | Open in Spotify | Save | Send`. The Send
/// capsule keeps its existing emphasized treatment (white-on-black) so it
/// remains visually primary; Save and Play sit at the same low-contrast
/// weight so the action row reads "primary CTA + supporting actions"
/// rather than "four equal pills".
///
/// The Like overlay (heart) only renders when the page was seeded from a
/// `SongShare` so the action stays tied to the existing per-share like
/// model. Song-only sources (Discover feed, Mixtapes Songs grid) hide it
/// — those songs don't have a share id to like against.
struct SongFullScreenPage: View {
    let song: Song
    let pageSize: CGSize
    let appState: AppState
    /// Optional share context so this page can preserve the per-share Like
    /// model when seeded from a feed entry. `nil` when seeded from a
    /// Discover grid tap or a Mixtape song row.
    var share: SongShare? = nil

    @State private var resolvedSpotifyURL: String?
    @State private var showSendSheet: Bool = false
    @State private var showSaveSheet: Bool = false
    @State private var topBlockHeight: CGFloat = 60
    @State private var bottomBlockHeight: CGFloat = 140

    private var audioPlayer: AudioPlayerService { AudioPlayerService.shared }
    private var saveService: SaveService { appState.saveService }

    private var isCurrentSong: Bool { audioPlayer.currentSongId == song.id }
    private var isPlayingThis: Bool { isCurrentSong && audioPlayer.isPlaying }
    private var isSaved: Bool { saveService.isSaved(songId: song.id) }
    private var shareIsLiked: Bool {
        guard let id = share?.id else { return false }
        return appState.isLiked(shareId: id)
    }

    var body: some View {
        let nonArt = topBlockHeight + bottomBlockHeight
        let artSize = FeedLayout.artSize(forPageSize: pageSize, nonArtHeight: nonArt)

        ZStack {
            Color.black

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                header
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                    .padding(.horizontal, 24)
                    .background(heightProbe(TopBlockHeightKey.self))

                artwork(size: artSize)

                VStack(spacing: 0) {
                    ScrubBarView(songId: song.id, fallbackDuration: song.duration)
                        .padding(.top, 20)
                        .padding(.horizontal, 32)
                        .padding(.bottom, 14)

                    actionRow
                        .padding(.horizontal, 32)
                        .padding(.bottom, 12)
                }
                .background(heightProbe(BottomBlockHeightKey.self))

                Spacer(minLength: 0)
            }
        }
        .frame(width: pageSize.width, height: pageSize.height)
        .onPreferenceChange(TopBlockHeightKey.self) { newValue in
            if abs(newValue - topBlockHeight) > 0.5 {
                topBlockHeight = newValue
            }
        }
        .onPreferenceChange(BottomBlockHeightKey.self) { newValue in
            if abs(newValue - bottomBlockHeight) > 0.5 {
                bottomBlockHeight = newValue
            }
        }
        .task {
            // Mirror SongCardView: pre-resolve the Spotify URL so the
            // Open-in-Spotify pill hands off instantly. Skipped when the
            // song already has a Spotify URI, when Apple Music is the
            // user's preferred service, or when there's no Apple Music
            // URL to translate from.
            guard appState.preferredMusicService == .spotify,
                  song.spotifyURI == nil,
                  let amURL = song.appleMusicURL else { return }
            resolvedSpotifyURL = await MusicSearchService.shared.resolveSpotifyURL(
                appleMusicURL: amURL,
                title: song.title,
                artist: song.artist
            )
        }
        .sheet(isPresented: $showSendSheet) {
            SongActionSheet(song: song, appState: appState, share: share)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showSaveSheet) {
            SaveToMixtapeSheet(song: song, appState: appState)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Header (title / artist)

    private var header: some View {
        VStack(spacing: 4) {
            HStack(spacing: 0) {
                Text(song.title)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                Text("  \u{00B7}  ")
                    .foregroundStyle(.white.opacity(0.4))
                Text(song.artist)
                    .foregroundStyle(.white.opacity(0.9))
            }
            .font(.system(size: 17))
            .lineLimit(1)
            .truncationMode(.tail)
            .multilineTextAlignment(.center)
        }
    }

    // MARK: - Artwork

    private func artwork(size: CGFloat) -> some View {
        AlbumArtSquare(url: song.albumArtURL, showsShadow: false)
            .frame(width: size, height: size)
            .overlay(alignment: .topTrailing) {
                if let shareId = share?.id {
                    Button {
                        appState.toggleLike(shareId: shareId)
                    } label: {
                        Image(systemName: shareIsLiked ? "heart.fill" : "heart")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(shareIsLiked ? .pink : .white.opacity(0.8))
                            .padding(10)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                    .sensoryFeedback(.impact(weight: .medium), trigger: shareIsLiked)
                    .padding(12)
                }
            }
            .shadow(color: .white.opacity(0.05), radius: 20, y: 10)
    }

    // MARK: - Action row

    private var actionRow: some View {
        HStack(spacing: 12) {
            playButton
            openInServiceButton(
                song: song,
                service: appState.preferredMusicService,
                resolvedSpotifyURL: resolvedSpotifyURL,
                shareId: share?.id
            )
            saveButton
            sendButton
        }
    }

    private var playButton: some View {
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
    }

    private var saveButton: some View {
        Button {
            showSaveSheet = true
        } label: {
            Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(isSaved ? 0.9 : 0.6))
                .frame(width: 40, height: 40)
                .background(Color.white.opacity(0.08))
                .clipShape(.capsule)
        }
        .sensoryFeedback(.selection, trigger: isSaved)
    }

    private var sendButton: some View {
        Button {
            showSendSheet = true
        } label: {
            Image(systemName: "paperplane.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 40, height: 40)
                .background(Color.white.opacity(0.08))
                .clipShape(.capsule)
        }
    }

    // MARK: - Height probes

    private func heightProbe<Key: PreferenceKey>(_ key: Key.Type) -> some View where Key.Value == CGFloat {
        GeometryReader { geo in
            Color.clear.preference(key: key, value: geo.size.height)
        }
    }
}

private struct TopBlockHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 60
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct BottomBlockHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 140
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
