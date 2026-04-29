import SwiftUI

/// Top-level segments of the Mixtapes tab. Order matches the spec:
/// Songs | Mixtapes (default) | Sent | Received | Liked.
enum MixtapesSegment: String, CaseIterable, Identifiable {
    case songs = "Songs"
    case mixtapes = "Mixtapes"
    case sent = "Sent"
    case received = "Received"
    case liked = "Liked"

    var id: String { rawValue }
}

/// Layout mode for any single Mixtapes segment. Persisted per segment
/// in `@AppStorage` keys keyed off the segment name so each segment
/// remembers its preference independently — defaults differ
/// per-segment (Songs/Mixtapes default to grid; Sent/Received/Liked
/// default to list).
enum MixtapesViewMode: String { case grid, list }

/// Replaces the old `ProfileView` as the rightmost tab. Five segments
/// share a single search bar (filters the visible segment's data) and a
/// single tap target — all songs route to `SongFullScreenFeedView` so the
/// playback model is identical regardless of which segment the user
/// taps from.
///
/// Toolbar layout matches the spec:
///   * top-leading → small profile button (initials)
///   * top-trailing → settings gear
struct MixtapesView: View {
    @Bindable var appState: AppState

    @State private var selectedSegment: MixtapesSegment = .mixtapes
    @State private var searchText: String = ""
    @State private var showSettings: Bool = false
    @State private var showProfileDetails: Bool = false
    @State private var fullscreenSeed: FullscreenSeed?
    @State private var detailMixtape: Mixtape?
    /// Inbound mixtape share to push into the read-only detail view.
    @State private var detailReceivedMixtape: MixtapeShare?
    /// Inbound album share to push into the read-only detail view.
    @State private var detailReceivedAlbum: AlbumShare?
    /// Focus binding for the "Search your songs" field. Drives both
    /// Return-key dismissal (via `onSubmit`) and any future programmatic
    /// dismiss points (e.g. tapping a result row) without round-tripping
    /// through `UIApplication.shared.endEditing`.
    @FocusState private var isSearchFocused: Bool

    // Per-segment grid/list mode preferences. Defaults match the spec:
    // Songs and Mixtapes start in grid; Sent / Received / Liked start
    // in list. Each segment's toggle writes to its own key so a user
    // who flips one tab to grid doesn't disturb the others.
    @AppStorage("mixtapes.viewMode.songs")    private var songsModeRaw    = MixtapesViewMode.grid.rawValue
    @AppStorage("mixtapes.viewMode.mixtapes") private var mixtapesModeRaw = MixtapesViewMode.grid.rawValue
    @AppStorage("mixtapes.viewMode.sent")     private var sentModeRaw     = MixtapesViewMode.list.rawValue
    @AppStorage("mixtapes.viewMode.received") private var receivedModeRaw = MixtapesViewMode.list.rawValue
    @AppStorage("mixtapes.viewMode.liked")    private var likedModeRaw    = MixtapesViewMode.list.rawValue

