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
    let feedItems: [DiscoveryFeedItem]
    let appState: AppState
    let onSearchTap: () -> Void
    let onShazamSongResolved: (Song) -> Void
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
    @StateObject private var shazam = ShazamMatchService()
    @State private var isResolvingShazamMatch = false
    @State private var shazamHint: String?
    @State private var keyboardHeight: CGFloat = 0
    @State private var listenerListItem: SentSongHistoryItem?
    @Environment(\.scenePhase) private var scenePhase

    private static let heroId = "__discovery_hero__"
    private let restingBottom: CGFloat = 14
    private let scrollHaptic = UIImpactFeedbackGenerator(style: .soft)

    // MARK: - Derived

    private var isOnHero: Bool {
        (visiblePageId ?? Self.heroId) == Self.heroId
    }

    private var activeShare: SongShare? {
        guard let id = visiblePageId, id != Self.heroId else { return nil }
        guard let item = feedItems.first(where: { $0.id == id }) else { return nil }
        if case .received(let share) = item {
            return share
        }
        return nil
    }

    /// The active sent-history entry when the visible page is a song the
    /// current user sent. The reply lane swaps to a listens pill in this
    /// case instead of leaving the slot empty.
    private var activeSentItem: SentSongHistoryItem? {
        guard let id = visiblePageId, id != Self.heroId else { return nil }
        guard let item = feedItems.first(where: { $0.id == id }) else { return nil }
        if case .sent(let sentItem) = item {
            return sentItem
        }
        return nil
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
        guard let target = replyRecipient else { return "Send a message..." }
        return viewerIsSender
            ? "Message \(target.firstName)..."
            : "Send a message to \(target.firstName)..."
    }

    // MARK: - Body

    var body: some View {
        // TikTok-style feed model adapted for a tab-contained view: one
        // stable in-tab viewport, pages exactly equal to that viewport,
        // and chrome floating above the pager. Keyboard/reply UI never
        // participates in page measurement, so song cards cannot resize
        // or drift when the composer focuses.
        //
        // The root is `ZStack(alignment: .top)` so the pager pins to the
        // top of the tab content area. The bottom `discoveryReplyLaneHeight`
        // is permanently reserved for the reply composer — that lane is
        // empty space on the hero (per spec), and the reply bar docks
        // inside it on song-card pages.
        GeometryReader { pageGeo in
            let replyLaneHeight = FeedLayout.discoveryReplyLaneHeight
            let pagerHeight = max(1, pageGeo.size.height - replyLaneHeight)
            let pagerSize = CGSize(width: pageGeo.size.width, height: pagerHeight)
            let safeInsets = pageGeo.safeAreaInsets

            ZStack(alignment: .top) {
                Color.black

                VStack(spacing: 0) {
                    ScrollViewReader { proxy in
                        ScrollView(.vertical) {
                            LazyVStack(spacing: 0) {
                                hero(pageSize: pagerSize, scrollProxy: proxy)
                                    .frame(width: pagerSize.width, height: pagerSize.height)
                                    .id(Self.heroId)

                                ForEach(feedItems) { item in
                                    switch item {
                                    case .received(let share):
                                        SongCardView(
                                            share: share,
                                            isLiked: appState.isLiked(shareId: share.id),
                                            appState: appState,
                                            onToggleLike: { appState.toggleLike(shareId: share.id) }
                                        )
                                        .frame(width: pagerSize.width, height: pagerSize.height)
                                        .clipped()
                                        .id(item.id)

                                    case .sent(let sentItem):
                                        if let share = sentItem.latestShare {
                                            SongCardView(
                                                share: share,
                                                sentHistory: sentItem,
                                                isLiked: appState.isLiked(shareId: share.id),
                                                appState: appState,
                                                onToggleLike: { appState.toggleLike(shareId: share.id) }
                                            )
                                            .frame(width: pagerSize.width, height: pagerSize.height)
                                            .clipped()
                                            .id(item.id)
                                        }
                                    }
                                }
                            }
                            .scrollTargetLayout()
                        }
                        .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
                        .scrollPosition(id: $visiblePageId)
                        .scrollIndicators(.hidden)
                        .frame(width: pagerSize.width, height: pagerSize.height, alignment: .top)
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
                        .onChange(of: feedItems.map(\.id)) { _, _ in
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

                    // Reply lane is always reserved at the bottom of the
                    // tab content. When the reply bar is hidden (hero
                    // page or no active share), this is just empty space
                    // — no other element reflows into it.
                    Color.clear.frame(height: replyLaneHeight)
                }

                addFriendsOverlay()

                if isReplyFocused {
                    Color.black.opacity(0.38)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { isReplyFocused = false }
                        .transition(.opacity)
                }

                if !isOnHero {
                    // Single chrome slot: received pages get the message
                    // box, sent pages get the listens activity pill, hero
                    // is excluded above. Both branches share the same
                    // `replyBarBottomPadding`, so the pill docks at the
                    // exact same y regardless of branch.
                    Group {
                        if activeShare != nil {
                            replyBar
                        } else if let sent = activeSentItem {
                            listensPill(for: sent)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, replyBarBottomPadding(safeBottom: safeInsets.bottom))
                    // Plain opacity (no translation) so the pill can't
                    // visually "travel" during a scroll-to-hero — it
                    // just fades out in place.
                    .transition(.opacity)
                    .zIndex(2)
                }

                if shouldShowShazamOverlay {
                    ShazamListeningOverlay(
                        isResolving: isResolvingShazamMatch,
                        onCancel: cancelShazam
                    )
                    .transition(.opacity)
                    .zIndex(10)
                }
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .sheet(item: $listenerListItem) { item in
            ShareListenerListSheet(listeners: item.listeners)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .animation(.easeOut(duration: 0.22), value: isReplyFocused)
        .animation(.easeOut(duration: 0.22), value: keyboardHeight)
        .onReceive(KeyboardObserver.shared.publisher) { height in
            keyboardHeight = height
        }
        .task {
            await gridVM.loadIfNeeded()
        }
        .onAppear {
            onHeroVisibilityChange?(isOnHero)
        }
        .onChange(of: shazam.state) { _, newValue in
            handleShazamStateChange(newValue)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active {
                shazam.stop()
                isResolvingShazamMatch = false
            }
        }
        .onDisappear {
            shazam.stop()
            isResolvingShazamMatch = false
        }
        .animation(.easeInOut(duration: 0.2), value: shouldShowShazamOverlay)
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
        guard feedItems.contains(where: { $0.id == pendingId }) else { return }
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
        let artFrame = FeedLayout.discoveryArtFrame(forPageSize: pageSize)
        let ctaTop = artFrame.bottom + 12

        return ZStack(alignment: .top) {
            AlbumArtGridBackgroundView(
                items: gridVM.dedupedDisplayItems,
                side: artFrame.side
            )
            .frame(width: artFrame.side, height: artFrame.side)
            .position(x: pageSize.width / 2, y: artFrame.centerY)

            VStack(spacing: 10) {
                DiscoverySearchCTA(
                    action: onSearchTap,
                    shazamAction: startShazam,
                    isShazamActive: shouldShowShazamOverlay,
                    shazamHint: shazamHint
                )

                if !feedItems.isEmpty {
                    historyRow(scrollProxy: scrollProxy)
                        // Fade out within the first ~25% of a hero → card
                        // swipe so the row never crosses the friends pill.
                        .scrollTransition(axis: .vertical) { content, phase in
                            content.opacity(max(0, 1 - abs(phase.value) * 4))
                        }
                }
            }
            .padding(.top, ctaTop)
            .frame(width: pageSize.width, alignment: .top)
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
            guard let firstId = feedItems.first?.id else { return }
            scrollHaptic.prepare()
            scrollHaptic.impactOccurred(intensity: 0.7)
            withAnimation(.easeInOut(duration: 0.45)) {
                scrollProxy.scrollTo(firstId, anchor: .top)
            }
        } label: {
            HStack(spacing: 10) {
                DiscoveryHistoryHint()

                HistoryAlbumPreview(
                    shares: Array(feedItems.compactMap(\.albumPreviewShare).prefix(6)),
                    side: 34
                )
            }
        }
        .buttonStyle(.plain)
    }

    /// Top chrome floats above the pager instead of using `safeAreaInset`,
    /// so it never changes the measured page height or snap interval.
    private func addFriendsOverlay() -> some View {
        VStack(spacing: 0) {
            HStack {
                Spacer(minLength: 0)
                addFriendsPill
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .background(Color.black)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .zIndex(3)
    }

    /// The reply bar is chrome over a stable pager. The bottom
    /// `discoveryReplyLaneHeight` of the tab content is permanently
    /// reserved for it; this padding just docks the bar at the bottom
    /// of that lane (the GeometryReader already excludes the tab bar's
    /// safe area, so we don't add `safeBottom` here — that would
    /// double-count the tab bar height and float the pill far above
    /// the nav). Keyboard lifts the bar without resizing the page.
    ///
    /// When the keyboard is up, the GR ends `safeBottom` above the screen
    /// bottom (tab bar + home indicator), but `keyboardHeight` is measured
    /// from the screen bottom. Subtract `safeBottom` so the bar lands
    /// exactly `restingBottom` above the keyboard top.
    private func replyBarBottomPadding(safeBottom: CGFloat) -> CGFloat {
        if keyboardHeight > 0 {
            return max(restingBottom, keyboardHeight - safeBottom + restingBottom)
        }
        return restingBottom
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
                    AppTextField(
                        "",
                        text: $replyText,
                        prompt: Text(replyPlaceholder).foregroundColor(.white.opacity(0.9)),
                        axis: .vertical,
                        submitLabel: .send
                    )
                    .lineLimit(1...5)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.white)
                    .tint(.white)
                    .focused($isReplyFocused)
                    .onChange(of: replyText) { _, newValue in
                        guard newValue.contains("\n") else { return }
                        let stripped = newValue.replacingOccurrences(of: "\n", with: "")
                        replyText = stripped
                        if stripped.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            isReplyFocused = false
                        } else {
                            sendReply()
                        }
                    }
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
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(Color(white: 0.16).opacity(0.94))
                .clipShape(.rect(cornerRadius: 28, style: .continuous))
            }
        }
        .padding(.horizontal, 14)
        .animation(.easeInOut(duration: 0.2), value: showSentConfirmation)
    }

    // MARK: - Listens pill (sent-song variant of the reply lane chrome)

    /// Renders the listens activity in the same slot as the reply pill on
    /// pages where the viewer is the sender. Empty state shows
    /// "No listens yet"; one listener shows their name; multiple show an
    /// avatar stack + count and open the full list on tap.
    private func listensPill(for sent: SentSongHistoryItem) -> some View {
        let listeners = sent.listeners
        let summary: String = {
            if listeners.isEmpty { return "No listens yet" }
            if listeners.count == 1 {
                return "Listened by \(listeners[0].user.firstName)"
            }
            let names = listeners.prefix(2).map(\.user.firstName).joined(separator: ", ")
            let rest = listeners.count - 2
            return rest > 0 ? "Listened by \(names) + \(rest)" : "Listened by \(names)"
        }()

        return Button {
            if listeners.count > 1 { listenerListItem = sent }
        } label: {
            HStack(spacing: 10) {
                if listeners.count > 1 {
                    ListenerAvatarStack(listeners: listeners)
                }
                Text(summary)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(listeners.isEmpty ? .white.opacity(0.42) : .white.opacity(0.82))
                    .lineLimit(1)
                if listeners.count > 1 {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.08), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(listeners.count <= 1)
        .accessibilityLabel(summary)
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

    // MARK: - Shazam

    private var shouldShowShazamOverlay: Bool {
        if isResolvingShazamMatch { return true }
        switch shazam.state {
        case .preparing, .listening: return true
        default: return false
        }
    }

    private func startShazam() {
        switch shazam.state {
        case .preparing, .listening:
            return
        default:
            break
        }
        if isResolvingShazamMatch { return }

        AudioPlayerService.shared.pause()
        withAnimation(.easeInOut(duration: 0.2)) { shazamHint = nil }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        Task { await shazam.start() }
    }

    private func cancelShazam() {
        shazam.stop()
        isResolvingShazamMatch = false
    }

    private func handleShazamStateChange(_ newState: ShazamMatchService.State) {
        switch newState {
        case .matched(let match):
            isResolvingShazamMatch = true
            Task { await resolveShazamMatch(match) }
        case .noMatch:
            withAnimation(.easeInOut(duration: 0.2)) {
                shazamHint = "Didn't catch a song. Try again somewhere quieter."
            }
            shazam.reset()
        case .error(let message):
            withAnimation(.easeInOut(duration: 0.2)) {
                shazamHint = message
            }
            shazam.reset()
        case .idle, .preparing, .listening:
            break
        }
    }

    private func resolveShazamMatch(_ match: ShazamMatchService.Match) async {
        let resolved = await AppleMusicSearchService.shared.lookupSong(
            appleMusicID: match.appleMusicID,
            isrc: match.isrc,
            title: match.title,
            artist: match.artist
        )

        await MainActor.run {
            isResolvingShazamMatch = false
            shazam.reset()
            guard let song = resolved else {
                let label = match.title.isEmpty ? "the song" : "\"\(match.title)\""
                withAnimation(.easeInOut(duration: 0.2)) {
                    shazamHint = "We heard \(label) but couldn't find it in Apple Music."
                }
                return
            }

            withAnimation(.easeInOut(duration: 0.2)) { shazamHint = nil }
            onShazamSongResolved(song)
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
