import SwiftUI

/// Song-search-only modal presented from the onboarding `SendFirstSongView`
/// when the user taps the big "search a song" CTA. Intentionally stripped
/// down compared to `SendSongSheet`:
///   * no friend selector, no detail sheet, no audio preview player — the
///     onboarding screen already owns recipient selection + send, so this
///     sheet's single job is to hand back a `Song`.
///   * debounce + row layout mirror the main search flow so the visual
///     language is consistent with the rest of the app.
struct OnboardingSongPickerSheet: View {
    let appState: AppState
    let onSelect: (Song) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText: String = ""
    @State private var results: [Song] = []
    @State private var isSearching: Bool = false
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                content
            }
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
        .onDisappear {
            searchTask?.cancel()
        }
    }

    // MARK: - Layout

    private var content: some View {
        VStack(spacing: 0) {
            Text("search a song")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 20)

            searchField
                .padding(.horizontal, 20)
                .padding(.bottom, 16)

            ScrollView {
                LazyVStack(spacing: 0) {
                    if isSearching {
                        ProgressView()
                            .tint(.white)
                            .padding(.top, 40)
                    } else if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                        hintView
                    } else if results.isEmpty {
                        noResultsView
                    } else {
                        ForEach(results) { song in
                            songRow(song)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.white.opacity(0.4))
            TextField("Search songs or artists...", text: $searchText)
                .foregroundStyle(.white)
                .tint(.white)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onChange(of: searchText) { _, newValue in
                    performSearch(newValue)
                }

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    results = []
                    isSearching = false
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

    private func songRow(_ song: Song) -> some View {
        Button {
            onSelect(song)
            dismiss()
        } label: {
            HStack(spacing: 14) {
                AsyncImage(url: URL(string: song.albumArtURL)) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Color.white.opacity(0.1)
                    }
                }
                .frame(width: 56, height: 56)
                .clipShape(.rect(cornerRadius: 6))

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

                Text(song.duration)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                Color.white.opacity(0.05)
                    .frame(height: 0.5)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Search

    private func performSearch(_ query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            results = []
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            if Task.isCancelled { return }
            do {
                let songs = try await MusicSearchService.shared.search(term: trimmed, limit: 25)
                if Task.isCancelled { return }
                await MainActor.run {
                    self.results = songs
                    self.isSearching = false
                }
            } catch {
                if Task.isCancelled { return }
                await MainActor.run {
                    self.results = []
                    self.isSearching = false
                }
            }
        }
    }
}