    private var user: AppUser? { appState.currentUser }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    searchBar
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 12)

                    segmentPicker
                        .padding(.bottom, 4)

                    // Section header sits between the segment chips and
                    // the content. It owns the grid/list toggle so the
                    // toggle has proper breathing room — the segment
                    // strip used to host it inline, which got crowded
                    // once five chips needed to scroll horizontally.
                    sectionHeaderBar
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 6)

                    contentForSegment
                }
                // Propagates to every descendant `ScrollView` (segment
                // grids, segment lists, search-results list, share
                // feeds), so dragging any list down past its content
                // edge interactively dismisses the search keyboard.
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showProfileDetails = true
                    } label: {
                        Text(user?.initials ?? "?")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(Color.white.opacity(0.15))
                            .clipShape(Circle())
                    }
                    .accessibilityLabel("Profile")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 17))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.black, for: .navigationBar)
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsView(appState: appState)
            }
            .presentationBackground(.black)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showProfileDetails) {
            ProfileDetailsView(appState: appState)
                .presentationBackground(.black)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(item: $fullscreenSeed) { seed in
            SongFullScreenFeedView(
                songs: seed.songs,
                startIndex: seed.startIndex,
                appState: appState,
                shareLookup: seed.shareLookup
            )
        }
        .sheet(item: $detailMixtape) { mixtape in
            MixtapeDetailView(mixtape: mixtape, appState: appState)
                .presentationBackground(.black)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $detailReceivedMixtape) { share in
            ReceivedMixtapeDetailView(share: share, appState: appState)
                .presentationBackground(.black)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $detailReceivedAlbum) { share in
            ReceivedAlbumDetailView(share: share, appState: appState)
                .presentationBackground(.black)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))

            TextField(
                "",
                text: $searchText,
                prompt: Text("Search your songs").foregroundColor(.white.opacity(0.4))
            )
            .font(.system(size: 14))
            .foregroundStyle(.white)
            .tint(.white)
            .submitLabel(.search)
            .focused($isSearchFocused)
            // Tapping Return on the keyboard collapses focus so users
            // can scan results without the keyboard eating half the
            // screen. `scrollDismissesKeyboard(.interactively)` on the
            // parent VStack handles the swipe-down case.
            .onSubmit { isSearchFocused = false }

            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.08))
        .clipShape(.capsule)
    }

    // MARK: - Segment picker

    /// Horizontally-scrolling segment chip strip. Used to host the
    /// list/grid toggle inline with the chips, which got cramped once
    /// all five chips needed to scroll. The toggle has been moved into
    /// `sectionHeaderBar` directly below this row.
    private var segmentPicker: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                ForEach(MixtapesSegment.allCases) { seg in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedSegment = seg
                        }
                    } label: {
                        VStack(spacing: 6) {
                            Text(seg.rawValue)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(selectedSegment == seg ? .white : .white.opacity(0.35))

                            Rectangle()
                                .fill(selectedSegment == seg ? Color.white : Color.clear)
                                .frame(height: 2)
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
            .padding(.horizontal, 8)
        }
        .scrollIndicators(.hidden)
    }

    /// Section header that sits below the segment chip strip. Shows a
    /// contextual title for the active segment on the leading edge and
    /// the grid/list toggle on the trailing edge. Hidden entirely
    /// while a search query is active (search results replace the
    /// segment view, so a per-segment toggle would be misleading).
    @ViewBuilder
    private var sectionHeaderBar: some View {
        if !isSearching {
            HStack(spacing: 8) {
                Text(sectionTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                    .textCase(.uppercase)
                    .tracking(0.5)

                Spacer()

                viewModeToggle
            }
        }
    }

    /// Title shown on the leading edge of `sectionHeaderBar`. Mirrors
    /// the active segment label so the toggle has obvious context
    /// without resorting to the segment chips above it.
    private var sectionTitle: String {
        switch selectedSegment {
        case .songs:    return "All songs"
        case .mixtapes: return "Your mixtapes"
        case .sent:     return "Sent"
        case .received: return "Received"
        case .liked:    return "Liked"
        }
    }

    /// Two-icon (grid / list) toggle that flips the active segment's
    /// `@AppStorage` mode.
    private var viewModeToggle: some View {
        HStack(spacing: 2) {
            modeButton(target: .grid, icon: "square.grid.2x2.fill")
            modeButton(target: .list, icon: "list.bullet")
        }
        .padding(2)
        .background(Color.white.opacity(0.06), in: Capsule())
    }

    private func modeButton(target: MixtapesViewMode, icon: String) -> some View {
        let active = currentMode == target
        return Button {
            setMode(target)
        } label: {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(active ? .black : .white.opacity(0.6))
                .frame(width: 28, height: 24)
                .background(active ? Color.white : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(target == .grid ? "Grid view" : "List view")
    }

    private var currentMode: MixtapesViewMode {
        switch selectedSegment {
        case .songs:    return MixtapesViewMode(rawValue: songsModeRaw) ?? .grid
        case .mixtapes: return MixtapesViewMode(rawValue: mixtapesModeRaw) ?? .grid
        case .sent:     return MixtapesViewMode(rawValue: sentModeRaw) ?? .list
        case .received: return MixtapesViewMode(rawValue: receivedModeRaw) ?? .list
        case .liked:    return MixtapesViewMode(rawValue: likedModeRaw) ?? .list
        }
    }

    private func setMode(_ mode: MixtapesViewMode) {
        switch selectedSegment {
        case .songs:    songsModeRaw = mode.rawValue
        case .mixtapes: mixtapesModeRaw = mode.rawValue
        case .sent:     sentModeRaw = mode.rawValue
        case .received: receivedModeRaw = mode.rawValue
        case .liked:    likedModeRaw = mode.rawValue
        }
    }

    // MARK: - Segment content

    /// True when the search field has any non-whitespace text. Used to
    /// switch the entire content area from the active segment view to a
    /// flat unified results list across all categories.
    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @ViewBuilder
    private var contentForSegment: some View {
        if isSearching {
            searchResultsList
        } else {
            switch selectedSegment {
            case .songs:
                if currentMode == .grid {
                    SongsGridView(
                        appState: appState,
                        searchText: searchText,
                        onTap: { songs, idx in
                            // Pre-warm AVPlayer so the preview download
                            // overlaps the present transition. Coordinator
                            // is idempotent for already-playing songs.
                            if songs.indices.contains(idx) {
                                AudioPlayerService.shared.play(song: songs[idx])
                            }
                            fullscreenSeed = FullscreenSeed(songs: songs, startIndex: idx)
                        }
                    )
                } else {
                    SongsListView(appState: appState) { songs, idx in
                        if songs.indices.contains(idx) {
                            AudioPlayerService.shared.play(song: songs[idx])
                        }
                        fullscreenSeed = FullscreenSeed(songs: songs, startIndex: idx)
                    }
                }
            case .mixtapes:
                if currentMode == .grid {
                    MixtapesGridView(
                        appState: appState,
                        searchText: searchText,
                        onTap: { mixtape in
                            detailMixtape = mixtape
                        }
                    )
                } else {
                    MixtapesListView(appState: appState) { mixtape in
                        detailMixtape = mixtape
                    }
                }
            case .sent:
                if currentMode == .list {
                    mergedShareFeed(direction: .sent)
                } else {
                    songShareGrid(songs: appState.sentShares)
                }
            case .received:
                if currentMode == .list {
                    mergedShareFeed(direction: .received)
                } else {
                    songShareGrid(songs: appState.receivedShares)
                }
            case .liked:
                if currentMode == .list {
                    shareList(appState.likedShares)
                } else {
                    songShareGrid(songs: appState.likedShares)
                }
            }
        }
    }

    /// Grid layout for the song-share segments (Sent / Received /
    /// Liked). Mixtape and album shares are intentionally hidden in
    /// grid view — square thumbnails work well for individual songs
    /// but a 2x2 mosaic mixed in with album art reads as visual
    /// noise. Users can flip back to list view to see the full
    /// timeline.
    private func songShareGrid(songs: [SongShare]) -> some View {
        let lookupMap: [String: SongShare] = Dictionary(
            songs.map { ($0.song.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let unique: [Song] = {
            var seen = Set<String>()
            var out: [Song] = []
            for share in songs where seen.insert(share.song.id).inserted {
                out.append(share.song)
            }
            return out
        }()
        let horizontalPadding: CGFloat = 12
        let spacing: CGFloat = 10

        return GeometryReader { geo in
            let cellSize = PinterestGridLayout.cellSize(
                containerWidth: geo.size.width,
                horizontalPadding: horizontalPadding,
                spacing: spacing
            )
            ScrollView {
                LazyVStack(spacing: 0) {
                    if unique.isEmpty {
                        emptyShareState.padding(.top, 60)
                    } else {
                        PinterestSquareGrid(
                            items: unique,
                            cellSize: cellSize,
                            spacing: spacing
                        ) { song, side in
                            AlbumArtSquare(
                                url: song.albumArtURL,
                                cornerRadius: 14,
                                showsPlaceholderProgress: false,
                                showsShadow: false,
                                targetDecodeSide: side
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if let idx = unique.firstIndex(where: { $0.id == song.id }) {
                                    AudioPlayerService.shared.play(song: song)
                                    fullscreenSeed = FullscreenSeed(
                                        songs: unique,
                                        startIndex: idx,
                                        shareLookup: { id in lookupMap[id] }
                                    )
                                }
                            }
                        }
                        .padding(.horizontal, horizontalPadding)
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .refreshable { await appState.refreshShares() }
        }
    }

    private func shareList(_ shares: [SongShare]) -> some View {
        // First-wins dedupe by `song.id`. The same song can legitimately
        // appear multiple times in Sent (one share per recipient),
        // Received (one per sender), or Liked (cross-sender duplicates),
        // and `Dictionary(uniqueKeysWithValues:)` would `fatalError` on
        // those duplicates and crash the tab.
        let lookupMap: [String: SongShare] = Dictionary(
            shares.map { ($0.song.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return ScrollView {
            LazyVStack(spacing: 0) {
                if shares.isEmpty {
                    emptyShareState
                } else {
                    ForEach(Array(shares.enumerated()), id: \.element.id) { idx, share in
                        ProfileSongRow(
                            share: share,
                            personLabel: personLabel(for: share),
                            isLiked: appState.isLiked(shareId: share.id),
                            onToggleLike: { appState.toggleLike(shareId: share.id) },
                            onTap: {
                                AudioPlayerService.shared.play(song: share.song)
                                fullscreenSeed = FullscreenSeed(
                                    songs: shares.map(\.song),
                                    startIndex: idx,
                                    shareLookup: { id in lookupMap[id] }
                                )
                            }
                        )
                        if share.id != shares.last?.id {
                            Divider()
                                .background(Color.white.opacity(0.06))
                                .padding(.horizontal, 20)
                        }
                    }
                }
                Color.clear.frame(height: 40)
            }
        }
        .scrollIndicators(.hidden)
        .refreshable { await appState.refreshShares() }
    }

    private func personLabel(for share: SongShare) -> String {
        switch selectedSegment {
        case .sent: return share.recipient.firstName
        case .received: return share.sender.firstName
        case .liked:
            if share.sender.id == appState.currentUser?.id {
                return "To \(share.recipient.firstName)"
            } else {
                return "From \(share.sender.firstName)"
            }
        default: return share.sender.firstName
        }
    }

    // MARK: - Merged share feed (Received / Sent)

    /// Segment direction for the merged feed. Read-only flag — the
    /// underlying data stays in `appState.{received,sent}*`.
    private enum FeedDirection { case received, sent }

    /// Heterogeneous feed item. Used for both Received and Sent so the
    /// row order represents true chronological history regardless of
    /// which underlying collection a share lives in. The `timestamp`
    /// peer accessor is the sort key.
    private enum SharedItem: Identifiable {
        case song(SongShare)
        case mixtape(MixtapeShare)
        case album(AlbumShare)

        var id: String {
            switch self {
            case .song(let s): return "song:\(s.id)"
            case .mixtape(let s): return "mixtape:\(s.id)"
            case .album(let s): return "album:\(s.id)"
            }
        }

        var timestamp: Date {
            switch self {
            case .song(let s): return s.timestamp
            case .mixtape(let s): return s.timestamp
            case .album(let s): return s.timestamp
            }
        }
    }

    /// Builds the unified, timestamp-sorted feed for a given direction.
    /// Newest-first to match every other share UI in the app.
    private func mergedItems(direction: FeedDirection) -> [SharedItem] {
        switch direction {
        case .received:
            let songs = appState.receivedShares.map(SharedItem.song)
            let mixtapes = appState.receivedMixtapeShares.map(SharedItem.mixtape)
            let albums = appState.receivedAlbumShares.map(SharedItem.album)
            return (songs + mixtapes + albums).sorted { $0.timestamp > $1.timestamp }
        case .sent:
            let songs = appState.sentShares.map(SharedItem.song)
            let mixtapes = appState.sentMixtapeShares.map(SharedItem.mixtape)
            let albums = appState.sentAlbumShares.map(SharedItem.album)
            return (songs + mixtapes + albums).sorted { $0.timestamp > $1.timestamp }
        }
    }

    /// Renders the unified Received/Sent feed. Songs use the existing
    /// `ProfileSongRow` so visuals stay identical to the prior version
    /// of these segments; mixtape and album rows get their own slim
    /// row UIs (mosaic / artwork on the left, "Mixtape from @sender"
    /// or "Album from @sender" subtitle, tap to open the read-only
    /// detail).
    @ViewBuilder
    private func mergedShareFeed(direction: FeedDirection) -> some View {
        let items = mergedItems(direction: direction)
        // Snapshot the song subset once so the fullscreen feed seed
        // can carry only-songs (mixtape/album rows handle their own
        // navigation, not the fullscreen feed).
        let songOnly: [SongShare] = items.compactMap {
            if case .song(let s) = $0 { return s }
            return nil
        }
        let lookupMap: [String: SongShare] = Dictionary(
            songOnly.map { ($0.song.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        ScrollView {
            LazyVStack(spacing: 0) {
                if items.isEmpty {
                    emptyShareState
                } else {
                    ForEach(Array(items.enumerated()), id: \.element.id) { _, item in
                        switch item {
                        case .song(let share):
                            // Tapping a song opens the fullscreen feed
                            // seeded from the song-only sub-list, so
                            // swiping doesn't accidentally land on a
                            // mixtape-share row inside a feed that's
                            // built around `[Song]`.
                            ProfileSongRow(
                                share: share,
                                personLabel: personLabel(for: share, direction: direction),
                                isLiked: appState.isLiked(shareId: share.id),
                                onToggleLike: { appState.toggleLike(shareId: share.id) },
                                onTap: {
                                    if let idx = songOnly.firstIndex(where: { $0.id == share.id }) {
                                        AudioPlayerService.shared.play(song: share.song)
                                        fullscreenSeed = FullscreenSeed(
                                            songs: songOnly.map(\.song),
                                            startIndex: idx,
                                            shareLookup: { id in lookupMap[id] }
                                        )
                                    }
                                }
                            )
                        case .mixtape(let share):
                            mixtapeShareRow(share: share, direction: direction)
                        case .album(let share):
                            albumShareRow(share: share, direction: direction)
                        }
                        if item.id != items.last?.id {
                            Divider()
                                .background(Color.white.opacity(0.06))
                                .padding(.horizontal, 20)
                        }
                    }
                }
                Color.clear.frame(height: 40)
            }
        }
        .scrollIndicators(.hidden)
        .refreshable { await appState.refreshShares() }
    }

    private func personLabel(for share: SongShare, direction: FeedDirection) -> String {
        switch direction {
        case .sent: return share.recipient.firstName
        case .received: return share.sender.firstName
        }
    }

    /// Slim list row for a mixtape share. Tapping opens the read-only
    /// `ReceivedMixtapeDetailView` (or, for outbound items, the live
    /// owner-side `MixtapeDetailView` if the mixtape still exists).
    private func mixtapeShareRow(share: MixtapeShare, direction: FeedDirection) -> some View {
        let counterpart = direction == .received ? share.sender : share.recipient
        let prefix = direction == .received ? "Mixtape from" : "Mixtape to"
        let songCount = share.mixtape.songCount
        return HStack(spacing: 12) {
            MixtapeCoverView(mixtape: share.mixtape, cornerRadius: 8, showsShadow: false)
                .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 3) {
                Text(share.mixtape.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("\(prefix) @\(counterpart.username.isEmpty ? counterpart.firstName : counterpart.username) · \(songCount) song\(songCount == 1 ? "" : "s")")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(1)
            }

            Spacer()

            Text(share.timestamp.formatted(.relative(presentation: .named)))
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.25))
                .frame(width: 70, alignment: .trailing)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            // Sent-side entries: if the mixtape is still owned by us,
            // jump to the live editable detail; otherwise fall back to
            // the snapshot reader. Received-side always uses the
            // snapshot since the original is in someone else's
            // account.
            if direction == .sent,
               let live = appState.mixtapeStore.mixtape(withId: share.mixtape.id) {
                detailMixtape = live
            } else {
                detailReceivedMixtape = share
            }
        }
    }

    /// Slim list row for an album share.
    private func albumShareRow(share: AlbumShare, direction: FeedDirection) -> some View {
        let counterpart = direction == .received ? share.sender : share.recipient
        let prefix = direction == .received ? "Album from" : "Album to"
        let count = share.songs.count
        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08))
                AsyncImage(url: URL(string: share.album.artworkURL)) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    }
                }
                .clipShape(.rect(cornerRadius: 8))
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 3) {
                Text(share.album.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("\(prefix) @\(counterpart.username.isEmpty ? counterpart.firstName : counterpart.username) · \(count) song\(count == 1 ? "" : "s")")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(1)
            }

            Spacer()

            Text(share.timestamp.formatted(.relative(presentation: .named)))
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.25))
                .frame(width: 70, alignment: .trailing)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            detailReceivedAlbum = share
        }
    }

    private var emptyShareState: some View {
        VStack(spacing: 8) {
            Image(systemName: "music.note")
                .font(.system(size: 28))
                .foregroundStyle(.white.opacity(0.15))
            Text(searchText.isEmpty ? "Nothing here yet" : "No matches")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.3))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    // MARK: - Unified search results

    /// One row in the global search list. Carries the provenance label
    /// inline so the row view doesn't have to know which segment a hit
    /// came from.
    private enum MixtapesSearchResult: Identifiable {
        case share(SongShare, personLabel: String)
        case song(Song, contextLabel: String)

        var id: String {
            switch self {
            case .share(let share, _): return "share:\(share.id)"
            case .song(let song, _): return "song:\(song.id)"
            }
        }

        var song: Song {
            switch self {
            case .share(let share, _): return share.song
            case .song(let song, _): return song
            }
        }
    }

    /// Walks every source the search bar should cover (Sent, Received,
    /// Liked, every user mixtape including the synthetic Liked one) and
    /// returns a deduped `[MixtapesSearchResult]` ordered the same way
    /// the visible segments order their content (sent → received → liked
    /// → mixtapes). Dedupe key is `song.id` with share results preferred
    /// over song-only ones, so a song that appears in both a share and a
    /// mixtape is rendered once with its full share context.
    private func aggregatedSearchResults() -> [MixtapesSearchResult] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }

        func matchesShare(_ share: SongShare) -> Bool {
            share.song.title.lowercased().contains(q)
                || share.song.artist.lowercased().contains(q)
                || (share.note ?? "").lowercased().contains(q)
        }

        var seen = Set<String>()
        var results: [MixtapesSearchResult] = []

        for share in appState.sentShares
        where matchesShare(share) && seen.insert(share.song.id).inserted {
            results.append(.share(share, personLabel: "Sent to \(share.recipient.firstName)"))
        }
        for share in appState.receivedShares
        where matchesShare(share) && seen.insert(share.song.id).inserted {
            results.append(.share(share, personLabel: "From \(share.sender.firstName)"))
        }
        for share in appState.likedShares
        where matchesShare(share) && seen.insert(share.song.id).inserted {
            let label: String
            if share.sender.id == appState.currentUser?.id {
                label = "Liked · to \(share.recipient.firstName)"
            } else {
                label = "Liked · from \(share.sender.firstName)"
            }
            results.append(.share(share, personLabel: label))
        }

        for mix in appState.mixtapeStore.allMixtapes {
            let mixNameMatches = mix.name.lowercased().contains(q)
            for song in mix.songs where !seen.contains(song.id) {
                let songMatches = song.title.lowercased().contains(q)
                    || song.artist.lowercased().contains(q)
                guard mixNameMatches || songMatches else { continue }
                seen.insert(song.id)
                results.append(.song(song, contextLabel: "From mixtape: \(mix.name)"))
            }
        }

        return results
    }

    /// Replaces the active segment view whenever the search field has
    /// any text. Mirrors the Sent/Received/Liked list visuals so the
    /// transition feels like "the same row UI, scoped wider" — share
    /// hits use `ProfileSongRow`, mixtape-only hits use the slim
    /// `MixtapesSearchRow`. Tapping any row opens the fullscreen feed
    /// seeded with the entire result list so the user can swipe through
    /// all matches inline.
    private var searchResultsList: some View {
        let results = aggregatedSearchResults()
        let allSongs = results.map(\.song)
        let lookupMap: [String: SongShare] = Dictionary(
            results.compactMap { result -> (String, SongShare)? in
                if case .share(let share, _) = result {
                    return (share.song.id, share)
                }
                return nil
            },
            uniquingKeysWith: { first, _ in first }
        )

        return ScrollView {
            LazyVStack(spacing: 0) {
                if results.isEmpty {
                    emptyShareState
                } else {
                    ForEach(Array(results.enumerated()), id: \.element.id) { idx, result in
                        switch result {
                        case .share(let share, let label):
                            ProfileSongRow(
                                share: share,
                                personLabel: label,
                                isLiked: appState.isLiked(shareId: share.id),
                                onToggleLike: { appState.toggleLike(shareId: share.id) },
                                onTap: {
                                    AudioPlayerService.shared.play(song: share.song)
                                    fullscreenSeed = FullscreenSeed(
                                        songs: allSongs,
                                        startIndex: idx,
                                        shareLookup: { id in lookupMap[id] }
                                    )
                                }
                            )
                        case .song(let song, let label):
                            MixtapesSearchRow(
                                song: song,
                                contextLabel: label,
                                onTap: {
                                    AudioPlayerService.shared.play(song: song)
                                    fullscreenSeed = FullscreenSeed(
                                        songs: allSongs,
                                        startIndex: idx,
                                        shareLookup: { id in lookupMap[id] }
                                    )
                                }
                            )
                        }
                        if idx != results.count - 1 {
                            Divider()
                                .background(Color.white.opacity(0.06))
                                .padding(.horizontal, 20)
                        }
                    }
                }
                Color.clear.frame(height: 40)
            }
        }
        .scrollIndicators(.hidden)
    }
}

// MARK: - Songs grid

/// Aggregated unique songs across received + sent + liked + every saved
/// song from `MixtapeStore`, deduped by `song.id`. Newest activity first
/// — `MixtapeStore.allSongsAcrossMixtapes` already returns the right order
/// for the saved set; we layer share-derived songs on top so the grid is
/// truly the union of "anything I've touched musically".
private struct SongsGridView: View {
    let appState: AppState
    let searchText: String
    let onTap: (_ songs: [Song], _ index: Int) -> Void

    private let horizontalPadding: CGFloat = 12
    private let spacing: CGFloat = 10

    private var aggregated: [Song] {
        var seen = Set<String>()
        var result: [Song] = []

        // Saved + Liked (synthetic) come first via MixtapeStore so the
        // user's curation surface to the top.
        for song in appState.mixtapeStore.allSongsAcrossMixtapes() where seen.insert(song.id).inserted {
            result.append(song)
        }
        // Then received and sent shares so the grid still shows
        // everything the user has been involved with.
        for share in appState.receivedShares where seen.insert(share.song.id).inserted {
            result.append(share.song)
        }
        for share in appState.sentShares where seen.insert(share.song.id).inserted {
            result.append(share.song)
        }
        return result
    }

    private var filtered: [Song] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return aggregated }
        return aggregated.filter { song in
            song.title.lowercased().contains(q) || song.artist.lowercased().contains(q)
        }
    }

    var body: some View {
        GeometryReader { geo in
            let cellSize = PinterestGridLayout.cellSize(
                containerWidth: geo.size.width,
                horizontalPadding: horizontalPadding,
                spacing: spacing
            )
            ScrollView {
                LazyVStack(spacing: 0) {
                    if filtered.isEmpty {
                        emptyState
                            .padding(.top, 80)
                    } else {
                        PinterestSquareGrid(
                            items: filtered,
                            cellSize: cellSize,
                            spacing: spacing
                        ) { song, side in
                            AlbumArtSquare(
                                url: song.albumArtURL,
                                cornerRadius: 14,
                                showsPlaceholderProgress: false,
                                showsShadow: false,
                                targetDecodeSide: side
                            )
                            // See HomeDiscoverView for the rationale —
                            // an explicit content shape + `.onTapGesture`
                            // is the only reliable way to make a
                            // transparent `AlbumArtSquare` cell tappable
                            // when nested under the staggered grid's
                            // `LazyVStack`s.
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if let idx = filtered.firstIndex(where: { $0.id == song.id }) {
                                    onTap(filtered, idx)
                                }
                            }
                        }
                        .padding(.horizontal, horizontalPadding)
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .refreshable { await appState.refreshShares() }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 28))
                .foregroundStyle(.white.opacity(0.15))
            Text(searchText.isEmpty ? "No songs yet — like or save some" : "No matches")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.3))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Mixtapes grid

private struct MixtapesGridView: View {
    let appState: AppState
    let searchText: String
    let onTap: (Mixtape) -> Void

    private let horizontalPadding: CGFloat = 12
    private let spacing: CGFloat = 10

    private var filtered: [Mixtape] {
        let all = appState.mixtapeStore.allMixtapes
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return all }
        return all.filter { mix in
            if mix.name.lowercased().contains(q) { return true }
            return mix.songs.contains(where: { $0.title.lowercased().contains(q) || $0.artist.lowercased().contains(q) })
        }
    }

    var body: some View {
        GeometryReader { geo in
            let cellSize = PinterestGridLayout.cellSize(
                containerWidth: geo.size.width,
                horizontalPadding: horizontalPadding,
                spacing: spacing
            )

            ScrollView {
                LazyVStack(spacing: 0) {
                    if filtered.isEmpty {
                        emptyState.padding(.top, 80)
                    } else {
                        PinterestSquareGrid(
                            items: filtered,
                            cellSize: cellSize,
                            spacing: spacing
                        ) { mixtape, _ in
                            VStack(spacing: 6) {
                                MixtapeBoardCardCover(mixtape: mixtape, cornerRadius: 14)
                                    .frame(width: cellSize, height: cellSize)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(mixtape.name)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                    Text("\(mixtape.songCount) song\(mixtape.songCount == 1 ? "" : "s")")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.white.opacity(0.45))
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 4)
                            }
                            // Same Button → tap-gesture conversion as the
                            // song grids above; the cover + name stack
                            // had the same transparent-label issue.
                            .contentShape(Rectangle())
                            .onTapGesture {
                                onTap(mixtape)
                            }
                        }
                        .padding(.horizontal, horizontalPadding)
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .refreshable {
                await appState.mixtapeStore.loadFromFirestore()
                await appState.saveService.loadFromFirestore()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 28))
                .foregroundStyle(.white.opacity(0.15))
            Text(searchText.isEmpty ? "No mixtapes yet" : "No matches")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.3))
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Songs list view

/// List variant of the Songs segment. Same data source as
/// `SongsGridView` (every song the user has touched, deduped) but
/// rendered as a slim `SongListRow` per entry. Tap routes through the
/// caller-supplied closure into the fullscreen feed.
private struct SongsListView: View {
    let appState: AppState
    let onTap: (_ songs: [Song], _ index: Int) -> Void

    private var aggregated: [Song] {
        var seen = Set<String>()
        var result: [Song] = []
        for song in appState.mixtapeStore.allSongsAcrossMixtapes() where seen.insert(song.id).inserted {
            result.append(song)
        }
        for share in appState.receivedShares where seen.insert(share.song.id).inserted {
            result.append(share.song)
        }
        for share in appState.sentShares where seen.insert(share.song.id).inserted {
            result.append(share.song)
        }
        return result
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if aggregated.isEmpty {
                    emptyState.padding(.top, 60)
                } else {
                    ForEach(Array(aggregated.enumerated()), id: \.element.id) { idx, song in
                        SongListRow(song: song, onTap: { onTap(aggregated, idx) })
                        if idx != aggregated.count - 1 {
                            Divider()
                                .background(Color.white.opacity(0.06))
                                .padding(.horizontal, 20)
                        }
                    }
                }
                Color.clear.frame(height: 40)
            }
        }
        .scrollIndicators(.hidden)
        .refreshable { await appState.refreshShares() }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "music.note.list")
                .font(.system(size: 28))
                .foregroundStyle(.white.opacity(0.15))
            Text("No songs yet — like or save some")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.3))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Slim row used by `SongsListView` (and reusable elsewhere). No
