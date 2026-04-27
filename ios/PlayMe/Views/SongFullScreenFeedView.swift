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

    init(
        songs: [Song],
        startIndex: Int,
        appState: AppState,
        shareLookup: ((String) -> SongShare?)? = nil
    ) {
        self.songs = songs
        self.startIndex = startIndex
        self.appState = appState
        self.shareLookup = shareLookup
        // Seed `visibleSongId` synchronously at view-init so
        // `.scrollPosition(id:)` has a target by the first layout pass.
        // Without this, the LazyVStack only renders the first ~2 pages
        // initially and a far-down seed (e.g. tapping the 50th song in
        // the Discover grid) silently lands on page 0 — which the user
        // experiences as "autoplay broken" because they hear the
        // tapped song while looking at a different page.
        let safe = min(max(0, startIndex), max(0, songs.count - 1))
        let seedId = songs.indices.contains(safe) ? songs[safe].id : nil
        _visibleSongId = State(initialValue: seedId)
    }

    var body: some View {
        // Top-level `.ignoresSafeArea()` so this view truly takes the full
        // screen edge-to-edge — TikTok-style — and, critically, so the
        // `GeometryReader`'s `pageGeo.size` matches the `ScrollView`'s
        // visible viewport. Earlier this was inverted: the `GeometryReader`
        // measured inside the safe area while the `ScrollView` itself
        // ignored it, so each page was ~80pt shorter than the snap
        // distance and every swipe accumulated that gap (the layout
        // looked centered on page 0 and drifted further off on every
        // following page).
        //
        // With `.ignoresSafeArea()` on the root: pageGeo.size == full
        // screen on every device, snap interval == page height, the feed
        // stays perfectly centered no matter how far you scroll, and
        // `pageGeo.safeAreaInsets` still reports the system insets so we
        // can keep the close button below the notch and let each page's
        // top/bottom `Spacer(minLength: 0)` absorb the home-indicator
        // strip naturally.
        GeometryReader { pageGeo in
            let pageSize = pageGeo.size
            let topInset = pageGeo.safeAreaInsets.top

            ZStack(alignment: .topLeading) {
                Color.black

                ScrollViewReader { proxy in
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
                    .onChange(of: visibleSongId) { _, newValue in
                        guard let newValue, let song = songs.first(where: { $0.id == newValue }) else { return }
                        coordinator.onVisibleSongChanged(to: song)
                    }
                    .onAppear {
                        // Force the LazyVStack to materialize the seed
                        // page — the bare `.scrollPosition` binding can
                        // no-op on a far-down seed if that id hasn't been
                        // laid out yet — then start playback immediately.
                        // The 50ms artificial sleep that used to live here
                        // was hiding latency, not avoiding a real race;
                        // the actual race (audio session not yet active)
                        // is handled inside `AudioPlayerService` setup.
                        guard let target = visibleSongId,
                              let song = songs.first(where: { $0.id == target }) else { return }
                        proxy.scrollTo(target, anchor: .top)
                        coordinator.startInitial(song: song)
                    }
                }

                closeButton
                    .padding(.top, topInset + 12)
                    .padding(.leading, 16)
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
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
