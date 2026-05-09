import SwiftUI

struct MessagesListView: View {
    let appState: AppState
    let resetToken: Int

    @State private var quickSendRecipient: AppUser?
    @State private var navigationPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navigationPath) {
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
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())

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
                            streakBadge(for: conversation)
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

    private func streakBadge(for conversation: Conversation) -> some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            HStack(spacing: 5) {
                StreakCountdownRing(progress: streakRemainingProgress(for: conversation, now: timeline.date))

                Text("\(conversation.songStreakCount)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.88))
            }
            .accessibilityLabel("Streak \(conversation.songStreakCount)")
        }
    }

    private func streakRemainingProgress(for conversation: Conversation, now: Date) -> Double {
        guard let deadline = streakResetDeadline(for: conversation),
              let start = streakStartDate(for: conversation) else {
            return 0
        }
        let total = deadline.timeIntervalSince(start)
        guard total > 0 else { return 0 }
        let remaining = deadline.timeIntervalSince(now)
        return max(0, min(1, remaining / total))
    }

    private func streakResetDeadline(for conversation: Conversation) -> Date? {
        guard let start = streakStartDate(for: conversation) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar.date(byAdding: .day, value: 2, to: start)
    }

    private func streakStartDate(for conversation: Conversation) -> Date? {
        guard let lastDay = conversation.songStreakLastDay else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: lastDay)
    }
}

private struct StreakCountdownRing: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.16), lineWidth: 1.4)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    Color.white.opacity(0.86),
                    style: StrokeStyle(lineWidth: 1.4, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 14, height: 14)
    }
}
