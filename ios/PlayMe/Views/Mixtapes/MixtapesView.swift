import SwiftUI

/// Top-level tabs of the library screen. Two swipeable pages: a
/// Locket-style Songs calendar (default landing) and your Mixtapes.
/// Declaration order is the left-to-right page / chip order.
enum MixtapesSegment: String, CaseIterable, Identifiable {
    case songs = "Songs"
    case mixtapes = "Mixtapes"

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

    /// Drives the top segment control and stays in sync with the inner
    /// `LibraryPager`. `ContentView` observes it but no longer drives swipe
    /// escape — the pager owns Songs<->Mixtapes paging and the Songs->Search
    /// hand-off directly.
    @Binding var selectedSegment: MixtapesSegment
    /// Opens the search/send sheet (tapping the calendar's "+" on today).
    var onSendSong: () -> Void
    /// Called when the user swipes right off the Songs page — escapes to the
    /// main Search tab with no rubber-band bounce.
    var onSwipeToSearch: () -> Void
    @State private var searchText: String = ""
    @State private var showSettings: Bool = false
    @State private var showProfileDetails: Bool = false
    /// Drives the search overlay that replaces the tab content while active.
    @State private var showSearch: Bool = false
    @State private var fullscreenSeed: FullscreenSeed?
    /// A tapped calendar day's songs, presented in the Locket-style carousel.
    @State private var dayCarouselSeed: DayCarouselSeed?
    @State private var detailMixtape: Mixtape?
    /// Inbound mixtape share to push into the read-only detail view.
    @State private var detailReceivedMixtape: MixtapeShare?
    /// Inbound album share to push into the read-only detail view.
    @State private var detailReceivedAlbum: AlbumShare?
    /// Focus binding for the search field. Drives Return-key dismissal and
    /// programmatic focus when the search overlay opens.
    @FocusState private var isSearchFocused: Bool

    // Grid/list preference for the Mixtapes page.
    @AppStorage("mixtapes.viewMode.mixtapes") private var mixtapesModeRaw = MixtapesViewMode.grid.rawValue

    private var mixtapesMode: MixtapesViewMode {
        MixtapesViewMode(rawValue: mixtapesModeRaw) ?? .grid
    }

