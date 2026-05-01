import SwiftUI

/// Root of the Home tab (leftmost). Minimal offset grid of editorial songs
/// from `DiscoverSongFeedProvider`; tap opens the shared TikTok-style song
/// feed seeded with this curated order.
struct HomeDiscoverView: View {
    let appState: AppState

    @State private var provider: any DiscoverSongFeedProvider = FirestoreDiscoverSongFeedProvider()
    @State private var items: [Song] = []
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
                        Text("For You")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, horizontalPadding)
                            .padding(.top, 12)
                            .padding(.bottom, 4)

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
                                SongDiscoverGridCell(song: song, side: side)
                                    .onTapGesture {
                                        guard let idx = items.firstIndex(where: { $0.id == song.id }) else { return }
                                        AudioPlayerService.shared.play(song: song)
                                        fullscreenSeed = FullscreenSeed(songs: items, startIndex: idx)
                                    }
                            }
                            .padding(.horizontal, horizontalPadding)
                            .padding(.top, 8)
                            .padding(.bottom, 24)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .refreshable { await refresh(force: true) }
            }
        }
        .task {
            await refresh(force: false)
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
            Text(errorMessage ?? "Pull to refresh. Add documents to `featured_songs` in Firebase.")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    private func refresh(force: Bool) async {
        if isLoading { return }
        isLoading = true
        defer { isLoading = false }
        let fresh = await provider.loadInitial()
        items = fresh
        if fresh.isEmpty, force {
            errorMessage = "No curated songs yet."
        } else if !fresh.isEmpty {
            errorMessage = nil
        }
    }
}
