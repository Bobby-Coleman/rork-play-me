import SwiftUI
import UIKit

/// Primary landing screen. Hosts three things in one paging scroll container:
///
/// 1. A hero page with a square-contained ambient album-art grid + centered
///    "search a song" CTA.
/// 2. One `SongCardView` per `SongShare`, accessible by scrolling up from the
///    hero ("history"). Retains the full reply/like/chat UX from the previous
///    `HomeFeedView`.
/// 3. The add-friends pill and reply pill, which render only when a card page
///    is visible — the hero stays visually clean.
struct DiscoveryView: View {
    let shares: [SongShare]
    let appState: AppState
    let onSearchTap: () -> Void
    let onAddFriends: () -> Void

    /// Reports whether the hero page is currently visible so the parent can
    /// adjust chrome (mini-player, tab-to-search routing) accordingly.
    var onHeroVisibilityChange: ((Bool) -> Void)? = nil

    @State private var visiblePageId: String? = DiscoveryView.heroId
    @State private var replyText: String = ""
    @State private var isSendingReply: Bool = false
    @State private var showSentConfirmation: Bool = false
    @FocusState private var isReplyFocused: Bool

    @State private var gridVM = SongGridViewModel()

    private static let heroId = "__discovery_hero__"
    private let restingBottom: CGFloat = 8
    private let scrollHaptic = UIImpactFeedbackGenerator(style: .soft)

    // MARK: - Derived

    private var isOnHero: Bool {
        (visiblePageId ?? Self.heroId) == Self.heroId
    }

    private var activeShare: SongShare? {
        guard let id = visiblePageId, id != Self.heroId else { return nil }
        return shares.first { $0.id == id }
    }

    private var viewerIsSender: Bool {
        guard let me = appState.currentUser?.id, let share = activeShare else { return false }
        return share.sender.id == me
    }

    private var replyRecipient: AppUser? {
        guard let share = activeShare else { return nil }
        return viewerIsSender ? share.recipient : share.sender
    }

    private var replyPlaceholder: String {
        guard let target = replyRecipient else { return "Reply..." }
        return viewerIsSender ? "Message \(target.firstName)..." : "Reply to \(target.firstName)..."
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        hero
                            .containerRelativeFrame([.horizontal, .vertical])
                            .id(Self.heroId)

                        ForEach(shares) { share in
                            SongCardView(
                                share: share,
                                isLiked: appState.isLiked(shareId: share.id),
                                appState: appState,
                                onToggleLike: { appState.toggleLike(shareId: share.id) }
                            )
                            .containerRelativeFrame([.horizontal, .vertical])
                            .clipped()
                            .id(share.id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $visiblePageId)
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.immediately)
                .ignoresSafeArea(.keyboard, edges: .bottom)
                .refreshable { await appState.refreshShares() }
                .onChange(of: visiblePageId) { oldValue, newValue in
                    guard let newValue, let oldValue, newValue != oldValue else { return }
                    // Silence the tiny haptic when transitioning to or from
                    // the hero page — the spec explicitly calls out the
                    // extra bounce/haptic as distracting when entering /
                    // leaving the landing experience. Card-to-card swipes
                    // still get the subtle tick so the feed feels tactile.
                    let toFromHero = newValue == Self.heroId || oldValue == Self.heroId
                    if !toFromHero {
                        scrollHaptic.prepare()
                        scrollHaptic.impactOccurred(intensity: 0.65)
                    }
                    if isReplyFocused { isReplyFocused = false }
                    if !replyText.isEmpty { replyText = "" }
                    onHeroVisibilityChange?(newValue == Self.heroId)
                }
                .onChange(of: appState.discoveryScrollToTopCounter) { _, _ in
                    // Clear reply focus/text synchronously, then flip
                    // `visiblePageId` inside `withAnimation`. The
                    // `.scrollPosition(id:)` binding turns that into the
                    // scroll animation, and because `isOnHero` goes true
                    // *at the same instant*, the reply bar's gate drops
                    // on frame 1 of the animation instead of lingering
                    // until the scroll settles — which is what made the
                    // pill appear to ride up with the scroll-to-hero.
                    isReplyFocused = false
                    replyText = ""
                    withAnimation(.easeInOut(duration: 0.35)) {
                        visiblePageId = Self.heroId
                    }
                }
            }

            if isReplyFocused {
                Color.black.opacity(0.38)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { isReplyFocused = false }
                    .transition(.opacity)
            }

            if !isOnHero && activeShare != nil {
                replyBar
                    .padding(.bottom, restingBottom)
                    // Plain opacity (no translation) so the pill can't
                    // visually "travel" during a scroll-to-hero — it
                    // just fades out in place.
                    .transition(.opacity)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            // Friends pill is visible across the whole Discovery tab —
            // both the hero and the history feed. Keeping it always
            // mounted removes the layout toggle on page change, which
            // was the last contributor to the scroll "bounce" feel.
            //
            // The strip has a solid black backdrop so scrolled content
            // (notably the hero's history chevron) can't ghost through
            // the translucent pill material during a hero → card swipe.
            HStack {
                Spacer(minLength: 0)
                addFriendsPill
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .background(Color.black)
        }
        .animation(.easeOut(duration: 0.22), value: isReplyFocused)
        .task {
            await gridVM.loadIfNeeded()
        }
        .onAppear {
            onHeroVisibilityChange?(isOnHero)
        }
    }

    // MARK: - Hero page

