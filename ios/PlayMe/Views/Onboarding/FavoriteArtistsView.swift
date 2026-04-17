import SwiftUI

/// Onboarding step 6: pick a few favorite artists via a typeahead chip picker.
/// Feeds `SongSuggestionsService` on the "send first song" step.
struct FavoriteArtistsView: View {
    let appState: AppState
    let onContinue: () -> Void
    let onSkip: () -> Void

    @State private var query: String = ""
    @State private var suggestions: [String] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var searchFocused: Bool

    private let maxArtists = 5
    private let recommendedArtists = 3

    private var selected: [String] { appState.favoriteArtists }

    private var canContinue: Bool { selected.count >= 1 }

    private var filteredSuggestions: [String] {
        let lowerSelected = Set(selected.map { $0.lowercased() })
        return suggestions.filter { !lowerSelected.contains($0.lowercased()) }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                header

                searchField
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                if !selected.isEmpty {
                    selectedChipsView
                        .padding(.horizontal, 20)
                        .padding(.top, 14)
                }

                suggestionsList
                    .padding(.top, 8)

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
            // Prompt the keyboard immediately — the screen is just this picker.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                searchFocused = true
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Who are a few of your\nfavorite artists?")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                    .lineSpacing(2)
                Spacer(minLength: 0)
                Button("Skip", action: onSkip)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
            }

            Text("Pick at least \(recommendedArtists) so we can suggest songs you'd love to share.")
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
            TextField("Search artists", text: $query)
                .foregroundStyle(.white)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)
                .submitLabel(.search)
                .focused($searchFocused)
                .onChange(of: query) { _, newValue in
                    performSearch(newValue)
                }

            if !query.isEmpty {
                Button {
                    query = ""
                    suggestions = []
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

    private var selectedChipsView: some View {
        FlowLayout(spacing: 8) {
            ForEach(selected, id: \.self) { artist in
                selectedChip(artist)
            }
        }
    }

    private func selectedChip(_ artist: String) -> some View {
        HStack(spacing: 6) {
            Text(artist)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
            Button {
                removeArtist(artist)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(red: 0.76, green: 0.38, blue: 0.35))
        .clipShape(.capsule)
    }

    private var suggestionsList: some View {
        Group {
            if isSearching {
                ProgressView()
                    .tint(.white.opacity(0.6))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)
            } else if !query.isEmpty && filteredSuggestions.isEmpty {
                Text("No artists found for \"\(query)\"")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.3))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)
            } else if query.isEmpty && selected.isEmpty {
                hintView
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredSuggestions, id: \.self) { artist in
                            suggestionRow(artist)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
    }

    private var hintView: some View {
        VStack(spacing: 10) {
            Image(systemName: "music.mic")
                .font(.system(size: 32))
                .foregroundStyle(.white.opacity(0.15))
            Text("Start typing an artist's name")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.3))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
    }

    private func suggestionRow(_ artist: String) -> some View {
        Button {
            addArtist(artist)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "music.mic")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 32, height: 32)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Circle())

                Text(artist)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer()

                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Color.white.opacity(0.05).frame(height: 0.5)
        }
        .disabled(selected.count >= maxArtists)
        .opacity(selected.count >= maxArtists ? 0.35 : 1)
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            Button {
                searchFocused = false
                onContinue()
            } label: {
                Text(continueLabel)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(canContinue ? .black : .white.opacity(0.4))
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(canContinue ? Color.white : Color.white.opacity(0.12))
                    .clipShape(.rect(cornerRadius: 25))
            }
            .disabled(!canContinue)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.94))
    }

    private var continueLabel: String {
        if selected.isEmpty { return "Pick at least 1 artist" }
        if selected.count < recommendedArtists {
            return "Continue (\(selected.count)/\(recommendedArtists))"
        }
        return "Continue"
    }

    // MARK: - Actions

    private func addArtist(_ artist: String) {
        guard selected.count < maxArtists else { return }
        guard !selected.contains(where: { $0.lowercased() == artist.lowercased() }) else { return }
        var current = appState.favoriteArtists
        current.append(artist)
        appState.favoriteArtists = current
    }

    private func removeArtist(_ artist: String) {
        appState.favoriteArtists.removeAll { $0.lowercased() == artist.lowercased() }
    }

    private func performSearch(_ term: String) {
        searchTask?.cancel()
        let trimmed = term.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            suggestions = []
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            do {
                let results = try await MusicSearchService.shared.searchArtists(term: trimmed, limit: 12)
                if Task.isCancelled { return }
                await MainActor.run {
                    self.suggestions = results.map { $0.artistName }
                    self.isSearching = false
                }
            } catch {
                await MainActor.run {
                    self.suggestions = []
                    self.isSearching = false
                }
            }
        }
    }
}

// MARK: - FlowLayout

/// Minimal flow layout so selected-artist chips wrap across multiple lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += rowHeight + spacing
                rowHeight = 0
            }
            currentX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            totalHeight = currentY + rowHeight
        }

        return CGSize(width: maxWidth == .infinity ? currentX : maxWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX: CGFloat = bounds.minX
        var currentY: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX && currentX > bounds.minX {
                currentX = bounds.minX
                currentY += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: currentX, y: currentY), proposal: ProposedViewSize(size))
            currentX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