/// share context — just art / title / artist / duration / play
/// glyph. Tapping the row fires `onTap`; the inline play button
/// triggers preview playback without opening the fullscreen feed.
private struct SongListRow: View {
    let song: Song
    let onTap: () -> Void

    private var audioPlayer: AudioPlayerService { AudioPlayerService.shared }
    private var isPlaying: Bool { audioPlayer.currentSongId == song.id && audioPlayer.isPlaying }

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
                        Circle().fill(.black.opacity(0.45))
                            .frame(width: 28, height: 28)
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
                .sensoryFeedback(.impact(weight: .light), trigger: isPlaying)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(song.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(song.artist)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(1)
            }
            Spacer()
            if !song.duration.isEmpty {
                Text(song.duration)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.25))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}

// MARK: - Mixtapes list view

/// List variant of the Mixtapes segment. Synthetic Liked mixtape is
/// pinned at the top to mirror the grid; otherwise rows are
/// most-recently-updated first.
private struct MixtapesListView: View {
    let appState: AppState
    let onTap: (Mixtape) -> Void

    private var mixtapes: [Mixtape] { appState.mixtapeStore.allMixtapes }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if mixtapes.isEmpty {
                    emptyState.padding(.top, 60)
                } else {
                    ForEach(Array(mixtapes.enumerated()), id: \.element.id) { idx, mix in
                        MixtapeListRow(mixtape: mix, onTap: { onTap(mix) })
                        if idx != mixtapes.count - 1 {
                            Divider()
                                .background(Color.white.opacity(0.06))
                                .padding(.horizontal, 20)
                        }
                    }
                }
                Color.clear.frame(height: 40)
            }
        }
        .scrollIndicators(.hidden)
        .refreshable {
            await appState.mixtapeStore.loadFromFirestore()
            await appState.saveService.loadFromFirestore()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 28))
                .foregroundStyle(.white.opacity(0.15))
            Text("No mixtapes yet")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.3))
        }
        .frame(maxWidth: .infinity)
    }
}

