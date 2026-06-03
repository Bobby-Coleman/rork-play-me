import SwiftUI
import FirebaseFirestore
import UserNotifications
import UIKit

struct ChatView: View {
    let conversation: Conversation
    let appState: AppState

    @State private var messages: [ChatMessage] = []
    @State private var newMessageText: String = ""
    @State private var listener: ListenerRegistration?
    @State private var isSending: Bool = false
    @State private var sheetSong: ChatSongTarget?
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

    /// Imperative scroll request handed to `ChatMessagesCollectionView`.
    /// The bridge clears this back to nil after dispatching to the
    /// underlying UIKit controller.
    @State private var pendingScrollAction: ChatScrollAction?

    /// When non-nil, the iMessage-style reaction tray overlay is
    /// presented for this message. Set by long-press on any bubble;
    /// cleared by tapping outside the tray, choosing an action, or
    /// reacting (which writes to Firestore and dismisses).
    @State private var pendingReactionTarget: ChatMessage?

    /// Captured frame of the long-pressed bubble in window coordinates.
    /// Passed to `ReactionMenuOverlay` so the lifted bubble animates
    /// from-position (iMessage-style) rather than fading in centered.
    @State private var pendingReactionSourceFrame: CGRect?

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

    /// The `shares/{id}` doc id to mark listened when opening this song from
    /// chat. Only the recipient records a listen, and only sends made through
    /// the share pipeline carry a share doc (message id `share-{shareId}`).
    private func listenShareId(for message: ChatMessage) -> String? {
        guard message.senderId != currentUID, message.id.hasPrefix("share-") else { return nil }
        return String(message.id.dropFirst("share-".count))
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
        return "Streak \(count)"
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
                ChatMessagesCollectionView(
                    messages: messages,
                    currentUID: currentUID,
                    friendName: friendName,
                    mostRecentReadMessageId: mostRecentReadMessageId,
                    highlightedMessageId: highlightedMessageId,
                    showEarlierLoader: hasMoreEarlier && initialTailLoaded,
                    isLoadingEarlier: isLoadingEarlier,
                    onLongPressMessage: { message, frame in
                        pendingReactionSourceFrame = frame
                        pendingReactionTarget = message
                    },
                    onTapSong: { message in
                        guard let song = message.song else { return }
                        sheetSong = ChatSongTarget(song: song, listenShareId: listenShareId(for: message))
                    },
                    onTapArtist: { song in artistSong = song },
                    onTapQuotedReply: { parentMessageId in
                        scrollToParent(messageId: parentMessageId)
                    },
                    onReachedTop: { triggerLoadEarlier() },
                    pendingScrollAction: $pendingScrollAction
                )
                // iMessage-style reply mode: when the user picks
                // "Reply" from the reaction tray, the surrounding
                // chat blurs out and an invisible hit layer
                // overlays it so a single tap cancels reply mode.
                // The selected parent message is rendered fresh
                // below (between the list and the composer),
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
        .onChange(of: messages.last?.id) { _, newId in
            guard let id = newId, id != lastBottomMessageId else { return }
            lastBottomMessageId = id
            // The collection view already pins to bottom on append when
            // the user is at-bottom; this onChange is also responsible
            // for marking the thread read whenever a new incoming line
            // lands while the chat is on screen.
            if let last = messages.last, last.senderId != currentUID {
                Task {
                    await FirebaseService.shared.markConversationRead(conversationId: conversation.id)
                }
            }
        }
        .sheet(item: $sheetSong) { target in
            SongActionSheet(song: target.song, appState: appState, recordListenShareId: target.listenShareId)
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
            // bubble's content via `ChatBubbleVisuals` so the lifted
            // copy matches pixel-for-pixel, and animates from the
            // source bubble's window-coord frame so the lift reads as
            // the same message rising rather than a teleported copy.
            if let target = pendingReactionTarget {
                ReactionMenuOverlay(
                    message: target,
                    isMe: target.senderId == currentUID,
                    currentUserUID: currentUID,
                    onReact: { emoji in
                        let convId = conversation.id
                        let msgId = target.id
                        Task {
                            await FirebaseService.shared.setReaction(
                                conversationId: convId,
                                messageId: msgId,
                                emoji: emoji
                            )
                        }
                        dismissReactionOverlay()
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
                        dismissReactionOverlay()
                    },
                    onReply: {
                        pendingReplyTo = target
                        dismissReactionOverlay()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            isComposerFocused = true
                        }
                    },
                    onCopy: {
                        dismissReactionOverlay()
                    },
                    onDismiss: {
                        dismissReactionOverlay()
                    },
                    bubbleContent: {
                        ChatBubbleVisuals(
                            message: target,
                            isMe: target.senderId == currentUID,
                            currentUID: currentUID,
                            friendName: friendName
                        )
                    },
                    sourceFrame: pendingReactionSourceFrame
                )
                .transition(.opacity)
            }
        }
    }

    private func dismissReactionOverlay() {
        pendingReactionTarget = nil
        pendingReactionSourceFrame = nil
    }

    private var blockAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingBlock != nil },
            set: { if !$0 { pendingBlock = nil } }
        )
    }

    /// iMessage-style "floating parent" rendered just above the
    /// composer when the user is in reply mode. Uses `ChatBubbleVisuals`
    /// so the lifted preview matches pixel-for-pixel with the in-list
    /// row — no timestamp, no reaction cluster, no long-press hit
    /// target. Aligns to the original sender's side (right for me,
    /// left for them) so it visually reads as the same message that
    /// lives further up in the (blurred) thread.
    @ViewBuilder
    private func floatingReplyParent(_ message: ChatMessage) -> some View {
        let isMe = message.senderId == currentUID
        HStack(spacing: 0) {
            if isMe { Spacer(minLength: 60) }
            ChatBubbleVisuals(
                message: message,
                isMe: isMe,
                currentUID: currentUID,
                friendName: friendName
            )
            if !isMe { Spacer(minLength: 60) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    /// Smooth-scroll to the parent of a quoted reply and briefly
    /// highlight that bubble so it's easy to spot in a busy thread.
    /// If the parent isn't currently in `messages` (because it's older
    /// than any earlier page that's been loaded yet), the scroll is a
    /// no-op — the user still has the inline `replyToPreview` snapshot
    /// for context, so the UX degrades gracefully.
    private func scrollToParent(messageId: String) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        pendingScrollAction = .toMessage(id: messageId, animated: true)
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

    /// Fetch the next 50 messages strictly older than `messages.first`
    /// and merge them into the visible array. The UIKit collection view
    /// preserves the user's reading position automatically by
    /// re-anchoring the previously-topmost message to the top after the
    /// snapshot applies, so no scroll-proxy plumbing is needed here.
    /// Guarded against re-entrancy (`isLoadingEarlier`) and end-of-
    /// history (`hasMoreEarlier`).
    private func triggerLoadEarlier() {
        guard hasMoreEarlier, !isLoadingEarlier else { return }
        guard let oldest = messages.first else { return }
        isLoadingEarlier = true
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
                }
                isLoadingEarlier = false
            }
        }
    }
}

/// Identifiable wrapper so a tapped chat song can carry the optional
/// `shares/{id}` doc id used to record a listen when opened externally.
private struct ChatSongTarget: Identifiable {
    let song: Song
    let listenShareId: String?
    var id: String { song.id }
}
