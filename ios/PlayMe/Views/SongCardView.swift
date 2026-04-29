import SwiftUI

struct SongCardView: View {
    let share: SongShare
    let isLiked: Bool
    let appState: AppState
    let onToggleLike: () -> Void

    private var audioPlayer: AudioPlayerService { AudioPlayerService.shared }
    @State private var resolvedSpotifyURL: String?
    @State private var showShareFlow: Bool = false
    @State private var showSaveSheet: Bool = false
    @State private var reportTarget: ReportTarget?
    @State private var showReportedToast: Bool = false
    @State private var pendingBlock: AppUser?
    @State private var isNoteExpanded: Bool = false
    @State private var chatTarget: Conversation?
    @State private var isOpeningChat: Bool = false
    @State private var showDetailSheet: Bool = false
    @State private var showArtistView: Bool = false
    /// Resolved MusicKit artist id used when `share.song.artistId` is
    /// nil (legacy shares). Populated on-demand from the artist name
    /// when the user taps the byline so the artist page still opens
    /// for older data.
    @State private var resolvedArtistId: String?
    @State private var isResolvingArtist: Bool = false
    /// Measured height of the content above the artwork (header block).
    /// Updated in-place via a `PreferenceKey` probe so the art size
    /// recomputes when Dynamic Type or localized strings change the
    /// header's rendered size.
    @State private var topBlockHeight: CGFloat = 68
    /// Measured height of the content below the artwork (sender row +
    /// player controls).
    @State private var bottomBlockHeight: CGFloat = 140

    private var isCurrentSong: Bool {
        audioPlayer.currentSongId == share.song.id
    }

    private var isPlayingThis: Bool {
        isCurrentSong && audioPlayer.isPlaying
    }

    /// True when the current user is the sender of this share. Kept so a
    /// sent song never prompts a self-reply via the chat affordance below.
    private var viewerIsSender: Bool {
        guard let me = appState.currentUser?.id else { return false }
        return share.sender.id == me
    }

    private var headerLabel: String {
        if viewerIsSender {
            return "YOU SENT \(share.recipient.firstName.uppercased()) A SONG"
        } else {
            return "\(share.sender.firstName.uppercased()) SENT YOU A SONG"
        }
    }

    /// Full "First Last" for the sender; falls back to first name when the last name is missing.
    private var senderFullName: String {
        let trimmedLast = share.sender.lastName.trimmingCharacters(in: .whitespaces)
        if trimmedLast.isEmpty { return share.sender.firstName }
        return "\(share.sender.firstName) \(trimmedLast)"
    }