/// Slim row for `MixtapesListView`: 2x2 mosaic + name + song count +
/// chevron. Tap fires `onTap` with the mixtape so the parent can
/// route into the live `MixtapeDetailView`.
private struct MixtapeListRow: View {
    let mixtape: Mixtape
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            MixtapeCoverView(mixtape: mixtape, cornerRadius: 8, showsShadow: false)
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text(mixtape.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("\(mixtape.songCount) song\(mixtape.songCount == 1 ? "" : "s")")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.25))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}

// MARK: - Mixtape detail

/// Minimal mixtape detail: name, song count, and a Pinterest grid of the
/// mixtape's songs. Tapping a song opens the fullscreen feed seeded with
/// that mixtape's order. System Liked mixtape gets a header chip so the
/// user understands why it can't be renamed/deleted.
struct MixtapeDetailView: View {
    let mixtape: Mixtape
    let appState: AppState

    @Environment(\.dismiss) private var dismiss
    @State private var fullscreenSeed: FullscreenSeed?
    @State private var showEditDetails: Bool = false
    @State private var showShareSheet: Bool = false
    /// Toggled by the "more"/"less" affordance under the description.
    /// Defaults to false so a long blurb collapses to 3 lines on first
    /// visit; the user can opt-in to the full text without losing grid
    /// real estate.
    @State private var descriptionExpanded: Bool = false

