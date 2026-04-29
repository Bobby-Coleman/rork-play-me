import SwiftUI

struct QuickSendSongSheet: View {
    @Environment(\.dismiss) private var dismiss
    let recipient: AppUser
    let appState: AppState

    @State private var searchText: String = ""
    @State private var selectedSong: Song?
    @State private var step: Int = 0
    @State private var searchTask: Task<Void, Never>?
    @State private var detailArtist: ArtistSummary?
    @State private var detailAlbum: Album?
    /// Album the user wants to share with a friend. Save-to-mixtape for
    /// albums lives behind the share view's bookmark icon, not the
    /// search-result row, so this view doesn't need a `saveAlbum`
    /// counterpart.
    @State private var shareAlbum: Album?
    @State private var note: String = ""
    @State private var isSending: Bool = false
    @FocusState private var isNoteFocused: Bool
    @FocusState private var isSearchFocused: Bool
    @State private var audioPlayer: AudioPlayerService = .shared

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if step == 0 {
                    songSearchView
                        .transition(.asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .leading)))
                } else if let song = selectedSong {
                    composeView(song: song)
                        .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .trailing)))
                }
            }
            .animation(.spring(duration: 0.3), value: step)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // On the compose step, back returns to search results so
                    // the user can correct a mis-tapped row. The X only
                    // dismisses the whole sheet from the search step.
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
            // Routes album shares through the unified share view, same
            // as the song flow. Internal branching renders the album
            // artwork and dispatches via `appState.sendAlbum` rather
            // than per-recipient song writes.
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
            Text("Send to \(recipient.firstName)")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 20)

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.white.opacity(0.4))
                TextField("Search songs or artists...", text: $searchText)
                    .foregroundStyle(.white)
                    .autocorrectionDisabled()
                    .focused($isSearchFocused)
                    .submitLabel(.search)
                    // Return collapses focus; swipe-down on the
                    // results scroll view also dismisses the keyboard
                    // via `scrollDismissesKeyboard(.interactively)`.
                    .onSubmit { isSearchFocused = false }
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

            if !searchText.isEmpty && !appState.searchResults.isEmpty {
                SearchFilterBar(selection: Binding(
                    get: { appState.searchFilter },
                    set: { appState.searchFilter = $0 }
                ))
                .padding(.bottom, 4)
            }

            ScrollView {
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
            .scrollDismissesKeyboard(.interactively)
        }
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
                AlbumResultRow(
                    album: album,
                    onTap: { detailAlbum = album },
                    onShareTap: { shareAlbum = album }
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
                onTap: { detailAlbum = album },
                onShareTap: { shareAlbum = album }
            )
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
            AlbumResultRow(
                album: album,
                onTap: { detailAlbum = album },
                onShareTap: { shareAlbum = album }
            )
            .id(album.id)
        }
    }

    private func composeView(song: Song) -> some View {
        VStack(spacing: 0) {
            // The toolbar chevron now owns the back affordance — the
            // inline "Back" row used to sit here but was redundant next
            // to the toolbar button.
            Color(.systemGray5)
                .frame(width: 120, height: 120)
                .overlay {
                    AsyncImage(url: URL(string: song.albumArtURL)) { phase in
                        if let image = phase.image {
                            image.resizable().aspectRatio(contentMode: .fill)
                        }
                    }
                    .allowsHitTesting(false)
                }
                .clipShape(.rect(cornerRadius: 12))
                .padding(.top, 12)
                .padding(.bottom, 8)

            Text(song.title)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            Text(song.artist)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.5))
                .padding(.bottom, 16)

            TextField(
                "",
                text: $note,
                prompt: Text("Add a note (optional)").foregroundColor(.white.opacity(0.78))
            )
                .font(.system(size: 15))
                .foregroundStyle(.white)
                .focused($isNoteFocused)
                .submitLabel(.done)
                .onSubmit { isNoteFocused = false }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    Color.white.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.22), lineWidth: 0.5)
                )
                .shadow(color: .white.opacity(0.18), radius: 10, x: 0, y: 0)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)

            Button {
                Task {
                    isSending = true
                    await appState.sendSong(song, to: recipient, note: note.isEmpty ? nil : note)
                    isSending = false
                    dismiss()
                }
            } label: {
                Text(isSending ? "Sending…" : "Send to \(recipient.firstName)")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(red: 0.76, green: 0.38, blue: 0.35))
                    .clipShape(.rect(cornerRadius: 14))
            }
            .disabled(isSending)
            .padding(.horizontal, 20)

            Spacer()
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
            if appState.isMusicSearchDenied {
                Image(systemName: "music.note.list")
                    .font(.system(size: 36))
                    .foregroundStyle(.white.opacity(0.15))
                Text("Allow Apple Music access to search songs")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text("Open Settings")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(.white))
                }
            } else {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 36))
                    .foregroundStyle(.white.opacity(0.15))
                Text("No results for \"\(searchText)\"")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.3))
            }
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

            Spacer()

            Button {
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
            // Row tap routes directly to compose — preview/scrub live
            // alongside the Send button there, so the extra detail step
            // is no longer useful. Back chevron returns here.
            selectedSong = song
            withAnimation(.spring(duration: 0.3)) { step = 1 }
        }
        .overlay(alignment: .bottom) {
            Color.white.opacity(0.05)
                .frame(height: 0.5)
        }
    }
}
