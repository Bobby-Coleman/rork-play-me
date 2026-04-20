import SwiftUI
import Combine

struct SongCardView: View {
    let share: SongShare
    let isLiked: Bool
    let appState: AppState
    let onToggleLike: () -> Void

    private var audioPlayer: AudioPlayerService { AudioPlayerService.shared }
    @State private var resolvedSpotifyURL: String?
    @State private var showShareFlow: Bool = false
    @State private var replyText: String = ""
    @State private var showSentConfirmation: Bool = false
    @State private var isSendingReply: Bool = false
    @State private var keyboardHeight: CGFloat = 0
    @State private var reportTarget: ReportTarget?
    @State private var showReportedToast: Bool = false
    @State private var pendingBlock: AppUser?
    @FocusState private var isReplyFocused: Bool

    private var isCurrentSong: Bool {
        audioPlayer.currentSongId == share.song.id
    }

    private var isPlayingThis: Bool {
        isCurrentSong && audioPlayer.isPlaying
    }

    /// True when the current user is the sender of this share. Keeps parity
    /// with `SongDetailSheet` so a sent song never prompts a self-reply.
    private var viewerIsSender: Bool {
        guard let me = appState.currentUser?.id else { return false }
        return share.sender.id == me
    }

    /// The person on the other side of the share — the recipient when the
    /// viewer is the sender, the sender otherwise.
    private var otherParty: AppUser {
        viewerIsSender ? share.recipient : share.sender
    }

    private var headerLabel: String {
        if viewerIsSender {
            return "YOU SENT \(share.recipient.firstName.uppercased()) A SONG"
        } else {
            return "\(share.sender.firstName.uppercased()) SENT YOU A SONG"
        }
    }

    /// Full "First Last" for the sender; falls back to first name when the last name is missing.
    private var senderFullName: String {
        let trimmedLast = share.sender.lastName.trimmingCharacters(in: .whitespaces)
        if trimmedLast.isEmpty { return share.sender.firstName }
        return "\(share.sender.firstName) \(trimmedLast)"
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 32)

