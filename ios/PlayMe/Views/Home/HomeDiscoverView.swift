import SwiftUI

/// Root of the new Home tab. Hosts a Pinterest-style staggered grid of
/// recommended songs that opens a TikTok-style fullscreen feed on tap.
///
/// Data flow:
/// 1. On first paint, seed `items` from
///    `PlaceholderDiscoverFeedProvider.cachedSongs()` so a returning user
///    sees the grid instantly without waiting on a network round-trip.
/// 2. Kick off `provider.loadInitial()` in `.task` to refresh the cache
///    in the background; replace `items` only if the provider returns a
///    non-empty list (so a transient failure never blanks the screen).
/// 3. Pull-to-refresh re-runs `loadInitial`.
///
/// The `provider` field is typed as `any DiscoverFeedProvider` so a real
/// recommendations service can later be wired in without touching this
/// view (or any of the grid plumbing).
struct HomeDiscoverView: View {
    let appState: AppState

    @State private var provider: any DiscoverFeedProvider = PlaceholderDiscoverFeedProvider()
    @State private var items: [Song] = PlaceholderDiscoverFeedProvider.cachedSongs()
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var fullscreenSeed: FullscreenSeed?

    private let horizontalPadding: CGFloat = 16
    private let spacing: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            let cellSize = PinterestGridLayout.cellSize(
                containerWidth: geo.size.width,
                horizontalPadding: horizontalPadding,
                spacing: spacing
            )

            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    LazyVStack(spacing: 0) {
                        if items.isEmpty && isLoading {
                            ProgressView()
                                .tint(.white)
                                .padding(.top, 80)
                        } else if items.isEmpty {
                            emptyState
                                .padding(.top, 80)
                        } else {
                            PinterestSquareGrid(
                                items: items,
                                cellSize: cellSize,
                                spacing: spacing
                            ) { song, side in
                                Button {
                                    openFullscreen(at: song)
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
                            .padding(.top, 12)
                            .padding(.bottom, 24)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .refreshable { await refresh(force: true) }
            }
        }
        .task {
            // Always refresh on appear if we don't have anything yet, or
            // if the cache is missing — `PlaceholderDiscoverFeedProvider`
            // owns its own freshness window, so we let it decide whether
            // to re-fetch.
            if items.isEmpty {
                await refresh(force: false)
            } else {
                Task { await refresh(force: false) }
            }
        }
        .fullScreenCover(item: $fullscreenSeed) { seed in
            SongFullScreenFeedView(
                songs: seed.songs,
                startIndex: seed.startIndex,
                appState: appState,
                shareLookup: seed.shareLookup
            )
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("Discover")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
            Text(errorMessage ?? "Pull to refresh and we'll line up some songs.")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    private func openFullscreen(at song: Song) {
        guard let idx = items.firstIndex(where: { $0.id == song.id }) else { return }
        fullscreenSeed = FullscreenSeed(songs: items, startIndex: idx)
    }

    private func refresh(force: Bool) async {
        if isLoading { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let fresh = try await provider.loadInitial()
            if !fresh.isEmpty {
                items = fresh
                errorMessage = nil
            } else if items.isEmpty && force {
                errorMessage = "No songs available right now."
            }
        } catch {
            if items.isEmpty {
                errorMessage = "Couldn't load Discover. Pull to retry."
            }
        }
    }
}

