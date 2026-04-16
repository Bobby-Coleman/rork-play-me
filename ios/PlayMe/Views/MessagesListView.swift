import SwiftUI

struct MessagesListView: View {
    let appState: AppState

    @State private var quickSendRecipient: AppUser?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if appState.conversations.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 40))
                            .foregroundStyle(.white.opacity(0.15))
                        Text("No messages yet")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.4))
                        Text("Reply to a song to start a conversation")
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.25))
                    }
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
        .sheet(item: $quickSendRecipient) { recipient in
            QuickSendSongSheet(recipient: recipient, appState: appState)
        }
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
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        Text(friendName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)

                        Text(conversation.lastMessageText)
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.4))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .buttonStyle(.plain)

            Group {
                if conversation.songStreakCount > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 11))
                        Text("\(conversation.songStreakCount)")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundStyle(.orange)
                }
            }
            .frame(minWidth: 32, alignment: .center)

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

            Button {
                quickSendRecipient = recipientAppUser(for: conversation)
            } label: {
                Image(systemName: "music.note.list")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color(red: 0.76, green: 0.38, blue: 0.35))
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Search and send a song")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

