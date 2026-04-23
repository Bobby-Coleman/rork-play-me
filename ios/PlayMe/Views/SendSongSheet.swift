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
    /// Fired once the underlying `FriendSelectorView` reports a successful
    /// send (right before the sheet dismisses). Lets onboarding advance to
    /// the next step without needing to observe dismissal externally.
    var onSent: (() -> Void)? = nil

    @State private var searchText: String = ""
    @State private var selectedSong: Song?
    @State private var step: Int = 0
    @State private var searchTask: Task<Void, Never>?
    @State private var detailArtist: ArtistSummary?
    @State private var audioPlayer: AudioPlayerService = .shared
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
                        song: selectedSong!,
                        appState: appState,
                        invitedContacts: invitedContacts,
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
                TextField("Search songs or artists...", text: $searchText)
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
                        appState.searchResults = []
                        appState.topArtistMatch = nil
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
            .padding(.bottom, 16)

            ScrollView {
                LazyVStack(spacing: 0) {
                    if appState.isSearchingSongs {
                        ProgressView()
                            .tint(.white)
                            .padding(.top, 40)
                    } else if searchText.isEmpty {
                        hintView
                    } else if appState.searchResults.isEmpty && appState.topArtistMatch == nil {
                        noResultsView
                    } else {
                        if let artist = appState.topArtistMatch {
                            ArtistResultHeader()
                            ArtistResultRow(artist: artist) {
                                detailArtist = artist
                            }
                            .overlay(alignment: .bottom) {
                                Color.white.opacity(0.05).frame(height: 0.5)
                            }
                            Text("SONGS")
                                .font(.system(size: 11, weight: .bold))
                                .tracking(1.5)
                                .foregroundStyle(.white.opacity(0.5))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 16)
                                .padding(.bottom, 4)
                        }
                        ForEach(appState.searchResults) { song in
                            songRow(song)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
            .scrollDismissesKeyboard(.interactively)
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
        VStack(spacing: 12) {
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
            appState.searchResults = []
            appState.topArtistMatch = nil
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
                Text(song.artist.uppercased())
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
                    .tracking(0.5)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                selectedSong = song
                withAnimation(.spring(duration: 0.3)) { step = 1 }
            } label: {
                Text("SHARE")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color(red: 0.76, green: 0.38, blue: 0.35))
                    .clipShape(.capsule)
            }
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
            selectedSong = song
            withAnimation(.spring(duration: 0.3)) { step = 1 }
        }
        .overlay(alignment: .bottom) {
            Color.white.opacity(0.05)
                .frame(height: 0.5)
        }
    }
}
