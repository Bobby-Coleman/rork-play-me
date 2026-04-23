import SwiftUI
import FirebaseFirestore
import UserNotifications

struct ChatView: View {
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

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(messages) { message in
                                messageBubble(message)
                                    .id(message.id)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .scrollIndicators(.hidden)
                    .onChange(of: messages.count) { _, _ in
                        if let last = messages.last {
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }

                inputBar
            }
        }
        .navigationTitle(friendName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
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
    }

    private var blockAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingBlock != nil },
            set: { if !$0 { pendingBlock = nil } }
        )
    }

    private func messageBubble(_ message: ChatMessage) -> some View {
        let isMe = message.senderId == currentUID

        return HStack {
            if isMe { Spacer(minLength: 60) }

            VStack(alignment: isMe ? .trailing : .leading, spacing: 4) {
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

                Text(formattedTimestamp(message.timestamp))
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.2))
            }

            if !isMe { Spacer(minLength: 60) }
        }
    }

    private func inlineSongCard(_ song: Song) -> some View {
        HStack(spacing: 10) {
            AsyncImage(url: URL(string: song.albumArtURL)) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Color(.systemGray5)
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(.rect(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if song.artistId != nil {
                    Button {
                        artistSong = song
                    } label: {
                        Text(song.artist)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(song.artist)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(8)
        .background(Color.white.opacity(0.08))
        .clipShape(.rect(cornerRadius: 12))
        .frame(maxWidth: 240)
        .contentShape(.rect)
        .onTapGesture {
            sheetSong = song
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Message...", text: $newMessageText)
                .font(.system(size: 15))
                .foregroundStyle(.white)
                .tint(.white)
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
        newMessageText = ""

        Task {
            await appState.sendMessage(conversationId: conversation.id, text: text)
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
        listener = FirebaseService.shared.listenForMessages(conversationId: conversation.id) { newMessages in
            Task { @MainActor in
                let newIds = newMessages.map(\.id)
                let oldIds = self.messages.map(\.id)
                if newIds != oldIds {
                    self.messages = newMessages
                }
            }
        }
    }
}
