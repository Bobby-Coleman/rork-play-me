import SwiftUI
import FirebaseFirestore
import UserNotifications
import UIKit

struct ChatView: View {
    private static let bottomAnchorID = "chat-bottom-anchor"

    let conversation: Conversation
    let appState: AppState

    @State private var messages: [ChatMessage] = []
    @State private var newMessageText: String = ""
    @State private var listener: ListenerRegistration?
    @State private var isSending: Bool = false
    @State private var sheetSong: Song?
    @State private var artistSong: Song?
    @State private var reportTarget: ReportTarget?
    @State private var showReportedToast: Bool = false
    @State private var pendingBlock: AppUser?
    @State private var backfilledSongMessageCount: Int?

    /// Pagination state for the lazy "Load earlier messages" sentinel at
    /// the top of the thread. The tail listener only carries the most
    /// recent 50 messages; everything older is fetched on-demand the
    /// first time the top sentinel scrolls into view, then merged into
    /// `messages`.
    @State private var hasMoreEarlier: Bool = true
    @State private var isLoadingEarlier: Bool = false
    @State private var initialTailLoaded: Bool = false
    /// Tracks the bottom-most message id we've already auto-scrolled to,
    /// so prepending older pages (which doesn't change `messages.last`)
    /// doesn't accidentally re-trigger the bottom-anchor scroll.
    @State private var lastBottomMessageId: String?

    /// When non-nil, the iMessage-style reaction tray overlay is
    /// presented for this message. Set by long-press on any bubble;
    /// cleared by tapping outside the tray, choosing an action, or
    /// reacting (which writes to Firestore and dismisses).
    @State private var pendingReactionTarget: ChatMessage?

    /// When non-nil, the composer is in "reply mode" — a quoted
    /// preview pill renders just above `inputBar` and the next
    /// `sendMessage` call embeds a `ReplyPreview` snapshot of this
    /// message so the receiver's bubble shows the quoted parent.
    @State private var pendingReplyTo: ChatMessage?

    /// Composer focus state. Tapping "Reply" in the reaction tray
    /// flips this to true so the keyboard pops up immediately, and
    /// `.scrollDismissesKeyboard(.interactively)` flips it back when
    /// the user drags up to dismiss.
    @FocusState private var isComposerFocused: Bool

    /// Briefly highlights a single message id when the user taps a
    /// quoted reply snippet to scroll to its parent. The highlight is
    /// the bubble's id; nil means "no highlight active". Driven by a
    /// short Task that resets the value after ~1.2s.
    @State private var highlightedMessageId: String?

    @Environment(\.scenePhase) private var scenePhase

    private var currentUID: String {
        FirebaseService.shared.firebaseUID ?? ""
    }

    private var friendName: String {
        conversation.friendName(currentUserId: currentUID)
    }

    private var friendUID: String {
        conversation.friendId(currentUserId: currentUID)
    }

    private var friendAsAppUser: AppUser {
        AppUser(id: friendUID, firstName: friendName, lastName: "", username: "", phone: "")
    }

    /// Live-updating mirror of the `Conversation` we were initialized
    /// with. The view's `let conversation` is a snapshot at navigation
    /// time, but `lastReadAt` flips when the friend opens the thread —
    /// so we re-resolve from the observable `appState.conversations`
    /// list on every render to pick up snapshot-listener updates.
    /// Falls back to the static snapshot if the live list hasn't
    /// caught up yet.
    private var liveConversation: Conversation {
        appState.conversations.first(where: { $0.id == conversation.id }) ?? conversation
    }

    private var displayedSongMessageCount: Int {
        max(liveConversation.songMessageCount, backfilledSongMessageCount ?? 0)
    }

    private var chatHeaderSubtitle: String {
        "\(songCountText) - \(streakText)"
    }

    private var songCountText: String {
        displayedSongMessageCount == 1 ? "1 song" : "\(displayedSongMessageCount) songs"
    }

    private var streakText: String {
        let count = liveConversation.songStreakCount
        guard count > 0 else { return "start a streak" }
        return count == 1 ? "1 day streak" : "\(count) day streak"
    }