    /// Detail-view layout preference, persisted across launches.
    /// Defaults to grid — Spotify-style album-art mosaic is the
    /// expected first-impression for an opened mixtape, with list a
    /// one-tap fallback for users who'd rather see titles.
    /// Default to **list** so opened mixtapes read like a tracklist
    /// (artist-page pattern); users can flip to grid anytime.
    @AppStorage("mixtapes.detail.viewMode") private var detailModeRaw = MixtapesViewMode.list.rawValue

    private var detailMode: MixtapesViewMode {
        MixtapesViewMode(rawValue: detailModeRaw) ?? .list
    }

    private var isOwner: Bool {
        guard let uid = appState.currentUser?.id else { return false }
        return !liveMixtape.isSystemLiked && uid == liveMixtape.ownerId
    }

    private let horizontalPadding: CGFloat = 12
    private let spacing: CGFloat = 10

    private var liveMixtape: Mixtape {
        // Pull the latest version out of `MixtapeStore` (which knows the
        // synthetic Liked mixtape) so newly added/removed songs reflect
        // here without the parent re-presenting the sheet.
        appState.mixtapeStore.mixtape(withId: mixtape.id) ?? mixtape
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let screenW = geo.size.width
                let cellSize = PinterestGridLayout.cellSize(
                    containerWidth: screenW,
                    horizontalPadding: horizontalPadding,
                    spacing: spacing
                )
                ZStack {
                    Color.black.ignoresSafeArea()

                    ScrollView {
                        VStack(spacing: 0) {
                            heroHeader(width: screenW)

                            VStack(alignment: .leading, spacing: 0) {
                                if liveMixtape.isSystemLiked {
                                    Text("Auto-built from your liked songs")
                                        .font(.system(size: 13))
                                        .foregroundStyle(.white.opacity(0.45))
                                        .padding(.top, 14)
                                } else {
                                    Text("\(liveMixtape.songCount) song\(liveMixtape.songCount == 1 ? "" : "s")")
                                        .font(.system(size: 14))
                                        .foregroundStyle(.white.opacity(0.5))
                                        .padding(.top, 14)
                                }

                                if let blurb = liveMixtape.description, !blurb.isEmpty {
                                    descriptionBlock(blurb)
                                        .padding(.top, 10)
                                }

                                if !liveMixtape.songs.isEmpty {
                                    detailSectionHeaderBar
                                        .padding(.top, 16)
                                        .padding(.bottom, 6)
                                }

                                if liveMixtape.songs.isEmpty {
                                    emptyState.padding(.top, 40)
                                } else if detailMode == .grid {
                                    PinterestSquareGrid(
                                        items: liveMixtape.songs,
                                        cellSize: cellSize,
                                        spacing: spacing
                                    ) { song, side in
                                        AlbumArtSquare(
                                            url: song.albumArtURL,
                                            cornerRadius: 14,
                                            showsPlaceholderProgress: false,
                                            showsShadow: false,
                                            targetDecodeSide: side
                                        )
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            if let idx = liveMixtape.songs.firstIndex(where: { $0.id == song.id }) {
                                                AudioPlayerService.shared.play(song: song)
                                                fullscreenSeed = FullscreenSeed(
                                                    songs: liveMixtape.songs,
                                                    startIndex: idx
                                                )
                                            }
                                        }
                                    }
                                    .padding(.horizontal, horizontalPadding)
                                    .padding(.bottom, 32)
                                } else {
                                    LazyVStack(spacing: 0) {
                                        ForEach(Array(liveMixtape.songs.enumerated()), id: \.element.id) { idx, song in
                                            SongListRow(song: song) {
                                                AudioPlayerService.shared.play(song: song)
                                                fullscreenSeed = FullscreenSeed(
                                                    songs: liveMixtape.songs,
                                                    startIndex: idx
                                                )
                                            }
                                            if song.id != liveMixtape.songs.last?.id {
                                                Divider()
                                                    .background(Color.white.opacity(0.05))
                                                    .padding(.leading, 80)
                                            }
                                        }
                                    }
                                    .padding(.bottom, 32)
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.white)
                }
                if isOwner {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showShareSheet = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 17))
                                .foregroundStyle(.white.opacity(0.85))
                        }
                        .accessibilityLabel("Share mixtape")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button {
                                showEditDetails = true
                            } label: {
                                Label("Edit details", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                Task {
                                    await appState.mixtapeStore.delete(mixtapeId: liveMixtape.id)
                                    dismiss()
                                }
                            } label: {
                                Label("Delete mixtape", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 17))
                                .foregroundStyle(.white.opacity(0.85))
                        }
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(item: $fullscreenSeed) { seed in
            SongFullScreenFeedView(
                songs: seed.songs,
                startIndex: seed.startIndex,
                appState: appState
            )
        }
        .sheet(isPresented: $showEditDetails) {
            EditMixtapeDetailsSheet(mixtape: liveMixtape, appState: appState)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showShareSheet) {
            // Snapshot the live mixtape so an edit mid-share doesn't
            // change what the recipient sees, then route through the
            // unified share view. `FriendSelectorView` branches on
            // `.mixtape(...)` to render `MixtapeCoverView` and
            // dispatch via `appState.sendMixtape`.
            let snapshot = liveMixtape
            NavigationStack {
                FriendSelectorView(
                    item: .mixtape(snapshot),
                    appState: appState,
                    onBack: { showShareSheet = false },
                    onSent: { showShareSheet = false }
                )
            }
            .presentationBackground(.black)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    /// Full-width square hero: uploaded cover or mosaic fallback, title
    /// on a bottom gradient (matches Home Discover cells).
    private func heroHeader(width: CGFloat) -> some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let u = liveMixtape.coverImageURL?.trimmingCharacters(in: .whitespacesAndNewlines), !u.isEmpty,
                   let url = URL(string: u) {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().aspectRatio(contentMode: .fill)
                        } else {
                            Color(.systemGray5)
                        }
                    }
                } else {
                    MixtapeCoverView(mixtape: liveMixtape, cornerRadius: 0, showsShadow: false)
                }
            }
            .frame(width: width, height: width)
            .clipped()

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .clear, location: 0.82),
                    .init(color: .black.opacity(0.88), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(width: width, height: width)
            .allowsHitTesting(false)

            Text(liveMixtape.name)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
        }
        .frame(width: width, height: width)
    }

    /// Section header strip for the detail screen. Mirrors the
    /// `sectionHeaderBar` used on the parent Mixtapes tab — labelled
    /// "Songs" on the leading edge with the same grid/list toggle on
    /// the trailing edge — so users have one consistent affordance for
    /// flipping layout regardless of which surface they're on.
    private var detailSectionHeaderBar: some View {
        HStack(spacing: 8) {
            Text("Songs")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
                .textCase(.uppercase)
                .tracking(0.5)
            Spacer()
            HStack(spacing: 2) {
                detailModeButton(target: .grid, icon: "square.grid.2x2.fill")
                detailModeButton(target: .list, icon: "list.bullet")
            }
            .padding(2)
            .background(Color.white.opacity(0.06), in: Capsule())
        }
    }

    private func detailModeButton(target: MixtapesViewMode, icon: String) -> some View {
        let active = detailMode == target
        return Button {
            detailModeRaw = target.rawValue
        } label: {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(active ? .black : .white.opacity(0.6))
                .frame(width: 28, height: 24)
                .background(active ? Color.white : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(target == .grid ? "Grid view" : "List view")
    }

    /// Description text + optional more/less toggle. Collapsed by
    /// default at 3 lines; `descriptionExpanded` flips that to a full
    /// (still capped to 300 chars at write time) reveal.
    private func descriptionBlock(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(descriptionExpanded ? nil : 3)
                .fixedSize(horizontal: false, vertical: true)
            // Heuristic disclosure trigger: only surface "more" when
            // the text is long enough that the 3-line clamp would
            // actually cut into it. ~120 chars is a tight upper bound
            // for 3 lines of 13pt text on standard widths.
            if text.count > 120 {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        descriptionExpanded.toggle()
                    }
                } label: {
                    Text(descriptionExpanded ? "less" : "more")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "music.note")
                .font(.system(size: 28))
                .foregroundStyle(.white.opacity(0.15))
            Text(liveMixtape.isSystemLiked ? "Like a song to start filling this in" : "No songs in this mixtape yet")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.3))
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Profile details (top-leading button destination)

