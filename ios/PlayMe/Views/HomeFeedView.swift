import SwiftUI
import UIKit
import Combine

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

    private let restingBottom: CGFloat = 8

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
                feed
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Spacer(minLength: 0)
                addFriendsPill
                Spacer(minLength: 0)
            }
        }
        .animation(.easeOut(duration: 0.22), value: isReplyFocused)
    }

    private var feed: some View {
        ZStack(alignment: .bottom) {
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
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
            .scrollPosition(id: $visibleShareId)
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.immediately)
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .onChange(of: visibleShareId) { oldValue, newValue in
                guard let newValue, let oldValue, newValue != oldValue else { return }
                scrollHaptic.prepare()
                scrollHaptic.impactOccurred(intensity: 0.65)
                if isReplyFocused { isReplyFocused = false }
                if !replyText.isEmpty { replyText = "" }
            }

            if isReplyFocused {
                Color.black.opacity(0.38)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { isReplyFocused = false }
                    .transition(.opacity)
            }

            replyBar
                .padding(.bottom, restingBottom)
        }
    }

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
                HStack(alignment: .bottom, spacing: 10) {
                    ZStack(alignment: .topLeading) {
                        if replyText.isEmpty {
                            Text(replyPlaceholder)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.white)
                                .shadow(color: .white.opacity(0.95), radius: 0, x: 0, y: 0)
                                .shadow(color: .white.opacity(0.75), radius: 6, x: 0, y: 0)
                                .shadow(color: .white.opacity(0.45), radius: 14, x: 0, y: 0)
                                .allowsHitTesting(false)
                        }
                        TextField("", text: $replyText, axis: .vertical)
                            .lineLimit(1...5)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.white)
                            .tint(.white)
                            .focused($isReplyFocused)
                            .disabled(replyRecipient == nil)
                    }

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
        .animation(.easeInOut(duration: 0.15), value: replyText.isEmpty)
    }

    private func sendReply() {
        let text = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let share = activeShare, let other = replyRecipient else { return }
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