    /// The id of the most recent message I've sent that the friend has
    /// already read, per `liveConversation.lastReadAt[friendUID]`.
    /// Drives the single iMessage-style "Read" indicator below that
    /// bubble. Returns nil when:
    ///  - the friend has never opened the thread, OR
    ///  - all my sent messages are newer than the friend's last read.
    /// Iterates from newest to oldest so we stop at the first match.
    private var mostRecentReadMessageId: String? {
        guard let friendReadAt = liveConversation.lastReadAt[friendUID] else { return nil }
        for message in messages.reversed() {
            if message.senderId == currentUID && message.timestamp <= friendReadAt {
                return message.id
            }
        }
        return nil
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            // Top sentinel: drives lazy-loading of earlier
                            // pages. We only render it once we've received
                            // the first tail snapshot (initialTailLoaded)
                            // so brand-new short threads don't briefly
                            // flash a "Loading earlier…" spinner.
                            if hasMoreEarlier && initialTailLoaded {
                                earlierPageLoader
                                    .onAppear { triggerLoadEarlier(scrollProxy: proxy) }
                            }
                            ForEach(messages) { message in
                                VStack(alignment: .trailing, spacing: 2) {
                                    messageBubble(message, scrollProxy: proxy)
                                    if message.id == mostRecentReadMessageId {
                                        // iMessage-style: a single "Read"
                                        // line under the most recent
                                        // message I've sent that the
                                        // friend has opened. Right-aligned
                                        // because my bubbles are right-
                                        // aligned. Animated transition so
                                        // the indicator slides as my
                                        // newest-read message advances
                                        // through the thread over time.
                                        Text("Read")
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundStyle(.white.opacity(0.45))
                                            .padding(.trailing, 4)
                                            .frame(maxWidth: .infinity, alignment: .trailing)
                                            .transition(.opacity.combined(with: .move(edge: .top)))
                                    }
                                }
                                .id(message.id)
                                .animation(.easeInOut(duration: 0.25), value: mostRecentReadMessageId)
                            }
                            Color.clear
                                .frame(height: 1)
                                .id(Self.bottomAnchorID)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .onAppear {
                        DispatchQueue.main.async {
                            scrollToBottom(proxy, animated: false)
                        }
                    }
                    .scrollIndicators(.hidden)
                    // iMessage-style: dragging the message list dismisses
                    // the keyboard interactively, with the keyboard
                    // following the user's finger so it can be brought
                    // back without a re-tap if they reverse direction.
                    .scrollDismissesKeyboard(.interactively)
                    .appKeyboardDismiss()
                    .onChange(of: messages.last?.id) { _, newId in
                        // Only auto-scroll when the most recent message
                        // changes (new send/receive), not when older pages
                        // are prepended — prepending preserves
                        // `messages.last`, so this onChange stays quiet
                        // and the user's reading position is preserved.
                        guard let id = newId, id != lastBottomMessageId else { return }
                        lastBottomMessageId = id
                        scrollToBottom(proxy, animated: true)
                    }
                    .onChange(of: initialTailLoaded) { _, loaded in
                        guard loaded else { return }
                        DispatchQueue.main.async {
                            scrollToBottom(proxy, animated: false)
                        }
                    }
                    // iMessage-style reply mode: when the user picks
                    // "Reply" from the reaction tray, the surrounding
                    // chat blurs out and an invisible hit layer
                    // overlays it so a single tap cancels reply mode.
                    // The selected parent message is rendered fresh
                    // below (between the ScrollView and the composer),
                    // so it stays sharp against the blurred backdrop.
                    .blur(radius: pendingReplyTo != nil ? 14 : 0)
                    .animation(.easeOut(duration: 0.2), value: pendingReplyTo?.id)
                    .overlay {
                        if pendingReplyTo != nil {
                            Color.black.opacity(0.001)
                                .contentShape(.rect)
                                .onTapGesture {
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        pendingReplyTo = nil
                                    }
                                }
                                .transition(.opacity)
                        }
                    }
                }

                if let replyTo = pendingReplyTo {
                    floatingReplyParent(replyTo)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                inputBar
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text(friendName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(chatHeaderSubtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }
                .accessibilityElement(children: .combine)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(role: .destructive) {
                        pendingBlock = friendAsAppUser
                    } label: {
                        Label("Block \(friendName)", systemImage: "hand.raised.fill")
                    }
                    Button {
                        reportTarget = .user(friendAsAppUser)
                    } label: {
                        Label("Report", systemImage: "flag.fill")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(.white)
                }
            }
        }
        .onAppear {
            startListening()
            Task {
                await FirebaseService.shared.markConversationRead(conversationId: conversation.id)
                let count = await FirebaseService.shared.backfillSongMessageCountIfNeeded(conversation: conversation)
                backfilledSongMessageCount = count
            }
            markThisConversationReadLocally()
            clearDeliveredNotificationsForThisConversation()
            ActiveScreenTracker.shared.activeConversationId = conversation.id
        }
        .onDisappear {
            listener?.remove()
            listener = nil
            if ActiveScreenTracker.shared.activeConversationId == conversation.id {
                ActiveScreenTracker.shared.activeConversationId = nil
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Foregrounding the app while the chat view is on screen
            // should refresh the read receipt — iMessage updates the
            // sender's "Read" indicator the instant the recipient
            // returns from the home screen, not just on initial open.
            // The 1Hz throttle inside markConversationRead prevents
            // this from being abusive.
            if newPhase == .active {
                Task {
                    await FirebaseService.shared.markConversationRead(conversationId: conversation.id)
                }
            }
        }
        .onChange(of: messages.last?.id) { _, _ in
            // Every time a new message arrives at the bottom, mark the
            // thread read. Filters by sender so my own outgoing sends
            // don't bump my own lastReadAt unnecessarily — that's
            // already handled by the background unreadCount=0 zeroing
            // and would otherwise produce a no-op write per sent line.
            guard let last = messages.last else { return }
            if last.senderId != currentUID {
                Task {
                    await FirebaseService.shared.markConversationRead(conversationId: conversation.id)
                }
            }
        }
        .sheet(item: $sheetSong) { song in
            SongActionSheet(song: song, appState: appState)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $artistSong) { song in
            if let aid = song.artistId {
                ArtistView(artistId: aid, initialArtistName: song.artist, appState: appState)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
        .sheet(item: $reportTarget) { target in
            ReportSheet(target: target, appState: appState) {
                withAnimation { showReportedToast = true }
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    withAnimation { showReportedToast = false }
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .overlay(alignment: .top) {
            if showReportedToast {
                Text("Report submitted. Thanks.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.9))
                    .clipShape(.capsule)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .alert("Block \(pendingBlock?.firstName ?? friendName)?", isPresented: blockAlertBinding) {
            Button("Cancel", role: .cancel) { pendingBlock = nil }
            Button("Block", role: .destructive) {
                if let user = pendingBlock {
                    Task { await appState.blockUser(user) }
                }
                pendingBlock = nil
            }
        } message: {
            Text("They won't be able to send you songs or messages, and you won't see their content.")
        }
        .overlay {
            // iMessage-style reaction tray. Sits as a sibling overlay
            // above the entire chat ZStack so it can dim the whole
            // screen with .ultraThinMaterial without blocking the
            // navigation bar layout. Re-renders the long-pressed
            // bubble's content via the same `bubbleVisuals(for:isMe:)`
            // helper used by the in-list rows so the lifted copy
            // matches pixel-for-pixel.
            if let target = pendingReactionTarget {
                ReactionMenuOverlay(
                    message: target,
                    isMe: target.senderId == currentUID,
                    currentUserUID: currentUID,
                    onReact: { emoji in
                        let convId = conversation.id
                        let msgId = target.id
                        // Refresh the in-overlay highlight by mutating
                        // pendingReactionTarget so the tray's "active"
                        // ring tracks the latest pick before we
                        // dismiss; the server write happens async.
                        Task {
                            await FirebaseService.shared.setReaction(
                                conversationId: convId,
                                messageId: msgId,
                                emoji: emoji
                            )
                        }
                        pendingReactionTarget = nil
                    },
                    onClearReaction: {
                        let convId = conversation.id
                        let msgId = target.id
                        Task {
                            await FirebaseService.shared.clearReaction(
                                conversationId: convId,
                                messageId: msgId
                            )
                        }
                        pendingReactionTarget = nil
                    },
                    onReply: {
                        pendingReplyTo = target
                        pendingReactionTarget = nil
                        // Defer focus to the next runloop tick so the
                        // keyboard pops up after the overlay's
                        // dismissal animation has handed back input.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            isComposerFocused = true
                        }
                    },
                    onCopy: {
                        pendingReactionTarget = nil
                    },
                    onDismiss: {
                        pendingReactionTarget = nil
                    },
                    bubbleContent: {
                        bubbleVisuals(for: target, isMe: target.senderId == currentUID)
                    }
                )
                .transition(.opacity)
            }
        }
    }

    private var blockAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingBlock != nil },
            set: { if !$0 { pendingBlock = nil } }
        )
    }

    private func messageBubble(_ message: ChatMessage, scrollProxy proxy: ScrollViewProxy) -> some View {
        let isMe = message.senderId == currentUID
        let isHighlighted = highlightedMessageId == message.id

        return HStack {
            if isMe { Spacer(minLength: 60) }

            VStack(alignment: isMe ? .trailing : .leading, spacing: 4) {
                bubbleVisuals(
                    for: message,
                    isMe: isMe,
                    onTapQuotedReply: { parentId in
                        scrollToParent(messageId: parentId, scrollProxy: proxy)
                    }
                )
                    .scaleEffect(isHighlighted ? 1.04 : 1)
                    .animation(.spring(response: 0.35, dampingFraction: 0.65), value: isHighlighted)
                    .overlay(alignment: isMe ? .bottomLeading : .bottomTrailing) {
                        // Reaction cluster floats slightly outside the
                        // bubble's bottom corner — leading for me-bubbles
                        // (right-aligned), trailing for them-bubbles
                        // (left-aligned), so the cluster always sits in
                        // the empty gutter rather than over the text.
                        if !message.reactions.isEmpty {
                            ReactionBadgeCluster(
                                reactions: message.reactions,
                                currentUserUID: currentUID
                            )
                            .offset(x: isMe ? -10 : 10, y: 10)
                            .zIndex(1)
                        }
                    }
                    .padding(.bottom, message.reactions.isEmpty ? 0 : 14)
                    .onLongPressGesture(minimumDuration: 0.35) {
                        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                        pendingReactionTarget = message
                    }

                Text(formattedTimestamp(message.timestamp))
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.2))
            }

            if !isMe { Spacer(minLength: 60) }
        }
    }

    /// iMessage-style "floating parent" rendered just above the
    /// composer when the user is in reply mode. Uses the same
    /// `bubbleVisuals` helper as the in-list bubble so the lifted
    /// preview matches pixel-for-pixel — no timestamp, no reaction
    /// cluster, no long-press hit target. Aligns to the original
    /// sender's side (right for me, left for them) so it visually
    /// reads as the same message that lives further up in the
    /// (blurred) thread.
    @ViewBuilder
    private func floatingReplyParent(_ message: ChatMessage) -> some View {
        let isMe = message.senderId == currentUID
        HStack {
            if isMe { Spacer(minLength: 60) }
            bubbleVisuals(for: message, isMe: isMe)
            if !isMe { Spacer(minLength: 60) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    /// Renders the bubble's visual content (quoted reply snippet, song
    /// card, text bubble) without timestamp or reactions cluster.
    /// Factored out so the reaction tray overlay can re-render the same
    /// thing pixel-identically when "lifting" a bubble onto the dimmed
    /// backdrop.
    ///
    /// - Parameter onTapQuotedReply: Optional callback fired when the
    ///   user taps the quoted-reply chip. The in-list version wires
    ///   this to `scrollToParent`; the overlay leaves it nil because
    ///   tapping during a reaction gesture would be ambiguous.
    @ViewBuilder
    private func bubbleVisuals(
        for message: ChatMessage,
        isMe: Bool,
        onTapQuotedReply: ((String) -> Void)? = nil
    ) -> some View {
        VStack(alignment: isMe ? .trailing : .leading, spacing: 4) {
            if let preview = message.replyToPreview {
                quotedReplySnippet(preview, isMe: isMe)
                    .contentShape(.rect)
                    .onTapGesture {
                        onTapQuotedReply?(preview.messageId)
                    }
            }

            if let song = message.song {
                inlineSongCard(song)
            }

            if !message.text.isEmpty {
                Text(message.text)
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(isMe ? Color(red: 0.76, green: 0.38, blue: 0.35) : Color.white.opacity(0.1))
                    .clipShape(.rect(cornerRadius: 18))
                    .frame(maxWidth: 280, alignment: isMe ? .trailing : .leading)
            }
        }
    }

    /// Compact "quoted parent" chip rendered inside a reply bubble.
    /// Matches the WhatsApp/Telegram pattern: vertical accent stripe,
    /// sender name, and one line of the parent's text or song title.
    /// Tapping is wired by the parent (`bubbleVisuals`) — this view
    /// only handles its own visual rendering.
    @ViewBuilder
    private func quotedReplySnippet(_ preview: ReplyPreview, isMe: Bool) -> some View {
        let displaySnippet: String = {
            if let songTitle = preview.songTitle, !songTitle.isEmpty {
                return "🎵 \(songTitle)"
            }
            return preview.textSnippet.isEmpty ? "Message" : preview.textSnippet
        }()

        let parentSenderName: String = preview.senderId == currentUID ? "You" : friendName

        HStack(spacing: 8) {
            Capsule()
                .fill(Color.white.opacity(0.45))
                .frame(width: 2)
            VStack(alignment: .leading, spacing: 1) {
                Text(parentSenderName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.65))
                Text(displaySnippet)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: 240, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }

    /// Smooth-scroll to the parent of a quoted reply and briefly
    /// highlight that bubble so it's easy to spot in a busy thread.
    /// If the parent isn't currently in `messages` (because it's older
    /// than any earlier page that's been loaded yet), the scrollTo is
    /// a no-op — the user still has the inline `replyToPreview`
    /// snapshot for context, so the UX degrades gracefully.
    private func scrollToParent(messageId: String, scrollProxy proxy: ScrollViewProxy) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.easeInOut(duration: 0.4)) {
            proxy.scrollTo(messageId, anchor: .center)
        }
        highlightedMessageId = messageId
        Task {
            try? await Task.sleep(for: .milliseconds(1200))
            await MainActor.run {
                if highlightedMessageId == messageId {
                    highlightedMessageId = nil
                }
            }
        }
    }

    private func inlineSongCard(_ song: Song) -> some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: URL(string: song.albumArtURL)) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Color(.systemGray5)
                }
            }
            .frame(width: 190, height: 190)
            .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.72)],
                startPoint: .center,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(song.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                if song.artistId != nil {
                    Button {
                        artistSong = song
                    } label: {
                        Text(song.artist)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.72))
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(song.artist)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)
                }
            }
            .padding(12)
        }
        .frame(width: 190, height: 190)
        .clipShape(.rect(cornerRadius: 14))
        .contentShape(.rect)
        .onTapGesture {
            sheetSong = song
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            AppTextField(pendingReplyTo != nil ? "Reply" : "Message...", text: $newMessageText, submitLabel: .send) {
                if !newMessageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    sendMessage()
                } else {
                    isComposerFocused = false
                }
            }
                .font(.system(size: 15))
                .foregroundStyle(.white)
                .tint(.white)
                .focused($isComposerFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.08))
                .clipShape(.capsule)

            if !newMessageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(Color(red: 0.76, green: 0.38, blue: 0.35))
                }
                .disabled(isSending)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.black)
    }

    private func formattedTimestamp(_ date: Date) -> String {
        let cal = Calendar.current
        let now = Date()

        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "h:mm a"

        if cal.isDateInToday(date) {
            return timeFmt.string(from: date)
        }
        if cal.isDateInYesterday(date) {
            return "Yesterday \(timeFmt.string(from: date))"
        }
        let daysAgo = cal.dateComponents([.day], from: cal.startOfDay(for: date), to: cal.startOfDay(for: now)).day ?? 7
        if daysAgo < 7 {
            let dayFmt = DateFormatter()
            dayFmt.dateFormat = "EEE"
            return "\(dayFmt.string(from: date)) \(timeFmt.string(from: date))"
        }
        if cal.component(.year, from: date) == cal.component(.year, from: now) {
            let dateFmt = DateFormatter()
            dateFmt.dateFormat = "MMM d"
            return "\(dateFmt.string(from: date)), \(timeFmt.string(from: date))"
        }
        let fullFmt = DateFormatter()
        fullFmt.dateFormat = "MMM d, yyyy"
        return fullFmt.string(from: date)
    }

    private func sendMessage() {
        let text = newMessageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isSending = true
        // Capture and clear the reply target synchronously before the
        // network call so a fast follow-up message doesn't accidentally
        // re-attach to the same parent.
        let replyTo = pendingReplyTo
        withAnimation(.easeOut(duration: 0.2)) {
            pendingReplyTo = nil
        }
        newMessageText = ""

        Task {
            await appState.sendMessage(
                conversationId: conversation.id,
                text: text,
                replyTo: replyTo
            )
            isSending = false
        }
    }

    /// Optimistically zero this conversation's `unreadCount` in the in-memory
    /// `AppState.conversations` array so the inbox row badge drops the moment
    /// the thread opens, without waiting for the Firestore snapshot listener
    /// to round-trip the `unreadCount_<uid>` = 0 write. The listener will
    /// later reconcile the authoritative value and this optimistic update
    /// will simply match.
    private func markThisConversationReadLocally() {
        guard let idx = appState.conversations.firstIndex(where: { $0.id == conversation.id }) else { return }
        guard appState.conversations[idx].unreadCount != 0 else { return }
        appState.conversations[idx] = appState.conversations[idx].withUnreadCount(0)
    }

    /// Remove any delivered push notifications that target this specific
    /// conversation. Notifications are tagged with `apns.thread-id =
    /// "conv-<id>"` by the Cloud Function, which both groups them in the
    /// iOS UI and lets us clear them surgically on open without touching
    /// other threads' notifications.
    private func clearDeliveredNotificationsForThisConversation() {
        let threadId = "conv-\(conversation.id)"
        UNUserNotificationCenter.current().getDeliveredNotifications { delivered in
            let ids = delivered
                .filter { $0.request.content.threadIdentifier == threadId }
                .map { $0.request.identifier }
            guard !ids.isEmpty else { return }
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        guard !messages.isEmpty else { return }
        lastBottomMessageId = messages.last?.id
        if animated {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
        }
    }

    private func startListening() {
        listener = FirebaseService.shared.listenForMessageTail(
            conversationId: conversation.id,
            limit: 50
        ) { tailMessages in
            Task { @MainActor in
                if !self.initialTailLoaded {
                    self.initialTailLoaded = true
                    // Threads that fit entirely in the tail window
                    // never need an earlier-page loader — disable it
                    // upfront to suppress the sentinel.
                    if tailMessages.count < 50 {
                        self.hasMoreEarlier = false
                    }
                }
                self.mergeIntoMessages(tailMessages)
            }
        }
    }

    /// Merge `incoming` into `messages` by id, preserving any earlier
    /// pages that have already been loaded. The tail listener delivers
    /// only the most recent ~50 messages, so on a thread where the user
    /// has scrolled back to load older pages we must NOT replace the
    /// full array — we instead overlay the latest tail snapshot on top
    /// of whatever else we've accumulated.
    ///
    /// Sorted by timestamp ascending so the rendered ForEach stays in
    /// chronological order regardless of arrival order.
    private func mergeIntoMessages(_ incoming: [ChatMessage]) {
        var byId: [String: ChatMessage] = [:]
        for m in messages { byId[m.id] = m }
        for m in incoming { byId[m.id] = m }
        messages = byId.values.sorted { $0.timestamp < $1.timestamp }
    }

    /// Top-of-list "Loading earlier…" sentinel. Renders a small spinner
    /// while a fetch is in flight, otherwise an empty 28pt strip whose
    /// `onAppear` is what actually triggers the next page.
    private var earlierPageLoader: some View {
        HStack {
            Spacer()
            if isLoadingEarlier {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white.opacity(0.4))
            }
            Spacer()
        }
        .frame(height: 28)
    }

    /// Fetch the next 50 messages strictly older than `messages.first`,
    /// merge them into the visible array, and pin the previously-oldest
    /// message to the top so the user's reading position doesn't jump.
    /// Guarded against re-entrancy (`isLoadingEarlier`) and end-of-
    /// history (`hasMoreEarlier`).
    private func triggerLoadEarlier(scrollProxy proxy: ScrollViewProxy) {
        guard hasMoreEarlier, !isLoadingEarlier else { return }
        guard let oldest = messages.first else { return }
        isLoadingEarlier = true
        let pivotId = oldest.id
        Task {
            let earlier = await FirebaseService.shared.loadEarlierMessages(
                conversationId: conversation.id,
                before: oldest.timestamp,
                limit: 50
            )
            await MainActor.run {
                if earlier.isEmpty {
                    hasMoreEarlier = false
                } else {
                    mergeIntoMessages(earlier)
                    if earlier.count < 50 {
                        hasMoreEarlier = false
                    }
                    // Anchor the previously-oldest message at the top
                    // so the new content appears above without yanking
                    // the user's view downward.
                    proxy.scrollTo(pivotId, anchor: .top)
                }
                isLoadingEarlier = false
            }
        }
    }
}