    private var user: AppUser? { appState.currentUser }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if showSearch {
                    searchOverlay
                } else {
                    VStack(spacing: 0) {
                        topSegmentControl
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                            .padding(.bottom, 10)

                        LibraryPager(
                            segment: $selectedSegment,
                            onSwipeRightFromSongs: onSwipeToSearch,
                            songs: {
                                SongCalendarView(
                                    appState: appState,
                                    onOpenDay: { groups in
                                        dayCarouselSeed = DayCarouselSeed(groups: groups)
                                    },
                                    onSendSong: onSendSong
                                )
                            },
                            mixtapes: { mixtapesPage }
                        )
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showProfileDetails = true
                    } label: {
                        AppUserAvatar(user: user, size: 30, background: Color.white.opacity(0.15))
                    }
                    .accessibilityLabel("Profile")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { showSearch = true }
                            isSearchFocused = true
                        } label: {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        .accessibilityLabel("Search")

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
        .fullScreenCover(item: $dayCarouselSeed) { seed in
            DayCarouselView(groups: seed.groups, appState: appState)
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

            AppTextField(
                "",
                text: $searchText,
                prompt: Text("Search your songs").foregroundColor(.white.opacity(0.4)),
                submitLabel: .search,
                onSubmit: { isSearchFocused = false }
            )
            .font(.system(size: 14))
            .foregroundStyle(.white)
            .tint(.white)
            .focused($isSearchFocused)

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

    // MARK: - Top tab control

    /// Two-chip segmented control kept in sync with the swipeable TabView.
    private var topSegmentControl: some View {
        HStack(spacing: 0) {
            ForEach(MixtapesSegment.allCases) { seg in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { selectedSegment = seg }
                } label: {
                    Text(seg.rawValue)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(selectedSegment == seg ? .black : .white.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background {
                            if selectedSegment == seg {
                                Capsule().fill(.white)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.white.opacity(0.08), in: Capsule())
    }

    // MARK: - Mixtapes page

    private var mixtapesPage: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Your mixtapes")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                    .textCase(.uppercase)
                    .tracking(0.5)

                Spacer()

                viewModeToggle
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 6)

            if mixtapesMode == .grid {
                MixtapesGridView(appState: appState, searchText: "") { mixtape in
                    detailMixtape = mixtape
                }
            } else {
                MixtapesListView(appState: appState) { mixtape in
                    detailMixtape = mixtape
                }
            }
        }
    }

    /// Two-icon (grid / list) toggle for the Mixtapes page.
    private var viewModeToggle: some View {
        HStack(spacing: 2) {
            modeButton(target: .grid, icon: "square.grid.2x2.fill")
            modeButton(target: .list, icon: "list.bullet")
        }
        .padding(2)
        .background(Color.white.opacity(0.06), in: Capsule())
    }

    private func modeButton(target: MixtapesViewMode, icon: String) -> some View {
        let active = mixtapesMode == target
        return Button {
            mixtapesModeRaw = target.rawValue
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

    // MARK: - Search overlay

    /// True when the search field has any non-whitespace text.
    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Replaces the tab content while the search affordance is open. Reuses
    /// the unified `searchResultsList` so songs + mixtapes stay searchable.
    private var searchOverlay: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                searchBar
                Button("Cancel") {
                    withAnimation(.easeInOut(duration: 0.2)) { showSearch = false }
                    searchText = ""
                    isSearchFocused = false
                }
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.8))
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)

            if isSearching {
                searchResultsList
            } else {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 28))
                        .foregroundStyle(.white.opacity(0.15))
                    Text("Search your songs and mixtapes")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.3))
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .scrollDismissesKeyboard(.interactively)
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
                                isLiked: appState.isLikedSong(share.song.id),
                                onToggleLike: { appState.toggleLikeSong(share.song, share: share) },
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
                                isLiked: appState.isLikedSong(share.song.id),
                                onToggleLike: { appState.toggleLikeSong(share.song, share: share) },
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
                                appState: appState,
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

    /// True only before the user has ANY mixtape content — no mixtapes of
    /// their own AND no liked songs. The synthetic Liked tile surfaces as
    /// soon as the user likes their first song, so liking now visibly
    /// builds the auto "Liked" mixtape instead of staying hidden behind
    /// the "save your first song" empty state.
    private var showFirstMixtapeState: Bool {
        appState.mixtapeStore.userMixtapes.isEmpty
            && appState.likedSongs.isEmpty
            && appState.likedShareIds.isEmpty
            && searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        GeometryReader { geo in
            let columnWidth = PinterestGridLayout.columnWidth(
                containerWidth: geo.size.width,
                horizontalPadding: horizontalPadding,
                spacing: spacing
            )
            let mosaicHeight = columnWidth / MixtapeBoardCardCover.mosaicAspect
            let captionBlockHeight: CGFloat = 34
            let cardSpacing: CGFloat = 6
            let rowHeight = mosaicHeight + cardSpacing + captionBlockHeight
            let columns = [
                GridItem(.fixed(columnWidth), spacing: spacing, alignment: .top),
                GridItem(.fixed(columnWidth), spacing: spacing, alignment: .top)
            ]

            ScrollView {
                LazyVStack(spacing: 0) {
                    if showFirstMixtapeState {
                        FirstMixtapeEmptyState().padding(.top, 48)
                    } else if filtered.isEmpty {
                        emptyState.padding(.top, 80)
                    } else {
                        LazyVGrid(columns: columns, alignment: .center, spacing: spacing) {
                            ForEach(filtered) { mixtape in
                                VStack(alignment: .leading, spacing: cardSpacing) {
                                    MixtapeBoardCardCover(mixtape: mixtape, cornerRadius: 14)
                                        .frame(width: columnWidth)
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
                                .frame(width: columnWidth, height: rowHeight, alignment: .top)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    onTap(mixtape)
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

// MARK: - First mixtape empty state

/// Premium empty state shown on the Mixtapes tab before the user has
/// created any mixtape of their own. Renders a tasteful "wireframe"
/// preview of mixtape cards (using the real board mosaic aspect) above a
/// bookmark icon and copy nudging the user to save their first song.
private struct FirstMixtapeEmptyState: View {
    var body: some View {
        VStack(spacing: 30) {
            HStack(spacing: 12) {
                ghostCard
                ghostCard
            }
            .frame(maxWidth: 320)
            .padding(.horizontal, 28)

            VStack(spacing: 10) {
                Image(systemName: "bookmark")
                    .font(.system(size: 30, weight: .regular))
                    .foregroundStyle(.white.opacity(0.5))
                Text("Save your first song to start a mixtape")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                Text("Tap the bookmark on any song to add it.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.3))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 44)
        }
        .frame(maxWidth: .infinity)
    }

    private var ghostCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 14)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.09), Color.white.opacity(0.03)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .aspectRatio(MixtapeBoardCardCover.mosaicAspect, contentMode: .fit)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.white.opacity(0.10))
                .frame(width: 64, height: 8)
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.white.opacity(0.05))
                .frame(width: 40, height: 7)
        }
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
    /// When provided, a song-level like heart is shown so any song can be
    /// liked/unliked straight from the list (e.g. the Liked mixtape).
    var appState: AppState? = nil
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
            if let appState {
                Button {
                    appState.toggleLikeSong(song)
                } label: {
                    Image(systemName: appState.isLikedSong(song.id) ? "heart.fill" : "heart")
                        .font(.system(size: 16))
                        .foregroundStyle(appState.isLikedSong(song.id) ? AnyShapeStyle(AppAccentGradient.button) : AnyShapeStyle(Color.white.opacity(0.25)))
                }
                .sensoryFeedback(.impact(weight: .light), trigger: appState.isLikedSong(song.id))
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

    /// Mirrors `MixtapesGridView`: only show the "save your first song"
    /// empty state until the user has any content — the Liked tile appears
    /// as soon as they like a song.
    private var showFirstMixtapeState: Bool {
        appState.mixtapeStore.userMixtapes.isEmpty
            && appState.likedSongs.isEmpty
            && appState.likedShareIds.isEmpty
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if showFirstMixtapeState {
                    FirstMixtapeEmptyState().padding(.top, 48)
                } else if mixtapes.isEmpty {
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
    @State private var showAddSongs: Bool = false
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

                                if isOwner {
                                    addSongsSearchBar
                                        .padding(.top, 14)
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
                                            SongListRow(song: song, appState: appState) {
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
        .sheet(isPresented: $showAddSongs) {
            AddSongsToMixtapeSheet(mixtape: liveMixtape, appState: appState)
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

    private var addSongsSearchBar: some View {
        Button {
            showAddSongs = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
                Text("add more songs")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.58))
                Spacer(minLength: 0)
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add more songs")
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

// MARK: - Add songs to mixtape

/// Search surface launched from `MixtapeDetailView`. It mirrors the main
/// song-search UI but keeps the action scoped to one mixtape: song rows get
/// an animated Add/Saved button instead of the send-to-friends step.
private struct AddSongsToMixtapeSheet: View {
    let mixtape: Mixtape
    let appState: AppState

    @Environment(\.dismiss) private var dismiss
    @State private var searchText: String = ""
    @State private var searchTask: Task<Void, Never>?
    @State private var detailArtist: ArtistSummary?
    @State private var detailAlbum: Album?
    @State private var audioPlayer: AudioPlayerService = .shared
    @State private var savingSongIds: Set<String> = []
    @State private var addedSongIds: Set<String> = []
    @State private var duplicateMixtapeSong: Song?
    @FocusState private var isSearchFocused: Bool

    private var liveMixtape: Mixtape {
        appState.mixtapeStore.mixtape(withId: mixtape.id) ?? mixtape
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    header
                    searchField

                    if !searchText.isEmpty && !appState.searchResults.isEmpty {
                        SearchFilterBar(selection: Binding(
                            get: { appState.searchFilter },
                            set: { appState.searchFilter = $0 }
                        ))
                        .padding(.bottom, 4)
                    }

                    AppScrollView {
                        LazyVStack(spacing: 0) {
                            if appState.isSearchingSongs && appState.searchResults.isEmpty {
                                ProgressView()
                                    .tint(.white)
                                    .padding(.top, 40)
                            } else if searchText.isEmpty {
                                hintView
                            } else if appState.searchResults.isEmpty {
                                noResultsView
                            } else {
                                resultsContent
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .task {
                try? await Task.sleep(for: .milliseconds(350))
                isSearchFocused = true
            }
            .onDisappear {
                searchTask?.cancel()
            }
        }
        .presentationBackground(.black)
        .preferredColorScheme(.dark)
        .sheet(item: $detailArtist) { artist in
            ArtistView(artistId: artist.id, initialArtistName: artist.name, appState: appState)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $detailAlbum) { album in
            AlbumDetailView(album: album, appState: appState)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .alert("Already added", isPresented: Binding(
            get: { duplicateMixtapeSong != nil },
            set: { if !$0 { duplicateMixtapeSong = nil } }
        )) {
            Button("OK", role: .cancel) {
                duplicateMixtapeSong = nil
            }
        } message: {
            Text("This song is already in \(liveMixtape.name).")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("add more songs")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)
            Text(liveMixtape.name)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 18)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.white.opacity(0.4))
            AppTextField("Search songs or artists...", text: $searchText, submitLabel: .search) {
                isSearchFocused = false
            }
                .foregroundStyle(.white)
                .tint(.white)
                .autocorrectionDisabled()
                .focused($isSearchFocused)
                .onChange(of: searchText) { _, newValue in
                    performSearch(newValue)
                }

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    appState.searchResults = .empty
                    appState.isSearchingSongs = false
                    searchTask?.cancel()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.08))
        .clipShape(.rect(cornerRadius: 12))
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var resultsContent: some View {
        switch appState.searchFilter {
        case .all:     allGroupedContent
        case .artists: artistsFullList
        case .songs:   songsFullList
        case .albums:  albumsFullList
        }
    }

    @ViewBuilder
    private var allGroupedContent: some View {
        let results = appState.searchResults

        if let top = results.topHit {
            ArtistResultHeader()
            topHitRow(top)
                .overlay(alignment: .bottom) {
                    Color.white.opacity(0.05).frame(height: 0.5)
                }
        }

        let artists = Array(results.artists.prefix(3).filter { artist in
            if case .artist(let top) = results.topHit, top.id == artist.id { return false }
            return true
        })
        if !artists.isEmpty {
            SearchSectionHeader(title: "Artists", onSeeAll: results.artists.count > artists.count ? {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                appState.searchFilter = .artists
            } : nil)
            ForEach(artists) { artist in
                ArtistResultRow(artist: artist) {
                    detailArtist = artist
                }
                .id(artist.id)
                .overlay(alignment: .bottom) {
                    Color.white.opacity(0.05).frame(height: 0.5)
                }
            }
        }

        let songs = Array(results.songs.prefix(4).filter { song in
            if case .song(let top) = results.topHit, top.id == song.id { return false }
            return true
        })
        if !songs.isEmpty {
            SearchSectionHeader(title: "Songs", onSeeAll: results.songs.count > songs.count ? {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                appState.searchFilter = .songs
            } : nil)
            ForEach(songs) { song in
                songRow(song)
            }
        }

        let albums = Array(results.albums.prefix(3).filter { album in
            if case .album(let top) = results.topHit, top.id == album.id { return false }
            return true
        })
        if !albums.isEmpty {
            SearchSectionHeader(title: "Albums", onSeeAll: results.albums.count > albums.count ? {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                appState.searchFilter = .albums
            } : nil)
            ForEach(albums) { album in
                AlbumResultRow(album: album, onTap: { detailAlbum = album })
                    .id(album.id)
                    .overlay(alignment: .bottom) {
                        Color.white.opacity(0.05).frame(height: 0.5)
                    }
            }
        }
    }

    @ViewBuilder
    private var artistsFullList: some View {
        ForEach(appState.searchResults.artists) { artist in
            ArtistResultRow(artist: artist) {
                detailArtist = artist
            }
            .id(artist.id)
            .overlay(alignment: .bottom) {
                Color.white.opacity(0.05).frame(height: 0.5)
            }
        }
    }

    @ViewBuilder
    private var songsFullList: some View {
        ForEach(appState.searchResults.songs) { song in
            songRow(song)
        }
    }

    @ViewBuilder
    private var albumsFullList: some View {
        ForEach(appState.searchResults.albums) { album in
            AlbumResultRow(album: album, onTap: { detailAlbum = album })
                .id(album.id)
                .overlay(alignment: .bottom) {
                    Color.white.opacity(0.05).frame(height: 0.5)
                }
        }
    }

    @ViewBuilder
    private func topHitRow(_ hit: SearchResults.TopHit) -> some View {
        switch hit {
        case .artist(let artist):
            ArtistResultRow(artist: artist) {
                detailArtist = artist
            }
            .id(artist.id)
        case .song(let song):
            songRow(song)
        case .album(let album):
            AlbumResultRow(album: album, onTap: { detailAlbum = album })
                .id(album.id)
        }
    }

    private var hintView: some View {
        VStack(spacing: 12) {
            Image(systemName: "music.magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(.white.opacity(0.15))
            Text("Search for songs to add")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.3))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private var noResultsView: some View {
        VStack(spacing: 14) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(.white.opacity(0.15))
            Text("No results for \"\(searchText)\"")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.3))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private func performSearch(_ query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            appState.searchResults = .empty
            appState.isSearchingSongs = false
            return
        }
        appState.isSearchingSongs = true
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await appState.searchSongs(query: trimmed)
        }
    }

    private func songRow(_ song: Song) -> some View {
        let isPlaying = audioPlayer.currentSongId == song.id && audioPlayer.isPlaying
        let isLoading = audioPlayer.currentSongId == song.id && audioPlayer.isLoading
        let isSaved = isSongInLiveMixtape(song)
        let isSaving = savingSongIds.contains(song.id)

        return HStack(spacing: 14) {
            ZStack {
                Color(.systemGray5)
                    .frame(width: 56, height: 56)
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
                            .frame(width: 32, height: 32)

                        if isLoading {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.6)
                        } else {
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .contentTransition(.symbolEffect(.replace))
                        }
                    }
                }
                .sensoryFeedback(.impact(weight: .light), trigger: isPlaying)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(song.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let artistId = song.artistId {
                    Button {
                        detailArtist = ArtistSummary(
                            id: artistId,
                            name: song.artist,
                            primaryGenre: nil
                        )
                    } label: {
                        Text(song.artist.uppercased())
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.4))
                            .tracking(0.5)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(song.artist.uppercased())
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                        .tracking(0.5)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            addButton(song: song, isSaved: isSaved, isSaving: isSaving)
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Color.white.opacity(0.05)
                .frame(height: 0.5)
        }
    }

    private func addButton(song: Song, isSaved: Bool, isSaving: Bool) -> some View {
        Button {
            guard !isSaving else { return }
            guard !isSaved else {
                duplicateMixtapeSong = song
                return
            }
            savingSongIds.insert(song.id)
            Task {
                await appState.mixtapeStore.addSong(song, to: liveMixtape.id)
                await MainActor.run {
                    savingSongIds.remove(song.id)
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.65)) {
                        _ = addedSongIds.insert(song.id)
                    }
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            }
        } label: {
            HStack(spacing: 5) {
                if isSaving {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.65)
                } else {
                    Image(systemName: isSaved ? "checkmark" : "plus")
                        .font(.system(size: 12, weight: .bold))
                        .contentTransition(.symbolEffect(.replace))
                }
                Text(isSaved ? "Added" : "Add")
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundStyle(isSaved ? .black : .white)
            .frame(minWidth: 66, minHeight: 34)
            .background(isSaved ? Color.white : Color.white.opacity(0.1), in: Capsule())
            .scaleEffect(isSaved ? 1.04 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(isSaving)
        .animation(.spring(response: 0.28, dampingFraction: 0.65), value: isSaved)
        .sensoryFeedback(.success, trigger: addedSongIds)
        .accessibilityLabel(isSaved ? "Added to mixtape" : "Add to mixtape")
    }

    private func isSongInLiveMixtape(_ song: Song) -> Bool {
        liveMixtape.songs.contains { $0.id == song.id }
            || appState.saveService.mixtapeIds(forSongId: song.id).contains(liveMixtape.id)
            || addedSongIds.contains(song.id)
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
    @State private var showPhotoEditor = false

    private var user: AppUser? { appState.currentUser }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 16) {
                    Button {
                        showPhotoEditor = true
                    } label: {
                        AppUserAvatar(user: user, size: 96, background: Color.white.opacity(0.12))
                            .overlay(alignment: .bottomTrailing) {
                                ZStack {
                                    Circle()
                                        .fill(Color.black)
                                        .frame(width: 32, height: 32)
                                    Circle()
                                        .fill(AppAccentGradient.button)
                                        .frame(width: 28, height: 28)
                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(.black)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 32)

                    Button {
                        showPhotoEditor = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "pencil")
                                .font(.system(size: 11, weight: .bold))
                            Text("Edit")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Color.white.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)

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
        .sheet(isPresented: $showPhotoEditor) {
            ProfilePhotoEditorView(appState: appState)
                .presentationBackground(.black)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - Library pager

/// Two-page horizontal pager for the Library tab (Songs <-> Mixtapes) that
/// replaces a page-style `TabView`. It owns the swipe so a right-swipe off
/// the Songs page hands straight to the main Search tab with no rubber-band
/// bounce (the old `TabView` edge-bounced the leftmost page while the global
/// gesture switched tabs, which read as clunky). Only predominantly
/// horizontal drags page; vertical drags fall through to the inner scroll.
private struct LibraryPager<SongsContent: View, MixtapesContent: View>: View {
    @Binding var segment: MixtapesSegment
    var onSwipeRightFromSongs: () -> Void
    @ViewBuilder var songs: () -> SongsContent
    @ViewBuilder var mixtapes: () -> MixtapesContent

    @State private var dragOffset: CGFloat = 0
    /// nil = axis undecided, true = horizontal (we drive paging), false =
    /// vertical (ignore so the inner scroll view keeps the gesture).
    @State private var horizontalLock: Bool?

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let base: CGFloat = segment == .songs ? 0 : -width

            HStack(spacing: 0) {
                songs().frame(width: width)
                mixtapes().frame(width: width)
            }
            .frame(width: width * 2, alignment: .leading)
            .offset(x: base + dragOffset)
            .simultaneousGesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { value in
                        let h = value.translation.width
                        let v = value.translation.height
                        if horizontalLock == nil {
                            if abs(h) > 12 || abs(v) > 12 {
                                horizontalLock = abs(h) > abs(v)
                            }
                        }
                        guard horizontalLock == true else { return }
                        dragOffset = resisted(h, width: width)
                    }
                    .onEnded { value in
                        defer { horizontalLock = nil }
                        guard horizontalLock == true else { return }
                        let h = value.translation.width
                        let predicted = value.predictedEndTranslation.width
                        let threshold = max(60, width * 0.22)

                        if segment == .songs {
                            if h < -threshold || predicted < -threshold {
                                withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
                                    segment = .mixtapes
                                    dragOffset = 0
                                }
                            } else if h > threshold || predicted > threshold {
                                onSwipeRightFromSongs()
                                dragOffset = 0
                            } else {
                                withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
                                    dragOffset = 0
                                }
                            }
                        } else {
                            if h > threshold || predicted > threshold {
                                withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
                                    segment = .songs
                                    dragOffset = 0
                                }
                            } else {
                                withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
                                    dragOffset = 0
                                }
                            }
                        }
                    }
            )
        }
        .clipped()
    }

    /// Full tracking toward an existing neighbor page; strong resistance when
    /// dragging past an edge (Songs->right escape, Mixtapes->left dead end)
    /// so there is a small hint without the elastic spring-back.
    private func resisted(_ h: CGFloat, width: CGFloat) -> CGFloat {
        let pastEdge = (segment == .songs && h > 0) || (segment == .mixtapes && h < 0)
        guard pastEdge else {
            return max(-width, min(width, h))
        }
        return h * 0.18
    }
}

// MARK: - Day carousel seed

/// Identifiable payload for the Locket-style day carousel `.fullScreenCover`.
struct DayCarouselSeed: Identifiable {
    let id = UUID()
    let groups: [DaySongGroup]
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
