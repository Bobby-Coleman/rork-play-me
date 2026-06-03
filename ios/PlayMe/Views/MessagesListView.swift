import SwiftUI

struct MessagesListView: View {
    let appState: AppState
    let resetToken: Int

    @State private var quickSendRecipient: AppUser?
    @State private var navigationPath = NavigationPath()
    @State private var showAddFriends = false

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                Color.black.ignoresSafeArea()

                if appState.conversations.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(appState.conversations) { conversation in
                                conversationRow(conversation)

                                if conversation.id != appState.conversations.last?.id {
                                    Divider()
                                        .background(Color.white.opacity(0.06))
                                        .padding(.horizontal, 20)
                                }
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .navigationTitle("Messages")
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .navigationDestination(for: Conversation.self) { conversation in
                ChatView(conversation: conversation, appState: appState)
            }
        }
        .task {
            await appState.loadConversations()
        }
        .onAppear {
            resetToInbox()
        }
        .onChange(of: resetToken) { _, _ in
            resetToInbox()
        }
        .sheet(item: $quickSendRecipient) { recipient in
            QuickSendSongSheet(recipient: recipient, appState: appState)
        }
        .sheet(isPresented: $showAddFriends) {
            AddFriendsView(appState: appState)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 40))
                .foregroundStyle(.white.opacity(0.15))

            VStack(spacing: 8) {
                Text("No messages yet")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
                Text("Send your first song to start a conversation")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.25))
                    .multilineTextAlignment(.center)
            }

            Button {
                showAddFriends = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 13, weight: .bold))
                    Text("Add Friends")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(.black)
                .padding(.horizontal, 18)
                .padding(.vertical, 11)
                .background(Capsule().fill(AppAccentGradient.button))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(.horizontal, 40)
    }

    private func resetToInbox() {
        guard !navigationPath.isEmpty else { return }
        navigationPath = NavigationPath()
    }

    private func recipientAppUser(for conversation: Conversation) -> AppUser {
        let uid = FirebaseService.shared.firebaseUID ?? ""
        let fid = conversation.friendId(currentUserId: uid)
        if let friend = appState.friends.first(where: { $0.id == fid }) {
            return friend
        }
        let name = conversation.friendName(currentUserId: uid)
        return AppUser(id: fid, firstName: name, lastName: "", username: "", phone: "")
    }

    private func conversationRow(_ conversation: Conversation) -> some View {
        let uid = FirebaseService.shared.firebaseUID ?? ""
        let friendName = conversation.friendName(currentUserId: uid)
        let friend = recipientAppUser(for: conversation)

        return HStack(alignment: .center, spacing: 8) {
            NavigationLink(value: conversation) {
                HStack(spacing: 12) {
                    AppUserAvatar(user: friend, size: 44, background: Color.white.opacity(0.1))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(friendName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .minimumScaleFactor(0.8)

                        Text(conversation.lastMessageText)
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.4))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Group {
                        if conversation.songStreakCount > 0 {
                            Text("Streak \(conversation.songStreakCount)")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.88))
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                                .accessibilityLabel("Streak \(conversation.songStreakCount)")
                        } else {
                            Text("start a streak")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.white.opacity(0.32))
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                    }
                    .frame(minWidth: 72, alignment: .center)

                    VStack(alignment: .trailing, spacing: 4) {
                        Text(conversation.lastMessageTimestamp, format: .relative(presentation: .named))
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.25))

                        if conversation.unreadCount > 0 {
                            Text("\(conversation.unreadCount)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(red: 0.76, green: 0.38, blue: 0.35))
                                .clipShape(.capsule)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                quickSendRecipient = recipientAppUser(for: conversation)
            } label: {
                // Paperplane matches the primary "reply with a song"
                // affordance used on received song cards, so the gesture
                // reads as "send back / reply with a song" consistently
                // across surfaces instead of "browse your music" (the old
                // `music.note.list`).
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color(red: 0.76, green: 0.38, blue: 0.35))
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Reply with a song")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

}
