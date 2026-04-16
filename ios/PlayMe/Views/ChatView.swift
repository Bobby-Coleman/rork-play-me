import SwiftUI
import FirebaseFirestore

struct ChatView: View {
    let conversation: Conversation
    let appState: AppState

    @State private var messages: [ChatMessage] = []
    @State private var newMessageText: String = ""
    @State private var listener: ListenerRegistration?
    @State private var isSending: Bool = false
    @State private var sheetSong: Song?

    private var currentUID: String {
        FirebaseService.shared.firebaseUID ?? ""
    }

    private var friendName: String {
        conversation.friendName(currentUserId: currentUID)
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
        .onAppear {
            startListening()
            Task {
                await FirebaseService.shared.markConversationRead(conversationId: conversation.id)
            }
        }
        .onDisappear {
            listener?.remove()
            listener = nil
        }
        .sheet(item: $sheetSong) { song in
            SongDetailSheet(song: song, appState: appState, share: nil)
        }
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
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(isMe ? Color(red: 0.76, green: 0.38, blue: 0.35) : Color.white.opacity(0.1))
                        .clipShape(.rect(cornerRadius: 18))
                }

                Text(formattedTimestamp(message.timestamp))
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.2))
            }

            if !isMe { Spacer(minLength: 60) }
        }
    }

    private func inlineSongCard(_ song: Song) -> some View {
        Button {
            sheetSong = song
        } label: {
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
                    Text(song.artist)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(8)
            .background(Color.white.opacity(0.08))
            .clipShape(.rect(cornerRadius: 12))
            .frame(maxWidth: 240)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
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
