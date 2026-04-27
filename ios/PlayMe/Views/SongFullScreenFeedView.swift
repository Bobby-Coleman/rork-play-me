import SwiftUI
import UIKit

/// TikTok-style vertical paging feed of songs. Presented full-screen from
/// any "tap a song" entry point in the app — Discover grid, Mixtapes
/// Songs grid, Mixtape detail screen, etc. — and seeded with the source
/// list's order so the user can swipe through neighbors without
/// scrolling back to the grid.
///
/// Implementation mirrors the proven `DiscoveryView` pager:
/// `ScrollView(.vertical)` + `LazyVStack(spacing: 0)` of pages sized to
/// the page geometry, plus `.scrollTargetBehavior(.paging)` and
/// `.scrollPosition(id:)` so swipes snap cleanly between pages on every
/// device.
///
/// Autoplay is delegated to `FullScreenFeedPlaybackCoordinator` — the
/// coordinator pauses the previous song and starts the new one whenever
/// `visibleSongId` changes. Songs without a `previewURL` still render
/// (artwork, action row); they just don't autoplay (the coordinator logs
/// and skips so the next swipe still triggers correctly).
///
/// Optional `shareLookup` lets the caller provide per-song share context
/// — e.g. the Received feed entry that produced this `Song` — so the
/// page can keep the heart overlay tied to the existing share-based Like
/// model. When `nil` (Discover, Mixtapes Songs grid), the heart is
/// hidden.
struct SongFullScreenFeedView: View {
    /// Ordered list of songs to play through. Caller controls the order;
    /// the feed never reorders.
    let songs: [Song]
    /// Index in `songs` to seed playback at. Clamped on appear so an
    /// out-of-range value never crashes.
    let startIndex: Int
    let appState: AppState
    /// Optional resolver mapping `song.id` → `SongShare` so per-song
    /// share context is available to `SongFullScreenPage`. Only used
    /// when the feed was seeded from a share-bearing source (e.g. the
    /// Received list).
    var shareLookup: ((String) -> SongShare?)? = nil

    @State private var coordinator = FullScreenFeedPlaybackCoordinator()
    @State private var visibleSongId: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        GeometryReader { pageGeo in
            let pageSize = pageGeo.size

            ZStack(alignment: .topLeading) {
                Color.black.ignoresSafeArea()

                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(songs) { song in
                            SongFullScreenPage(
                                song: song,
                                pageSize: pageSize,
                                appState: appState,
                                share: shareLookup?(song.id)
                            )
                            .frame(width: pageSize.width, height: pageSize.height)
                            .clipped()
                            .id(song.id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $visibleSongId)
                .scrollIndicators(.hidden)
                .ignoresSafeArea(.container, edges: .vertical)
                .onChange(of: visibleSongId) { _, newValue in
                    guard let newValue, let song = songs.first(where: { $0.id == newValue }) else { return }
                    coordinator.onVisibleSongChanged(to: song)
                }

                closeButton
                    .padding(.top, pageGeo.safeAreaInsets.top + 12)
                    .padding(.leading, 16)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            // Clamp `startIndex` so a stale or out-of-range seed value
            // (e.g. the source list shrank between tap and present) never
            // crashes. Falling back to 0 keeps the feed usable.
            let safeIndex = min(max(0, startIndex), max(0, songs.count - 1))
            guard let seed = songs.indices.contains(safeIndex) ? songs[safeIndex] : nil else { return }
            visibleSongId = seed.id
            coordinator.startInitial(song: seed)
        }
        .onDisappear {
            // Don't yank `AudioPlayerService.stop()` here unconditionally:
            // doing so kills the mini-player on every dismiss. Only stop
            // the song the coordinator owns so other surfaces (Received
            // feed) stay in their own playback state.
            coordinator.stop()
        }
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 36, height: 36)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
        }
    }
}
