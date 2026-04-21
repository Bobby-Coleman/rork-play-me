import SwiftUI
import UIKit

struct HomeFeedView: View {
    let shares: [SongShare]
    let appState: AppState
    let onSendSong: () -> Void
    var onAddFriends: () -> Void = {}

    @State private var visibleShareId: String?
    @State private var replyText: String = ""
    @State private var isSendingReply: Bool = false
    @State private var showSentConfirmation: Bool = false
    @FocusState private var isReplyFocused: Bool

    private let scrollHaptic = UIImpactFeedbackGenerator(style: .soft)

    private var activeShare: SongShare? {
        if let id = visibleShareId {
            return shares.first { $0.id == id } ?? shares.first
        }
        return shares.first
    }

    private var viewerIsSender: Bool {
        guard let me = appState.currentUser?.id, let share = activeShare else { return false }
        return share.sender.id == me
    }

    /// The user the reply will be sent to — the recipient when the viewer is the
    /// sender (messaging your own recipient about a song you sent), the sender
    /// otherwise.
    private var replyRecipient: AppUser? {
        guard let share = activeShare else { return nil }
        return viewerIsSender ? share.recipient : share.sender
    }

    private var replyPlaceholder: String {
        guard let target = replyRecipient else { return "Reply..." }
        return viewerIsSender ? "Message \(target.firstName)..." : "Reply to \(target.firstName)..."
    }

    var body: some View {
        Group {
            if shares.isEmpty {
                emptyState
            } else {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(shares) { share in
                            SongCardView(
                                share: share,
                                isLiked: appState.isLiked(shareId: share.id),
                                appState: appState,
                                onToggleLike: { appState.toggleLike(shareId: share.id) }
                            )
                            .containerRelativeFrame(.vertical)
                            .id(share.id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $visibleShareId)
                .scrollIndicators(.hidden)
                .onChange(of: visibleShareId) { oldValue, newValue in
                    guard let newValue, let oldValue, newValue != oldValue else { return }
                    scrollHaptic.prepare()
                    scrollHaptic.impactOccurred(intensity: 0.65)
                    // Drafts shouldn't leak across recipients; drop focus and
                    // clear the text when the active share changes.
                    if isReplyFocused { isReplyFocused = false }
                    if !replyText.isEmpty { replyText = "" }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    replyBar
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Spacer(minLength: 0)
                addFriendsPill
                Spacer(minLength: 0)
            }
        }
    }

    private var replyBar: some View {
        ZStack {
            if showSentConfirmation {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.green)
                    Text("Sent!")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .transition(.opacity)
            } else {
                HStack(spacing: 8) {
                    TextField(replyPlaceholder, text: $replyText)
                        .font(.system(size: 14))
                        .foregroundStyle(.white)
                        .tint(.white)
                        .focused($isReplyFocused)
                        .submitLabel(.send)
                        .onSubmit { sendReply() }
                        .disabled(replyRecipient == nil)

                    if isReplyFocused && replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button { isReplyFocused = false } label: {
                            Text("Done")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }

                    if !replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button {
                            sendReply()
                        } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 26))
                                .foregroundStyle(.white)
                        }
                        .disabled(isSendingReply)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(white: 0.18).opacity(0.92))
                .clipShape(.capsule)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .animation(.easeInOut(duration: 0.2), value: showSentConfirmation)
    }

    private func sendReply() {
        let text = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let share = activeShare, let other = replyRecipient else { return }
        // Defensive guard: never allow a self-conversation, which would crash
        // downstream when creating a conversation with [uid, uid].
        if let me = appState.currentUser?.id, other.id == me {
            print("HomeFeedView: refusing to send reply to self (uid=\(me))")
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
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    private var emptyState: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "music.note")
                    .font(.system(size: 48))
                    .foregroundStyle(.white.opacity(0.2))

                Text("No songs yet")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)

                Text("Send a song to a friend\nand wait for one back")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)

                Button(action: onSendSong) {
                    Text("Send a Song")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 12)
                        .background(.white)
                        .clipShape(.capsule)
                }
                .padding(.top, 8)
            }
        }
    }
}
