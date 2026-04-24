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
        // Root `ZStack(alignment: .bottom)` floats the focus-dim and
        // reply pill above the paging stack. The pager lives inside a
        // `VStack` with a fixed `Color.clear` sibling reserving exactly
        // the reply-pill slot — that gives `GeometryReader` inside a
        // single, unambiguous page size to hand down to every page.
        //
        // This layout deliberately avoids mixing
        // `.containerRelativeFrame([.horizontal, .vertical])` with
        // `.safeAreaInset(edge: .bottom)` on the same ScrollView:
        // `containerRelativeFrame` measures against the ScrollView's
        // full frame while `.scrollTargetBehavior(.paging)` snaps by
        // the visible content region, and on some iPhones those two
        // numbers disagree enough that the next page's top leaks past
        // the snap seam. Measuring once with `GeometryReader` and
        // `.frame(height:)` each page explicitly guarantees page
        // height == snap distance on every device.
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                GeometryReader { pageGeo in
                    let pageSize = pageGeo.size
                    ScrollViewReader { proxy in
                        ScrollView(.vertical) {
                            LazyVStack(spacing: 0) {
                                hero(pageSize: pageSize, scrollProxy: proxy)
                                    .frame(width: pageSize.width, height: pageSize.height)
                                    .id(Self.heroId)

                                ForEach(shares) { share in
                                    SongCardView(
                                        share: share,
                                        isLiked: appState.isLiked(shareId: share.id),
                                        appState: appState,
                                        onToggleLike: { appState.toggleLike(shareId: share.id) }
                                    )
                                    .frame(width: pageSize.width, height: pageSize.height)
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
                            // Silence the tiny haptic when transitioning
                            // to or from the hero page — card-to-card
                            // swipes still get the subtle tick so the
                            // feed feels tactile.
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
                            isReplyFocused = false
                            replyText = ""
                            withAnimation(.easeInOut(duration: 0.35)) {
                                visiblePageId = Self.heroId
                            }
                        }
                        // Widget deep-link target: when the user taps the
                        // home-screen widget, ContentView sets
                        // `pendingDiscoveryShareId` and switches to this
                        // tab. We scroll directly to that share and clear
                        // the pending id. Guarded so we only scroll once
                        // the matching share has actually landed in the
                        // hydrated list (important on cold launch, where
                        // the deep link fires before receivedShares
                        // resolves).
                        .onChange(of: appState.pendingDiscoveryShareId) { _, newValue in
                            attemptPendingDiscoveryScroll(proxy: proxy, pendingId: newValue)
                        }
                        .onChange(of: shares.map(\.id)) { _, _ in
                            attemptPendingDiscoveryScroll(
                                proxy: proxy,
                                pendingId: appState.pendingDiscoveryShareId
                            )
                        }
                        .onAppear {
                            attemptPendingDiscoveryScroll(
                                proxy: proxy,
                                pendingId: appState.pendingDiscoveryShareId
                            )
                        }
                    }
                }

                // Fixed slot the reply pill renders into. Kept as a
                // VStack sibling (rather than a ScrollView
                // safeAreaInset) so the `pageGeo` above measures the
                // exact scrollable area and every page matches the
                // paging snap distance.
                Color.clear
                    .frame(height: FeedLayout.replyBarReservedHeight)
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

    // MARK: - Widget deep-link routing

    /// Scrolls the feed to `pendingId` when it matches a loaded share
    /// and clears `AppState.pendingDiscoveryShareId` so subsequent user
    /// interaction (tab-tap to hero, pull-to-refresh, etc.) isn't
    /// second-guessed by a stale target. If the id hasn't landed in
    /// `shares` yet (typical on cold launch), this is a no-op — the
    /// `.onChange(of: shares.map(\.id))` observer will retry once the
    /// Firestore listener hydrates.
    private func attemptPendingDiscoveryScroll(proxy: ScrollViewProxy, pendingId: String?) {
        guard let pendingId, !pendingId.isEmpty else { return }
        guard shares.contains(where: { $0.id == pendingId }) else { return }
        isReplyFocused = false
        replyText = ""
        withAnimation(.easeInOut(duration: 0.4)) {
            visiblePageId = pendingId
            proxy.scrollTo(pendingId, anchor: .top)
        }
        appState.pendingDiscoveryShareId = nil
    }

    // MARK: - Hero page

    /// Hero layout. Consumes the page size measured once by the
    /// pager's outer `GeometryReader` so hero grid and the first
    /// `SongCardView`'s artwork are identical on every iPhone — SE
    /// through Pro Max — when the user swipes between them.
    ///
    /// Vertical layout (top → bottom):
    ///   * Flexible top spacer.
    ///   * Album art grid (square, `FeedLayout.artSize`).
    ///   * Fixed gap.
    ///   * Search CTA (text + magnifier).
    ///   * Flexible spacer.
    ///   * History row (tap-to-scroll + rotating album preview) —
    ///     hidden entirely on accounts with no received shares.
    private func hero(pageSize: CGSize, scrollProxy: ScrollViewProxy) -> some View {
        // Non-grid content: search CTA (~80pt) + history row (~44pt)
        // + inter-group spacing. Passed to `FeedLayout.artSize` so
        // the grid shrinks gracefully on short viewports rather than
        // clipping the CTA or row.
        let nonGridHeight: CGFloat = 200
        let gridSide = FeedLayout.artSize(forPageSize: pageSize, nonArtHeight: nonGridHeight)
        let gridToCTAGap = max(18, pageSize.height * 0.028)
        let ctaToHistoryMin = max(18, pageSize.height * 0.028)
        let historyBottom = max(20, pageSize.height * 0.03)

        return VStack(spacing: 0) {
            Spacer(minLength: 0)

            AlbumArtGridBackgroundView(
                items: gridVM.dedupedDisplayItems,
                side: gridSide
            )
            .frame(width: gridSide, height: gridSide)

            Spacer().frame(minHeight: gridToCTAGap, maxHeight: gridToCTAGap * 2)

            DiscoverySearchCTA(action: onSearchTap)

            Spacer(minLength: ctaToHistoryMin)

            if !shares.isEmpty {
                historyRow(scrollProxy: scrollProxy)
                    .padding(.bottom, historyBottom)
                    // Fade out within the first ~25% of a hero → card
                    // swipe so the row never crosses the friends pill.
                    .scrollTransition(axis: .vertical) { content, phase in
                        content.opacity(max(0, 1 - abs(phase.value) * 4))
                    }
            } else {
                Spacer().frame(height: historyBottom)
            }
        }
        .frame(width: pageSize.width, height: pageSize.height)
        .background(Color.black)
    }

    /// Single tappable surface on the hero combining the existing
    /// history pill with a small rotating album-art preview. Tapping
    /// anywhere on the row fires the haptic and animates the scroll
    /// view to the first received share, so users don't have to
    /// discover the swipe gesture themselves. Only rendered when
    /// there's at least one share to show.
    private func historyRow(scrollProxy: ScrollViewProxy) -> some View {
        Button {
            guard let firstId = shares.first?.id else { return }
            scrollHaptic.prepare()
            scrollHaptic.impactOccurred(intensity: 0.7)
            withAnimation(.easeInOut(duration: 0.45)) {
                scrollProxy.scrollTo(firstId, anchor: .top)
            }
        } label: {
            HStack(spacing: 10) {
                DiscoveryHistoryHint()

                HistoryAlbumPreview(
                    shares: Array(shares.prefix(6)),
                    side: 34
                )
            }
        }
        .buttonStyle(.plain)
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