                VStack(spacing: 0) {
                    VStack(spacing: 4) {
                        Text(headerLabel)
                            .font(.system(size: 12, weight: .bold))
                            .tracking(1.5)
                            .foregroundStyle(.white.opacity(0.5))

                        Text(share.song.title)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)

                        Text(share.song.artist)
                            .font(.system(size: 15))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .padding(.top, 16)
                    .padding(.bottom, 20)

                    Color.clear
                        .frame(maxWidth: .infinity)
                        .frame(height: UIScreen.main.bounds.width - 48)
                        .overlay {
                            AsyncImage(url: URL(string: share.song.albumArtURL)) { phase in
                                if let image = phase.image {
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                } else if phase.error != nil {
                                    Color(.systemGray5)
                                } else {
                                    Color(.systemGray6)
                                        .overlay { ProgressView().tint(.white) }
                                }
                            }
                            .allowsHitTesting(false)
                        }
                        .clipShape(.rect(cornerRadius: 16))
                        .overlay(alignment: .topTrailing) {
                            Button {
                                onToggleLike()
                            } label: {
                                Image(systemName: isLiked ? "heart.fill" : "heart")
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundStyle(isLiked ? .pink : .white.opacity(0.8))
                                    .padding(10)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Circle())
                            }
                            .sensoryFeedback(.impact(weight: .medium), trigger: isLiked)
                            .padding(12)
                        }
                        .overlay(alignment: .topLeading) {
                            if !viewerIsSender {
                                Menu {
                                    Button(role: .destructive) {
                                        pendingBlock = share.sender
                                    } label: {
                                        Label("Block \(share.sender.firstName)", systemImage: "hand.raised.fill")
                                    }
                                    Button {
                                        reportTarget = .share(share)
                                    } label: {
                                        Label("Report song", systemImage: "flag.fill")
                                    }
                                } label: {
                                    Image(systemName: "ellipsis")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.85))
                                        .padding(10)
                                        .background(.ultraThinMaterial)
                                        .clipShape(Circle())
                                }
                                .padding(12)
                            }
                        }
                        .shadow(color: .white.opacity(0.05), radius: 20, y: 10)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 12)

                    HStack(spacing: 6) {
                        Text(viewerIsSender ? "You" : senderFullName)
                            .font(.system(size: 13, weight: .medium))
                        Text("·")
                        Text(share.timestamp, format: .dateTime.month(.abbreviated).day())
                    }
                    .foregroundStyle(.white.opacity(0.5))
                    .font(.system(size: 13))
                    .padding(.bottom, 8)

                    if let note = share.note {
                        Text("\"\(note)\"")
                            .font(.system(size: 15))
                            .foregroundStyle(.white.opacity(0.7))
                            .italic()
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                            .padding(.bottom, 12)
                    }

                    playerControls
                        .padding(.horizontal, 32)
                        .padding(.bottom, 12)
                }

                Spacer(minLength: 140)
            }
        }
        .overlay(alignment: .bottom) {
            replyBar
                .padding(.horizontal, 24)
                .padding(.bottom, keyboardHeight > 0 ? keyboardHeight + 8 : 24)
                .animation(.easeOut(duration: 0.25), value: keyboardHeight)
        }
        .onReceive(KeyboardObserver.shared.publisher) { height in
            keyboardHeight = height
        }
        .task {
            if appState.preferredMusicService == .spotify, let amURL = share.song.appleMusicURL {
                resolvedSpotifyURL = await MusicSearchService.shared.resolveSpotifyURL(appleMusicURL: amURL)
            }
        }
        .sheet(isPresented: $showShareFlow) {
            NavigationStack {
                FriendSelectorView(
                    song: share.song,
                    appState: appState,
                    onBack: { showShareFlow = false },
                    onSent: { showShareFlow = false }
                )
            }
            .presentationBackground(.black)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
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
                    .padding(.top, 40)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .alert("Block \(pendingBlock?.firstName ?? "user")?", isPresented: blockAlertBinding) {
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

    private var playerControls: some View {
        VStack(spacing: 8) {
            ScrubBarView(songId: share.song.id, fallbackDuration: share.song.duration)
                .padding(.bottom, 2)

            HStack(spacing: 12) {
                Button {
                    audioPlayer.play(song: share.song)
                } label: {
                    ZStack {
                        if isCurrentSong && audioPlayer.isLoading {
                            ProgressView()
                                .tint(.black)
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: isPlayingThis ? "pause.fill" : "play.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .contentTransition(.symbolEffect(.replace))
                        }
                    }
                    .foregroundStyle(.black)
                    .frame(width: 52, height: 40)
                    .background(.white)
                    .clipShape(.capsule)
                }
                .sensoryFeedback(.impact(weight: .light), trigger: isPlayingThis)

                openInServiceButton(song: share.song, service: appState.preferredMusicService, resolvedSpotifyURL: resolvedSpotifyURL)

                Button {
                    showShareFlow = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 40, height: 40)
                        .background(Color.white.opacity(0.08))
                        .clipShape(.capsule)
                }
            }

            if let error = audioPlayer.error,
               audioPlayer.currentSongId == nil || audioPlayer.currentSongId == share.song.id {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.top, 4)
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
                    TextField(viewerIsSender ? "Message \(otherParty.firstName)..." : "Reply to \(otherParty.firstName)...", text: $replyText)
                        .font(.system(size: 14))
                        .foregroundStyle(.white)
                        .tint(.white)
                        .focused($isReplyFocused)
                        .submitLabel(.send)
                        .onSubmit { sendReply() }

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
                                .foregroundStyle(Color(red: 0.76, green: 0.38, blue: 0.35))
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
        .animation(.easeInOut(duration: 0.2), value: showSentConfirmation)
    }

    private func sendReply() {
        let text = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let other = otherParty
        // Defensive guard: never allow a self-conversation, which would crash
        // downstream when creating a conversation with [uid, uid].
        if let me = appState.currentUser?.id, other.id == me {
            print("SongCardView: refusing to send reply to self (uid=\(me))")
            replyText = ""
            isReplyFocused = false
            return
        }
        isSendingReply = true
        let capturedText = text
        replyText = ""
        isReplyFocused = false

        Task {
            var success = false
            if let conv = await FirebaseService.shared.getOrCreateConversation(
                with: other.id,
                friendName: other.firstName
            ) {
                await appState.sendMessage(conversationId: conv.id, text: capturedText, song: share.song)
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
}

// MARK: - ScrubBarView (isolated progress observation)

struct ScrubBarView: View {
    let songId: String
    let fallbackDuration: String

    private var audioPlayer: AudioPlayerService { AudioPlayerService.shared }
    private var progressModel: PlayerProgressModel { AudioPlayerService.shared.progressModel }
    @State private var isScrubbing: Bool = false
    @State private var scrubValue: Double = 0

    private var isCurrentSong: Bool {
        audioPlayer.currentSongId == songId
    }

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                let width = geo.size.width
                let progressValue = isScrubbing ? scrubValue : (isCurrentSong ? progressModel.progress : 0)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.15))
                        .frame(height: 4)

                    Capsule()
                        .fill(Color.white.opacity(0.9))
                        .frame(width: max(0, width * progressValue), height: 4)

                    Circle()
                        .fill(.white)
                        .frame(width: isScrubbing ? 14 : 10, height: isScrubbing ? 14 : 10)
                        .offset(x: max(0, min(width * progressValue - (isScrubbing ? 7 : 5), width - (isScrubbing ? 14 : 10))))
                        .animation(.spring(duration: 0.2), value: isScrubbing)
                }
                .frame(height: 14)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isScrubbing = true
                            let fraction = max(0, min(1, value.location.x / width))
                            scrubValue = fraction
                        }
                        .onEnded { value in
                            let fraction = max(0, min(1, value.location.x / width))
                            if isCurrentSong {
                                let seekTime = fraction * progressModel.duration
                                audioPlayer.seek(to: seekTime)
                            }
                            isScrubbing = false
                        }
                )
            }
            .frame(height: 14)

            HStack {
                Text(isCurrentSong ? progressModel.formattedTime(progressModel.currentTime) : "0:00")
                    .monospacedDigit()
                Spacer()
                Text(isCurrentSong && progressModel.duration > 0 ? progressModel.formattedTime(progressModel.duration) : (fallbackDuration.isEmpty ? "0:30" : fallbackDuration))
                    .monospacedDigit()
            }
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.4))
        }
    }
}