    /// Hero layout. `gridSide` is derived from `UIScreen.main.bounds` rather
    /// than a `GeometryReader` so the computation doesn't re-run while the
    /// paging scroll is mid-transition (a GeometryReader inside a
    /// `containerRelativeFrame` page re-publishes its size during animation,
    /// which can kick off layout work during the snap and cause the bounce
    /// feel the spec wants gone).
    ///
    /// Vertical layout (top → bottom):
    ///   * Flexible top spacer — pushes everything down from the navbar.
    ///   * Album art grid (square).
    ///   * Fixed gap.
    ///   * Search CTA (text + magnifier).
    ///   * Flexible spacer.
    ///   * History chevron pinned near the bottom.
    ///
    /// The two flexible spacers sandwich the core content (grid + CTA) so it
    /// ends up visually centered — addressing the "positioned too high"
    /// feedback — while the history hint stays anchored.
    private var hero: some View {
        // All spacing is a fraction of the real screen height so the hero
        // lands in the same visual position on every device (SE through
        // Pro Max). `UIScreen.main.bounds` is deliberate: it's stable and
        // doesn't re-publish mid-paging the way a `GeometryReader` would.
        //
        // The grid side mirrors `SongCardView.artSize` — which is
        // `min(screenW - 48, max(220, screenH - 180))` — so when the user
        // swipes from hero to the first song card the artwork keeps
        // exactly the same on-screen size. On every modern phone the
        // width formula wins, so the cap only matters on SE-class
        // devices; `screenH * 0.42` leaves just enough headroom below
        // the grid for the CTA + history chevron on those shorter
        // viewports.
        let screenW = UIScreen.main.bounds.width
        let screenH = UIScreen.main.bounds.height
        let gridSide = min(screenW - 48, screenH * 0.42)
        // Lowered topSpace offsets the extra height the larger grid
        // eats; the grid's BOTTOM edge ends up within a few points of
        // where it sat with the previous (smaller) layout, preserving
        // the "positioning is good" feedback while the bigger square is
        // still visually anchored in the upper half.
        let topSpace = max(60, screenH * 0.09)
        let gridToCTAGap = max(18, screenH * 0.028)
        let ctaToHistoryMin = max(18, screenH * 0.028)
        // Raised from `max(12, screenH * 0.022)` so the history chevron
        // clears the translucent tab bar on every device instead of
        // sitting right under its edge.
        let historyBottom = max(28, screenH * 0.04)

        return VStack(spacing: 0) {
            Spacer().frame(minHeight: topSpace)

            AlbumArtGridBackgroundView(
                items: gridVM.dedupedDisplayItems,
                side: gridSide
            )
            .frame(width: gridSide, height: gridSide)

            Spacer().frame(minHeight: gridToCTAGap, maxHeight: gridToCTAGap * 2)

            DiscoverySearchCTA(action: onSearchTap)

            Spacer(minLength: ctaToHistoryMin)

            DiscoveryHistoryHint()
                .padding(.bottom, historyBottom)
                // Fade out within the first ~25% of a hero → card swipe
                // so the chevron never crosses the friends pill. The
                // scroll transition phase value is 0 when the hint is
                // centered and approaches ±1 as it exits the viewport;
                // the ×4 multiplier collapses opacity to zero well
                // before the hint can reach the top bar.
                .scrollTransition(axis: .vertical) { content, phase in
                    content.opacity(max(0, 1 - abs(phase.value) * 4))
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    // MARK: - Reply bar (mirrors HomeFeedView behavior)

    private var replyBar: some View {
        ZStack {
            if showSentConfirmation {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(.green)
                    Text("Sent!")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .transition(.opacity)
            } else {
                HStack(spacing: 10) {
                    TextField(
                        "",
                        text: $replyText,
                        prompt: Text(replyPlaceholder).foregroundColor(.white.opacity(0.9)),
                        axis: .vertical
                    )
                    .lineLimit(1...5)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white)
                    .tint(.white)
                    .focused($isReplyFocused)
                    .disabled(replyRecipient == nil)

                    if isReplyFocused && replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button { isReplyFocused = false } label: {
                            Text("Done")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.65))
                        }
                    }

                    if !replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button {
                            sendReply()
                        } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 30))
                                .foregroundStyle(.white)
                        }
                        .disabled(isSendingReply)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(Color(white: 0.16).opacity(0.94))
                .clipShape(.rect(cornerRadius: 26, style: .continuous))
            }
        }
        .padding(.horizontal, 14)
        .animation(.easeInOut(duration: 0.2), value: showSentConfirmation)
    }

    private func sendReply() {
        let text = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let share = activeShare, let other = replyRecipient else { return }
        if let me = appState.currentUser?.id, other.id == me {
            print("DiscoveryView: refusing to send reply to self (uid=\(me))")
            replyText = ""
            isReplyFocused = false
            return
        }
        isSendingReply = true
        let capturedText = text
        let capturedSong = share.song
        replyText = ""
        isReplyFocused = false

        Task {
            var success = false
            if let conv = await FirebaseService.shared.getOrCreateConversation(
                with: other.id,
                friendName: other.firstName
            ) {
                await appState.sendMessage(conversationId: conv.id, text: capturedText, song: capturedSong)
                success = true
            }
            isSendingReply = false
            if success {
                showSentConfirmation = true
                try? await Task.sleep(for: .seconds(1.5))
                showSentConfirmation = false
            }
        }
    }

    // MARK: - Add friends pill (reused from HomeFeedView)

    private var addFriendsPill: some View {
        Button(action: onAddFriends) {
            HStack(spacing: 6) {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 13, weight: .semibold))
                Text("Add Friends")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial.opacity(0.8))
            .background(Color.white.opacity(0.1))
            .clipShape(.capsule)
        }
        .overlay(alignment: .topTrailing) {
            if appState.incomingRequests.count > 0 {
                Text("\(appState.incomingRequests.count)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.red, in: Capsule())
                    .offset(x: 6, y: -6)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 8)
    }
}
