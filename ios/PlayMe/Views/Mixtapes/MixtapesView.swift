import SwiftUI

/// Top-level segments of the Mixtapes tab. Order matches the spec:
/// Songs (default) | Mixtapes | Sent | Received | Liked.
enum MixtapesSegment: String, CaseIterable, Identifiable {
    case songs = "Songs"
    case mixtapes = "Mixtapes"
    case sent = "Sent"
    case received = "Received"
    case liked = "Liked"

    var id: String { rawValue }
}

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

    @State private var selectedSegment: MixtapesSegment = .songs
    @State private var searchText: String = ""
    @State private var showSettings: Bool = false
    @State private var showProfileDetails: Bool = false
    @State private var fullscreenSeed: FullscreenSeed?
    @State private var detailMixtape: Mixtape?

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

                    contentForSegment
                }
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

    // MARK: - Segment content

    @ViewBuilder
    private var contentForSegment: some View {
        switch selectedSegment {
        case .songs:
            SongsGridView(
                appState: appState,
                searchText: searchText,
                onTap: { songs, idx in
                    fullscreenSeed = FullscreenSeed(songs: songs, startIndex: idx)
                }
            )
        case .mixtapes:
            MixtapesGridView(
                appState: appState,
                searchText: searchText,
                onTap: { mixtape in
                    detailMixtape = mixtape
                }
            )
        case .sent:
            shareList(appState.sentShares.filter(matchesSearch))
        case .received:
            shareList(appState.receivedShares.filter(matchesSearch))
        case .liked:
            shareList(appState.likedShares.filter(matchesSearch))
        }
    }

    private func shareList(_ shares: [SongShare]) -> some View {
        let lookupMap: [String: SongShare] = Dictionary(uniqueKeysWithValues: shares.map { ($0.song.id, $0) })
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

    private func matchesSearch(_ share: SongShare) -> Bool {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return true }
        return share.song.title.lowercased().contains(q)
            || share.song.artist.lowercased().contains(q)
            || (share.note ?? "").lowercased().contains(q)
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
                            Button {
                                if let idx = filtered.firstIndex(where: { $0.id == song.id }) {
                                    onTap(filtered, idx)
                                }
                            } label: {
                                AlbumArtSquare(
                                    url: song.albumArtURL,
                                    cornerRadius: 14,
                                    showsPlaceholderProgress: false,
                                    showsShadow: false,
                                    targetDecodeSide: side
                                )
                            }
                            .buttonStyle(.plain)
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
                            Button {
                                onTap(mixtape)
                            } label: {
                                VStack(spacing: 6) {
                                    MixtapeCoverView(mixtape: mixtape, cornerRadius: 14, showsShadow: false)
                                    Text(mixtape.name)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 4)
                                }
                            }
                            .buttonStyle(.plain)
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
    @State private var showRename: Bool = false
    @State private var renameText: String = ""

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
                let cellSize = PinterestGridLayout.cellSize(
                    containerWidth: geo.size.width,
                    horizontalPadding: horizontalPadding,
                    spacing: spacing
                )
                ZStack {
                    Color.black.ignoresSafeArea()

                    ScrollView {
                        VStack(spacing: 0) {
                            header
                                .padding(.horizontal, 20)
                                .padding(.top, 12)
                                .padding(.bottom, 18)

                            if liveMixtape.songs.isEmpty {
                                emptyState.padding(.top, 60)
                            } else {
                                PinterestSquareGrid(
                                    items: liveMixtape.songs,
                                    cellSize: cellSize,
                                    spacing: spacing
                                ) { song, side in
                                    Button {
                                        if let idx = liveMixtape.songs.firstIndex(where: { $0.id == song.id }) {
                                            fullscreenSeed = FullscreenSeed(
                                                songs: liveMixtape.songs,
                                                startIndex: idx
                                            )
                                        }
                                    } label: {
                                        AlbumArtSquare(
                                            url: song.albumArtURL,
                                            cornerRadius: 14,
                                            showsPlaceholderProgress: false,
                                            showsShadow: false,
                                            targetDecodeSide: side
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, horizontalPadding)
                                .padding(.bottom, 32)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .navigationTitle(liveMixtape.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.white)
                }
                if !liveMixtape.isSystemLiked {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button {
                                renameText = liveMixtape.name
                                showRename = true
                            } label: {
                                Label("Rename", systemImage: "pencil")
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
        .alert("Rename mixtape", isPresented: $showRename) {
            TextField("Mixtape name", text: $renameText)
            Button("Save") {
                Task { await appState.mixtapeStore.rename(mixtapeId: liveMixtape.id, to: renameText) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            MixtapeCoverView(mixtape: liveMixtape, cornerRadius: 12, showsShadow: false)
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 2) {
                Text(liveMixtape.name)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("\(liveMixtape.songCount) song\(liveMixtape.songCount == 1 ? "" : "s")")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.5))
                if liveMixtape.isSystemLiked {
                    Text("Auto-built from your liked songs")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            Spacer()
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