    var body: some View {
        GeometryReader { proxy in
            let nonArt = topBlockHeight + bottomBlockHeight
            let artSize = FeedLayout.artSize(forPageSize: proxy.size, nonArtHeight: nonArt)

            ZStack {
                Color.black

                // Symmetric flexible spacers geometrically center the
                // content within the page. The page size is the scroll
                // container's visible region (see `DiscoveryView`'s
                // top + bottom safe-area insets), so there's no need
                // for an asymmetric bottom padding to "push content up
                // above the reply pill" — the reply pill lives outside
                // the page entirely.
                VStack(spacing: 0) {
                    Spacer(minLength: 0)

                    header
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                        .padding(.horizontal, 24)
                        .background(heightProbe(TopBlockHeightKey.self))

                    artwork(size: artSize)

                    VStack(spacing: 0) {
                        senderDateRow
                            .padding(.top, 20)
                            .padding(.bottom, 12)

                        playerControls
                            .padding(.horizontal, 32)
                            .padding(.bottom, 12)
                    }
                    .background(heightProbe(BottomBlockHeightKey.self))

                    Spacer(minLength: 0)
                }
            }
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
                // View-time prefetch for the "Open in Spotify" pill.
                // `resolveSpotifyURL` is cache-first (local → Firestore
                // global) and only hits the network on true cache
                // misses — which, after catalog warm-up, is a rounding
                // error. Our Cloud Function path has an app-wide rate
                // pool (not per-IP), so it's safe to fire this on every
                // card that scrolls by. Result: the tap handoff is
                // instant because the URL is already cached locally.
                guard appState.preferredMusicService == .spotify,
                      share.song.spotifyURI == nil,
                      let amURL = share.song.appleMusicURL else { return }

                let resolved = await MusicSearchService.shared.resolveSpotifyURL(
                    appleMusicURL: amURL,
                    title: share.song.title,
                    artist: share.song.artist
                )
                resolvedSpotifyURL = resolved
                // Per-share writeback: lets the NEXT viewer of THIS
                // specific share skip even the Firestore cache lookup
                // (the URI ships embedded in the share doc itself).
                // The global `spotifyResolutions` cache is already
                // populated by `resolveSpotifyURL`.
                if let resolved,
                   let trackID = SpotifyDeepLinkResolver.spotifyTrackID(fromSpotifyURL: resolved) {
                    let uri = "spotify:track:\(trackID)"
                    print("event=open_in_spotify firestore_writeback source=prefetch shareId=\(share.id) uri=\(uri)")
                    await FirebaseService.shared.patchShareSpotifyURI(shareId: share.id, spotifyURI: uri)
                }
            }
            .sheet(isPresented: $showShareFlow) {
                NavigationStack {
                    FriendSelectorView(
                        item: .song(share.song),
                        appState: appState,
                        shareId: share.id,
                        onBack: { showShareFlow = false },
                        onSent: { showShareFlow = false }
                    )
                }
                .presentationBackground(.black)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .sheet(item: $reportTarget) { target in
                ReportSheet(target: target, appState: appState) {
                    withAnimation { showReportedToast = true }
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        withAnimation { showReportedToast = false }
                    }
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .sheet(item: $chatTarget) { conv in
                NavigationStack {
                    ChatView(conversation: conv, appState: appState)
                }
                .presentationBackground(.black)
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showDetailSheet) {
                SongActionSheet(song: share.song, appState: appState, share: share)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showSaveSheet) {
                SaveToMixtapeSheet(song: share.song, appState: appState)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showArtistView) {
                if let aid = share.song.artistId ?? resolvedArtistId {
                    ArtistView(artistId: aid, initialArtistName: share.song.artist, appState: appState)
                        .presentationDetents([.large])
                        .presentationDragIndicator(.visible)
                }
            }
            .overlay(alignment: .top) {
                if showReportedToast {
                    Text("Report submitted. Thanks.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.black.opacity(0.9))
                        .clipShape(.capsule)
                        .padding(.top, 40)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .alert("Block \(pendingBlock?.firstName ?? "user")?", isPresented: blockAlertBinding) {
                Button("Cancel", role: .cancel) { pendingBlock = nil }
                Button("Block", role: .destructive) {
                    if let user = pendingBlock {
                        Task { await appState.blockUser(user) }
                    }
                    pendingBlock = nil
                }
            } message: {
                Text("They won't be able to send you songs or messages, and you won't see their content.")
            }
        }
    }

    private var blockAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingBlock != nil },
            set: { if !$0 { pendingBlock = nil } }
        )
    }

    // MARK: - Header (label + inline title/artist)

    private var header: some View {
        VStack(spacing: 4) {
            Text(headerLabel)
                .font(.system(size: 12, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)

            HStack(spacing: 0) {
                Button {
                    showDetailSheet = true
                } label: {
                    Text(share.song.title)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                Text("  \u{00B7}  ")
                    .foregroundStyle(.white.opacity(0.4))

                Button {
                    openArtistPage()
                } label: {
                    Text(share.song.artist)
                        .foregroundStyle(.white.opacity(0.9))
                }
                .buttonStyle(.plain)
                .disabled(isResolvingArtist)
            }
            .font(.system(size: 17))
            .lineLimit(1)
            .truncationMode(.tail)
            .multilineTextAlignment(.center)
        }
    }

    // MARK: - Artwork

    private func artwork(size: CGFloat) -> some View {
        AlbumArtSquare(url: share.song.albumArtURL, showsShadow: false)
            .frame(width: size, height: size)
            .contentShape(Rectangle())
            .onTapGesture {
                showDetailSheet = true
            }
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
            .overlay(alignment: .topLeading) {
                if !viewerIsSender {
                    Menu {
                        Button(role: .destructive) {
                            pendingBlock = share.sender
                        } label: {
                            Label("Block \(share.sender.firstName)", systemImage: "hand.raised.fill")
                        }
                        Button {
                            reportTarget = .share(share)
                        } label: {
                            Label("Report song", systemImage: "flag.fill")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(10)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                    .padding(12)
                }
            }
            .overlay(alignment: .bottom) {
                if let note = share.note, !note.isEmpty {
                    Text(note)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(isNoteExpanded ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.horizontal, 16)
                        .padding(.bottom, 20)
                        .onTapGesture {
                            if note.count > 80 {
                                withAnimation(.easeInOut(duration: 0.2)) { isNoteExpanded.toggle() }
                            }
                        }
                }
            }
            .shadow(color: .white.opacity(0.05), radius: 20, y: 10)
    }

    // MARK: - Sender row (tap to open chat)

    private var senderDateRow: some View {
        Button {
            openChatWithSender()
        } label: {
            HStack(spacing: 6) {
                // Sender name is tappable (opens chat); render it in a
                // noticeably brighter white than the surrounding
                // metadata so it reads as an affordance rather than
                // dim caption text.
                Text(viewerIsSender ? "You" : senderFullName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
                Text("\u{00B7}")
                    .foregroundStyle(.white.opacity(0.5))
                Text(share.timestamp, format: .dateTime.month(.abbreviated).day())
                    .foregroundStyle(.white.opacity(0.5))
            }
            .font(.system(size: 13))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(viewerIsSender || isOpeningChat)
    }

    /// Opens the artist profile sheet. Uses the song's stored
    /// `artistId` when present; falls back to a MusicKit search keyed
    /// by artist name for legacy shares that pre-date the stored id.
    /// Shows the sheet synchronously on the fast path so the tap
    /// feels immediate; only spends a round-trip on the (rare)
    /// unresolved case.
    private func openArtistPage() {
        if share.song.artistId != nil {
            showArtistView = true
            return
        }
        if let cached = resolvedArtistId, !cached.isEmpty {
            showArtistView = true
            return
        }
        guard !isResolvingArtist else { return }
        isResolvingArtist = true
        Task {
            let resolved = await AppleMusicSearchService.shared.resolveArtistId(name: share.song.artist)
            if let resolved, !resolved.isEmpty {
                resolvedArtistId = resolved
                showArtistView = true
            }
            isResolvingArtist = false
        }
    }

    private func openChatWithSender() {
        guard !viewerIsSender, !isOpeningChat else { return }
        let user = share.sender
        if let me = appState.currentUser?.id, user.id == me { return }
        isOpeningChat = true
        Task {
            if let conv = await FirebaseService.shared.getOrCreateConversation(
                with: user.id,
                friendName: user.firstName
            ) {
                chatTarget = conv
            }
            isOpeningChat = false
        }
    }

    // MARK: - Player controls

    private var playerControls: some View {
        VStack(spacing: 8) {
            ScrubBarView(songId: share.song.id, fallbackDuration: share.song.duration)
                .padding(.bottom, 2)

            HStack(spacing: 12) {
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

                openInServiceButton(song: share.song, service: appState.preferredMusicService, resolvedSpotifyURL: resolvedSpotifyURL, shareId: share.id)

                Button {
                    showSaveSheet = true
                } label: {
                    Image(systemName: appState.saveService.isSaved(songId: share.song.id) ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(appState.saveService.isSaved(songId: share.song.id) ? 0.9 : 0.6))
                        .frame(width: 40, height: 40)
                        .background(Color.white.opacity(0.08))
                        .clipShape(.capsule)
                }
                .sensoryFeedback(.selection, trigger: appState.saveService.isSaved(songId: share.song.id))

                Button {
                    showShareFlow = true
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 40, height: 40)
                        .background(Color.white.opacity(0.08))
                        .clipShape(.capsule)
                }
            }

            if let error = audioPlayer.error,
               audioPlayer.currentSongId == nil || audioPlayer.currentSongId == share.song.id {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.top, 4)
            }
        }
    }

    // MARK: - Height probe

    /// Transparent `GeometryReader` background that publishes the host
    /// view's rendered height through the supplied `PreferenceKey`. Used
    /// by `SongCardView` to discover the real size of the top/bottom
    /// non-art blocks and size the artwork to the leftover space.
    private func heightProbe<Key: PreferenceKey>(_ key: Key.Type) -> some View where Key.Value == CGFloat {
        GeometryReader { geo in
            Color.clear.preference(key: key, value: geo.size.height)
        }
    }
}

private struct TopBlockHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 68
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

// MARK: - ScrubBarView (isolated progress observation)

struct ScrubBarView: View {
    let songId: String
    let fallbackDuration: String

    private var audioPlayer: AudioPlayerService { AudioPlayerService.shared }
    private var progressModel: PlayerProgressModel { AudioPlayerService.shared.progressModel }
    @State private var isScrubbing: Bool = false
    @State private var scrubValue: Double = 0

    private var isCurrentSong: Bool {
        audioPlayer.currentSongId == songId
    }

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                let width = geo.size.width
                let progressValue = isScrubbing ? scrubValue : (isCurrentSong ? progressModel.progress : 0)

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
                                let seekTime = fraction * progressModel.duration
                                audioPlayer.seek(to: seekTime)
                            }
                            isScrubbing = false
                        }
                )
            }
            .frame(height: 14)

            HStack {
                Text(isCurrentSong ? progressModel.formattedTime(progressModel.currentTime) : "0:00")
                    .monospacedDigit()
                Spacer()
                Text(isCurrentSong && progressModel.duration > 0 ? progressModel.formattedTime(progressModel.duration) : (fallbackDuration.isEmpty ? "0:30" : fallbackDuration))
                    .monospacedDigit()
            }
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.4))
        }
    }
}
