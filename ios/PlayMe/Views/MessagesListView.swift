import SwiftUI

struct MessagesListView: View {
    let appState: AppState
    let resetToken: Int

    @State private var quickSendRecipient: AppUser?
    @State private var navigationPath = NavigationPath()
    @State private var showAddFriends = false

    /// One row per friend, with the matching conversation attached when one
    /// exists. Friends you haven't started a thread with still appear (with a
    /// "send them a song" hint), so the screen reads as a friends list.
    private struct FriendInboxRow: Identifiable {
        let friend: AppUser
        let conversation: Conversation?
        var id: String { friend.id }
    }

    private var inboxRows: [FriendInboxRow] {
        let uid = FirebaseService.shared.firebaseUID ?? ""
        var convByFriend: [String: Conversation] = [:]
        for c in appState.conversations {
            convByFriend[c.friendId(currentUserId: uid)] = c
        }

        var rows = appState.friends.map { friend in
            FriendInboxRow(friend: friend, conversation: convByFriend[friend.id])
        }

        // Fallback: include any conversation whose participant isn't in the
        // friends array yet (e.g. friends list still hydrating) so existing
        // threads never vanish.
        let coveredIds = Set(appState.friends.map(\.id))
        for c in appState.conversations {
            let fid = c.friendId(currentUserId: uid)
            guard !coveredIds.contains(fid) else { continue }
            let name = c.friendName(currentUserId: uid)
            let derived = AppUser(id: fid, firstName: name, lastName: "", username: "", phone: "")
            rows.append(FriendInboxRow(friend: derived, conversation: c))
        }

        return rows.sorted { a, b in
            switch (a.conversation, b.conversation) {
            case let (ca?, cb?):
                return ca.lastMessageTimestamp > cb.lastMessageTimestamp
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return a.friend.firstName.localizedCaseInsensitiveCompare(b.friend.firstName) == .orderedAscending
            }
        }
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    statsHeader

                    if inboxRows.isEmpty {
                        emptyState
                            .frame(maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(inboxRows) { row in
                                    friendRow(row)

                                    if row.id != inboxRows.last?.id {
                                        Divider()
                                            .background(Color.white.opacity(0.06))
                                            .padding(.horizontal, 20)
                                    }
                                }
                            }
                        }
                        .scrollIndicators(.hidden)
                        .refreshable {
                            await appState.loadConversations()
                            await appState.refreshFriends()
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Friends")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
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

    // MARK: - Header stats

    private var statsHeader: some View {
        HStack(spacing: 10) {
            statPill(
                icon: "music.note",
                text: appState.uniqueSongsSentCount == 1 ? "1 song" : "\(appState.uniqueSongsSentCount) songs"
            )
            statPill(
                icon: "flame.fill",
                text: "\(appState.effectiveSendDayStreak)d streak"
            )
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 14)
    }

    private func statPill(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(AppAccentGradient.button)
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Capsule().fill(Color.white.opacity(0.08)))
    }

    // MARK: - Empty state (no friends yet)

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.2")
                .font(.system(size: 40))
                .foregroundStyle(.white.opacity(0.15))

            VStack(spacing: 8) {
                Text("No friends yet")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
                Text("Add friends, then send a song to start a conversation")
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

    // MARK: - Rows

    @ViewBuilder
    private func friendRow(_ row: FriendInboxRow) -> some View {
        HStack(alignment: .center, spacing: 8) {
            if let conversation = row.conversation {
                NavigationLink(value: conversation) {
                    rowInner(friend: row.friend, conversation: conversation)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Button {
                    quickSendRecipient = row.friend
                } label: {
                    rowInner(friend: row.friend, conversation: nil)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                quickSendRecipient = row.friend
            } label: {
                // Paperplane = "send / reply with a song", matching the
                // affordance on received song cards. Uses the same accent
                // gradient as the Add button.
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppAccentGradient.button)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Send a song to \(row.friend.firstName)")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func rowInner(friend: AppUser, conversation: Conversation?) -> some View {
        HStack(spacing: 12) {
            AppUserAvatar(user: friend, size: 44, background: Color.white.opacity(0.1))

            VStack(alignment: .leading, spacing: 3) {
                Text(friend.firstName.isEmpty ? "@\(friend.username)" : friend.firstName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.8)

                if let conversation, !conversation.lastMessageText.isEmpty {
                    Text(conversation.lastMessageText)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.4))
                        .lineLimit(1)
                } else {
                    Text("Send them a song to start a conversation")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.3))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let conversation {
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
                            .background(AppAccentGradient.bubble)
                            .clipShape(.capsule)
                    }
                }
            }
        }
        .contentShape(Rectangle())
    }
}
