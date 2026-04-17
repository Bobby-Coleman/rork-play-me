import SwiftUI

/// Onboarding step 7: ask what the user has been listening to lately.
/// The user can tap a specific song OR confirm a plain artist string;
/// both feed SongSuggestionsService on the next step.
struct RecentlyListeningView: View {
    let appState: AppState
    let onContinue: () -> Void
    let onSkip: () -> Void

    @State private var query: String = ""
    @State private var results: [Song] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var searchFocused: Bool

    private var hasPickedSong: Bool { appState.recentListeningSong != nil }
    private var hasArtistText: Bool {
        !(appState.recentListeningArtist ?? "").trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var canContinue: Bool { hasPickedSong || hasArtistText }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                header

                searchField
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                if let picked = appState.recentListeningSong {
                    pickedSongView(picked)
                        .padding(.horizontal, 20)
                        .padding(.top, 14)
                }

                resultsList

                Spacer(minLength: 0)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomBar
            }
        }
        .toolbar {
            ToolbarItem(placement: .keyboard) {
                HStack {
                    Spacer(minLength: 0)
                    Button("Done") { searchFocused = false }
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                searchFocused = true
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("What have you been\nlistening to lately?")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                    .lineSpacing(2)
                Spacer(minLength: 0)
                Button("Skip", action: onSkip)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
            }

            Text("Pick a song or type an artist. We'll use this to suggest songs to share.")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.white.opacity(0.4))
            TextField("Search song or artist", text: $query)
                .foregroundStyle(.white)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)
                .submitLabel(.search)
                .focused($searchFocused)
                .onChange(of: query) { _, newValue in
                    // Clear any previously-picked song the moment the user types again
                    if appState.recentListeningSong != nil { appState.recentListeningSong = nil }
                    appState.recentListeningArtist = newValue.trimmingCharacters(in: .whitespaces).isEmpty ? nil : newValue
                    performSearch(newValue)
                }

            if !query.isEmpty {
                Button {
                    query = ""
                    results = []
                    appState.recentListeningSong = nil
                    appState.recentListeningArtist = nil
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
    }

    private func pickedSongView(_ song: Song) -> some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: song.albumArtURL)) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    Color.white.opacity(0.1)
                }
            }
            .frame(width: 52, height: 52)
            .clipShape(.rect(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text("Picked")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(red: 0.76, green: 0.38, blue: 0.35))
                    .textCase(.uppercase)
                Text(song.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(song.artist)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }

            Spacer()

            Button {
                appState.recentListeningSong = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Circle())
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.06))
        .clipShape(.rect(cornerRadius: 10))
    }

    private var resultsList: some View {
        Group {
            if hasPickedSong {
                EmptyView()
            } else if isSearching {
                ProgressView()
                    .tint(.white.opacity(0.6))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)
            } else if !query.isEmpty && results.isEmpty {
                VStack(spacing: 8) {
                    Text("No songs found for \"\(query)\"")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.3))
                    Text("Tap Continue to use \"\(query)\" as an artist.")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 24)
            } else if query.isEmpty {
                hintView
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(results) { song in
                            resultRow(song)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .padding(.top, 8)
    }

    private var hintView: some View {
        VStack(spacing: 10) {
            Image(systemName: "headphones")
                .font(.system(size: 32))
                .foregroundStyle(.white.opacity(0.15))
            Text("Start typing a song or artist")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.3))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
    }

    private func resultRow(_ song: Song) -> some View {
        Button {
            pickSong(song)
        } label: {
            HStack(spacing: 12) {
                AsyncImage(url: URL(string: song.albumArtURL)) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Color.white.opacity(0.1)
                    }
                }
                .frame(width: 44, height: 44)
                .clipShape(.rect(cornerRadius: 5))

                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(song.artist)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color(red: 0.76, green: 0.38, blue: 0.35))
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Color.white.opacity(0.05).frame(height: 0.5)
        }
    }

    private var bottomBar: some View {
        Button {
            searchFocused = false
            onContinue()
        } label: {
            Text(canContinue ? "Continue" : "Pick a song or type an artist")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(canContinue ? .black : .white.opacity(0.4))
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(canContinue ? Color.white : Color.white.opacity(0.12))
                .clipShape(.rect(cornerRadius: 25))
        }
        .disabled(!canContinue)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.94))
    }

    // MARK: - Actions

    private func pickSong(_ song: Song) {
        appState.recentListeningSong = song
        appState.recentListeningArtist = song.artist
        searchFocused = false
    }

    private func performSearch(_ term: String) {
        searchTask?.cancel()
        let trimmed = term.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            results = []
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            do {
                let songs = try await MusicSearchService.shared.search(term: trimmed, limit: 15)
                if Task.isCancelled { return }
                await MainActor.run {
                    self.results = songs
                    self.isSearching = false
                }
            } catch {
                await MainActor.run {
                    self.results = []
                    self.isSearching = false
                }
            }
        }
    }
}
