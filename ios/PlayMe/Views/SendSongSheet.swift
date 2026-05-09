import SwiftUI

struct SendSongSheet: View {
    @Environment(\.dismiss) private var dismiss
    let appState: AppState
    /// Extra invited (pending-signup) contacts to offer as recipients alongside
    /// real friends. Defaults to empty, so main-app call sites keep their
    /// existing friends-only behavior. The onboarding flow passes
    /// `appState.invitedContacts` so a freshly registered user can still send
    /// their first song to someone who hasn't joined yet.
    var invitedContacts: [SimpleContact] = []
    /// Existing users the new account requested by username during onboarding.
    /// They are real PlayMe accounts, but they may not be accepted friends yet,
    /// so the first-song flow threads them separately into the recipient row.
    var onboardingRequestedUsers: [AppUser] = []
    /// Fired once the underlying `FriendSelectorView` reports a successful
    /// send (right before the sheet dismisses). Lets onboarding advance to
    /// the next step without needing to observe dismissal externally.
    var onSent: (() -> Void)? = nil

    @State private var searchText: String = ""
    @State private var selectedSong: Song?
    @State private var step: Int = 0
    @State private var searchTask: Task<Void, Never>?
    @State private var detailArtist: ArtistSummary?
    @State private var detailAlbum: Album?
    /// Album the user wants to share with friends. Optional-driven
    /// recipient picker — same pattern as the mixtape-share button.
    /// Save-to-mixtape for albums is reached from the share view's
    /// bookmark icon, not from the search-result row, so there is no
    /// `saveAlbum` state mirrored here.
    @State private var shareAlbum: Album?
    @State private var audioPlayer: AudioPlayerService = .shared
    @AppStorage("songSearch.recentQueries") private var recentSearchesRaw: String = "[]"
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if step == 0 {
                    songSearchView
                        .transition(.asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .leading)))
                } else {
                    FriendSelectorView(
                        item: .song(selectedSong!),
                        appState: appState,
                        invitedContacts: invitedContacts,
                        onboardingRequestedUsers: onboardingRequestedUsers,
                        onBack: { withAnimation(.spring(duration: 0.3)) { step = 0 } },
                        onSent: {
                            onSent?()
                            dismiss()
                        }
                    )
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .trailing)))
                }
            }
            .animation(.spring(duration: 0.3), value: step)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // On step 1 the user is picking recipients for a song
                    // they already chose — the back chevron returns them to
                    // their search results in case they tapped the wrong
                    // row. On step 0 we keep the X for a full sheet dismiss.
                    Button {
                        if step == 1 {
                            withAnimation(.spring(duration: 0.3)) { step = 0 }
                        } else {
                            dismiss()
                        }
                    } label: {
                        Image(systemName: step == 1 ? "chevron.left" : "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(width: 32, height: 32)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Circle())
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .task {
                // iOS drops focus requests issued before the sheet's
                // presentation animation settles, so we wait out the
                // transition (~0.35s) and then focus the search field.
                // This runs once per sheet appearance — returning from
                // step 1 back to step 0 doesn't trigger it again, which
                // is the desired behavior.
                try? await Task.sleep(for: .milliseconds(350))
                if step == 0 {
                    isSearchFocused = true
                }
            }
        }
        .presentationBackground(.black)
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
        .sheet(item: $shareAlbum) { album in
            // Album shares run through the same unified share view as
            // songs. The view branches internally on `.album(...)` to
            // render the album artwork and dispatch via
            // `appState.sendAlbum` instead of the per-recipient song
            // fan-out.
            NavigationStack {
                FriendSelectorView(
                    item: .album(album),
                    appState: appState,
                    onBack: { shareAlbum = nil },
                    onSent: { shareAlbum = nil }
                )
            }
            .presentationBackground(.black)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private var songSearchView: some View {
        VStack(spacing: 0) {
            Text("search a song")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 20)

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.white.opacity(0.4))
                AppTextField("Search songs or artists...", text: $searchText, submitLabel: .search) {
                    commitCurrentSearch()
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

            if searchText.isEmpty {
                RecentSongSearchList(
                    searches: RecentSongSearchStore.decode(recentSearchesRaw),
                    onSelect: applyRecentSearch(_:),
                    onRemove: removeRecentSearch(_:)
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }

            // Filter tabs only surface once the user actually has results
            // to slice. Hiding them for empty/hint states keeps the first
            // impression clean.
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

    /// Slices the reranked buckets by the active filter. `.all` is the
    /// grouped Spotify-style view; every other filter is a full list of
    /// that entity type.
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

        // Artists — top 3, de-duped against the top hit so we don't show
        // the same artist twice back-to-back.
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
                    commitCurrentSearch()
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
                AlbumResultRow(
                    album: album,
                    onTap: {
                        commitCurrentSearch()
                        detailAlbum = album
                    },
                    onShareTap: {
                        commitCurrentSearch()
                        shareAlbum = album
                    }
                )
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
                commitCurrentSearch()
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
            AlbumResultRow(
                album: album,
                onTap: {
                    commitCurrentSearch()
                    detailAlbum = album
                },
                onShareTap: {
                    commitCurrentSearch()
                    shareAlbum = album
                }
            )
            .id(album.id)
            .overlay(alignment: .bottom) {
                Color.white.opacity(0.05).frame(height: 0.5)
            }
        }
    }

    /// Renders the absolute-best hit as a visually distinct "Top result"
    /// row. Artists use the round treatment; songs/albums reuse the
    /// square-thumbnail row styling so users can immediately play or
    /// explore without an extra tap.
    @ViewBuilder
    private func topHitRow(_ hit: SearchResults.TopHit) -> some View {
        switch hit {
        case .artist(let artist):
            ArtistResultRow(artist: artist) {
                commitCurrentSearch()
                detailArtist = artist
            }
            .id(artist.id)
        case .song(let song):
            songRow(song)
        case .album(let album):
            AlbumResultRow(
                album: album,
                onTap: {
                    commitCurrentSearch()
                    detailAlbum = album
                },
                onShareTap: {
                    commitCurrentSearch()
                    shareAlbum = album
                }
            )
            .id(album.id)
        }
    }

    private var hintView: some View {
        VStack(spacing: 12) {
            Image(systemName: "music.magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(.white.opacity(0.15))
            Text("Search for any song")
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

    private func commitCurrentSearch() {
        recentSearchesRaw = RecentSongSearchStore.adding(searchText, to: recentSearchesRaw)
    }

    private func applyRecentSearch(_ query: String) {
        isSearchFocused = false
        if searchText == query {
            performSearch(query)
        } else {
            searchText = query
        }
    }

    private func removeRecentSearch(_ query: String) {
        recentSearchesRaw = RecentSongSearchStore.removing(query, from: recentSearchesRaw)
    }

    private func songRow(_ song: Song) -> some View {
        let isPlaying = audioPlayer.currentSongId == song.id && audioPlayer.isPlaying
        let isLoading = audioPlayer.currentSongId == song.id && audioPlayer.isLoading

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
                // Tappable artist byline — routes to `ArtistView` when we
                // have a stable iTunes artistId. Legacy/shared songs
                // without an id fall back to plain text (matches the
                // convention used on `SongCardView`).
                if let artistId = song.artistId {
                    Button {
                        commitCurrentSearch()
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

            Spacer()

            Button {
                commitCurrentSearch()
                selectedSong = song
                withAnimation(.spring(duration: 0.3)) { step = 1 }
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.impact(weight: .light), trigger: selectedSong?.id)

            Text(song.duration)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.3))
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            // Row tap routes directly to the friend picker — the picker
            // now owns preview/scrub itself, so the intermediate detail
            // sheet is no longer worth an extra step. The back chevron on
            // that screen brings the user right back to these results.
            commitCurrentSearch()
            selectedSong = song
            withAnimation(.spring(duration: 0.3)) { step = 1 }
        }
        .overlay(alignment: .bottom) {
            Color.white.opacity(0.05)
                .frame(height: 0.5)
        }
    }
}

enum RecentSongSearchStore {
    static let limit = 8

    static func decode(_ raw: String) -> [String] {
        guard let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return decoded
    }

    static func adding(_ query: String, to raw: String) -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return raw }

        var searches = decode(raw)
        searches.removeAll { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
        searches.insert(trimmed, at: 0)
        return encode(Array(searches.prefix(limit)))
    }

    static func removing(_ query: String, from raw: String) -> String {
        encode(decode(raw).filter { $0 != query })
    }

    private static func encode(_ searches: [String]) -> String {
        guard let data = try? JSONEncoder().encode(searches),
              let raw = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return raw
    }
}

struct RecentSongSearchList: View {
    let searches: [String]
    let onSelect: (String) -> Void
    let onRemove: (String) -> Void

    var body: some View {
        if !searches.isEmpty {
            VStack(spacing: 0) {
                ForEach(searches, id: \.self) { query in
                    HStack(spacing: 10) {
                        Button {
                            onSelect(query)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.35))
                                Text(query)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.75))
                                    .lineLimit(1)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Button {
                            onRemove(query)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white.opacity(0.45))
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(query)")
                    }
                    .padding(.vertical, 9)

                    if query != searches.last {
                        Divider().background(Color.white.opacity(0.06))
                    }
                }
            }
        }
    }
}
