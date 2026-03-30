import SwiftUI

struct SendSongSheet: View {
    @Environment(\.dismiss) private var dismiss
    let appState: AppState

    @State private var searchText: String = ""
    @State private var selectedSong: Song?
    @State private var step: Int = 0
    @State private var searchTask: Task<Void, Never>?

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
                        onBack: { withAnimation(.spring(duration: 0.3)) { step = 0 } },
                        onSent: { dismiss() }
                    )
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .trailing)))
                }
            }
            .animation(.spring(duration: 0.3), value: step)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(width: 32, height: 32)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Circle())
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .presentationBackground(.black)
    }

    private var songSearchView: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom) {
                Text("search a song")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)

                Spacer()

                if appState.spotifyAuth.isAuthenticated {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color(red: 0.11, green: 0.73, blue: 0.33))
                            .frame(width: 6, height: 6)
                        Text("Spotify")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color(red: 0.11, green: 0.73, blue: 0.33))
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 20)

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.white.opacity(0.4))
                TextField("Search songs or artists...", text: $searchText)
                    .foregroundStyle(.white)
                    .autocorrectionDisabled()
                    .onChange(of: searchText) { _, newValue in
                        performSearch(newValue)
                    }

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        appState.searchResults = []
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
                    } else if appState.searchResults.isEmpty {
                        noResultsView
                    } else {
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
        HStack(spacing: 14) {
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

                if song.previewURL != nil {
                    Button {
                        appState.audioPlayer.play(song: song)
                    } label: {
                        let isThisSong = appState.audioPlayer.currentSong?.id == song.id
                        Image(systemName: isThisSong && appState.audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(.black.opacity(0.6))
                            .clipShape(Circle())
                    }
                    .sensoryFeedback(.impact(weight: .light), trigger: appState.audioPlayer.currentSong?.id)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(song.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if song.spotifyID != nil {
                        Image(systemName: "waveform")
                            .font(.system(size: 9))
                            .foregroundStyle(Color(red: 0.11, green: 0.73, blue: 0.33))
                    }
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
        .overlay(alignment: .bottom) {
            Color.white.opacity(0.05)
                .frame(height: 0.5)
        }
    }
}
