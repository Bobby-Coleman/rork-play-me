import SwiftUI

struct MessagesListView: View {
    let appState: AppState

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
                                NavigationLink(value: conversation) {
                                    conversationRow(conversation)
                                }

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
    }

    private func conversationRow(_ conversation: Conversation) -> some View {
        let uid = FirebaseService.shared.firebaseUID ?? ""
        let friendName = conversation.friendName(currentUserId: uid)

        return HStack(spacing: 12) {
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

            Spacer()

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
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}