/// Lightweight wrapper that surfaces the profile header info that used
/// to live at the top of `ProfileView`. Kept minimal — the spec calls
/// for the profile button to lead to a "details" surface, not the old
/// full-screen Profile tab.
struct ProfileDetailsView: View {
    let appState: AppState
    @Environment(\.dismiss) private var dismiss

    private var user: AppUser? { appState.currentUser }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 16) {
                    Text(user?.initials ?? "?")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 96, height: 96)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Circle())
                        .padding(.top, 32)

                    Text(user?.firstName ?? "")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)

                    Text("@\(user?.username ?? "")")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.45))

                    HStack(spacing: 6) {
                        Image(systemName: "music.note.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(appState.preferredMusicService == .spotify ? .green : .pink)
                        Text(appState.preferredMusicService == .spotify ? "Spotify listener" : "Apple Music listener")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .padding(.top, 4)

                    Spacer()
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Fullscreen seed payload

/// Identifiable payload for `.fullScreenCover(item:)`. Holds the ordered
/// `[Song]`, the start index, and an optional share lookup so per-share
/// context (heart overlay, share-aware Send) survives the transition.
struct FullscreenSeed: Identifiable {
    let id = UUID()
    let songs: [Song]
    let startIndex: Int
    let shareLookup: ((String) -> SongShare?)?

    init(
        songs: [Song],
        startIndex: Int,
        shareLookup: ((String) -> SongShare?)? = nil
    ) {
        self.songs = songs
        self.startIndex = startIndex
        self.shareLookup = shareLookup
    }
}
