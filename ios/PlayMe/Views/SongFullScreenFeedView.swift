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
    /// Pinterest-style horizontal-drag offset for swipe-right-to-dismiss.
    /// Driven by the `.simultaneousGesture` below; on release we either
    /// animate it back to 0 (cancel) or out to screen-width (commit dismiss)
    /// so the page visibly slides off the right edge before the
    /// `.fullScreenCover` itself dismisses.
    @State private var dragOffsetX: CGFloat = 0
    /// Latched once a dismiss is in flight so the gesture's `onChanged`
    /// can't yank `dragOffsetX` back during the slide-out animation.
    @State private var isDismissing: Bool = false
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
                        prewarmNeighbors(of: newValue)
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
                        // Prewarm the seed's neighbors so the second
                        // page is hot before the user even swipes once.
                        prewarmNeighbors(of: target)
                    }
                }

                closeButton
                    .padding(.top, topInset + 20)
                    .padding(.leading, 16)
            }
            .offset(x: dragOffsetX)
            // Swipe-right-to-dismiss. `.simultaneousGesture` so the
            // vertical paging gesture on the inner `ScrollView` keeps
            // working — we only react when the drag is *predominantly*
            // rightward (h > 0 and |h| > |v| * 1.5), which leaves the
            // vertical pager untouched on diagonal flicks.
            .simultaneousGesture(
                DragGesture(minimumDistance: 15)
                    .onChanged { value in
                        guard !isDismissing else { return }
                        let h = value.translation.width
                        let v = value.translation.height
                        guard h > 0, abs(h) > abs(v) * 1.5 else { return }
                        dragOffsetX = h
                    }
                    .onEnded { value in
                        guard !isDismissing else { return }
                        let h = value.translation.width
                        let predicted = value.predictedEndTranslation.width
                        if h > 100 || predicted > 220 {
                            performSlideDismiss(width: pageSize.width)
                        } else {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                                dragOffsetX = 0
                            }
                        }
                    }
            )
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .onDisappear {
            // Don't yank `AudioPlayerService.stop()` here unconditionally:
            // doing so kills the mini-player on every dismiss. Only stop
            // the song the coordinator owns so other surfaces (Received
            // feed) stay in their own playback state.
            coordinator.stop()
            // Drop pooled `AVPlayerItem`s so we don't keep megabytes of
            // audio resident on surfaces that aren't this feed.
            AudioPrewarmer.shared.clearAll()
        }
    }

    /// Pre-fetch `AVPlayerItem`s for the songs adjacent to `songId` so
    /// the next swipe (and the previous-page swipe-back) is near-
    /// instant. We prewarm `N+1`, `N+2`, and `N-1` — the next two
    /// because the user almost always swipes forward, and the previous
    /// one because the back-swipe is common too. The prewarmer is
    /// LRU-bounded to 5 items, so this never grows unbounded even on
    /// long sessions.
    private func prewarmNeighbors(of songId: String) {
        guard let idx = songs.firstIndex(where: { $0.id == songId }) else { return }
        let window = [idx + 1, idx + 2, idx - 1]
            .compactMap { songs.indices.contains($0) ? songs[$0] : nil }
        guard !window.isEmpty else { return }
        AudioPrewarmer.shared.prewarm(songs: window)
    }

    private var closeButton: some View {
        Button {
            performSlideDismiss(width: UIScreen.main.bounds.width)
        } label: {
            // Slight leading offset on the chevron itself nudges its
            // optical center to where the old `xmark` glyph sat, so the
            // 36pt circle still looks centered after the swap.
            Image(systemName: "chevron.left")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white.opacity(0.85))
                .padding(.leading, -1)
                .frame(width: 36, height: 36)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
        }
    }

    /// Shared dismiss path used by both the chevron tap and the
    /// swipe-right gesture: animate the page off the right edge first
    /// so the underlying grid is visible behind the slide, *then*
    /// trigger `.fullScreenCover` dismissal. Without this, tapping the
    /// chevron would crossfade the cover away (jarring) instead of
    /// matching the swipe's lateral motion.
    private func performSlideDismiss(width: CGFloat) {
        guard !isDismissing else { return }
        isDismissing = true
        let target = max(width, UIScreen.main.bounds.width)
        withAnimation(.easeOut(duration: 0.22)) {
            dragOffsetX = target
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
            dismiss()
        }
    }
}
