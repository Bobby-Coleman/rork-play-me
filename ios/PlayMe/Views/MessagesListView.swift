import SwiftUI

struct MessagesListView: View {
    let appState: AppState
    let resetToken: Int

    @State private var quickSendRecipient: AppUser?
    @State private var navigationPath = NavigationPath()
    @Environment(\.riffTheme) private var theme

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                theme.bg.ignoresSafeArea()

                if appState.conversations.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 40))
                            .foregroundStyle(theme.fg.opacity(0.18))
                        Text("No messages yet")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(theme.fg.opacity(0.45))
                        Text("Reply to a song to start a conversation")
                            .font(.system(size: 14))
                            .foregroundStyle(theme.faint)
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(appState.conversations) { conversation in
                                conversationRow(conversation)

                                if conversation.id != appState.conversations.last?.id {
                                    Divider()
                                        .background(theme.border.opacity(0.4))
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
            .toolbarColorScheme(theme.toolbarColorScheme, for: .navigationBar)
            .toolbarBackground(theme.bg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
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
    }

    private func resetToInbox() {
        guard !navigationPath.isEmpty else { return }
        navigationPath = NavigationPath()
    }

    private func recipientAppUser(for conversation: Conversation) -> AppUser {
        let uid = FirebaseService.shared.firebaseUID ?? ""
        let fid = conversation.friendId(currentUserId: uid)
        let name = conversation.friendName(currentUserId: uid)
        return AppUser(id: fid, firstName: name, lastName: "", username: "", phone: "")
    }

    private func conversationRow(_ conversation: Conversation) -> some View {
        let uid = FirebaseService.shared.firebaseUID ?? ""
        let friendName = conversation.friendName(currentUserId: uid)

        return HStack(alignment: .center, spacing: 8) {
            NavigationLink(value: conversation) {
                HStack(spacing: 12) {
                    Text(String(friendName.prefix(1)).uppercased())
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(theme.fg)
                        .frame(width: 44, height: 44)
                        .background(theme.softBg)
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        Text(friendName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(theme.fg)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .minimumScaleFactor(0.8)

                        Text(conversation.lastMessageText)
                            .font(.system(size: 13))
                            .foregroundStyle(theme.sub)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Group {
                        if conversation.songStreakCount > 0 {
                            Text("Streak \(conversation.songStreakCount)")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(theme.fg.opacity(0.88))
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                                .accessibilityLabel("Streak \(conversation.songStreakCount)")
                        } else {
                            Text("start a streak")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(theme.faint)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                    }
                    .frame(minWidth: 72, alignment: .center)

                    VStack(alignment: .trailing, spacing: 4) {
                        Text(conversation.lastMessageTimestamp, format: .relative(presentation: .named))
                            .font(.system(size: 11))
                            .foregroundStyle(theme.faint)

                        if conversation.unreadCount > 0 {
                            Text("\(conversation.unreadCount)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(theme.accentOn)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(theme.accent)
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
                    .foregroundStyle(theme.accentOn)
                    .frame(width: 36, height: 36)
                    .background(theme.accent)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Reply with a song")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

}
