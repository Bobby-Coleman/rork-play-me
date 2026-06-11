import SwiftUI

/// Locket-style viewer for a single calendar day's songs. Presented when a
/// day cell is tapped. Songs page horizontally (with the neighbors peeking
/// at the edges as a swipe cue) and a thumbnail strip at the bottom lets the
/// user jump between them. Each card is a full player: artwork, the sender's
/// avatar + the message they sent (no quotes), and a play / like / open /
/// send action row.
///
/// Songs arrive deduped: one `DaySongGroup` per unique song that day. A
/// group carries every share of that song (same song sent to N friends),
/// and sent-scope cards render a "Sent to …" recipient summary that
/// expands into the full list when it's long.
struct DayCarouselView: View {
    let groups: [DaySongGroup]
    let appState: AppState
    var startIndex: Int = 0

    @Environment(\.dismiss) private var dismiss
    @State private var currentGroupId: String?
    @State private var sendShare: SongShare?
    /// Group ids whose long recipient list is expanded.
    @State private var expandedRecipientGroupIds: Set<String> = []

    private var audioPlayer: AudioPlayerService { AudioPlayerService.shared }

    init(groups: [DaySongGroup], appState: AppState, startIndex: Int = 0) {
        self.groups = groups
        self.appState = appState
        self.startIndex = startIndex
        let safe = min(max(0, startIndex), max(0, groups.count - 1))
        let seed = groups.indices.contains(safe) ? groups[safe].id : nil
        _currentGroupId = State(initialValue: seed)
    }

    var body: some View {
        GeometryReader { geo in
            let cardWidth = max(0, geo.size.width - 80)

            ZStack(alignment: .top) {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    header
                        .padding(.top, 12)
                        .padding(.bottom, 18)

                    pager(cardWidth: cardWidth)

                    thumbnailStrip
                        .padding(.top, 16)
                        .padding(.bottom, 8)
                }

                closeButton
                    .padding(.top, 10)
                    .padding(.leading, 16)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { playCurrent() }
        .onChange(of: currentGroupId) { _, _ in playCurrent() }
        .sheet(item: $sendShare) { share in
            SongActionSheet(song: share.song, appState: appState, share: share)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 2) {
            if let date = groups.first?.timestamp {
                Text(Self.yearFormatter.string(from: date))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
                Text(Self.dateFormatter.string(from: date))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity)
        // Keep the centered date clear of the 36pt close button (plus its
        // 16pt leading inset) that overlays the same top edge.
        .padding(.horizontal, 60)
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 36, height: 36)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
        }
        .accessibilityLabel("Close")
    }

    // MARK: - Pager

    private func pager(cardWidth: CGFloat) -> some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 16) {
                ForEach(groups) { group in
                    card(group, width: cardWidth)
                        .frame(width: cardWidth)
                        .id(group.id)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $currentGroupId)
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, 40, for: .scrollContent)
    }

    @ViewBuilder
    private func card(_ group: DaySongGroup, width: CGFloat) -> some View {
        let share = group.primary
        let song = group.song
        let trimmedNote = share.note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        VStack(spacing: 14) {
            if !trimmedNote.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    AppUserAvatar(user: share.sender, size: 26, background: Color.white.opacity(0.16))
                    Text(trimmedNote)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 4)
            }

            AlbumArtSquare(url: song.albumArtURL, cornerRadius: 22, showsShadow: true)
                .frame(width: width, height: width)
                .overlay(alignment: .topTrailing) {
                    likeButton(song: song, share: share)
                        .padding(12)
                }

            Text(share.timestamp, format: .dateTime.hour().minute())
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))

            VStack(spacing: 3) {
                Text(song.title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(song.artist)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)
            }

            recipientRow(for: group)

            actionRow(song: song, share: share)
        }
    }

    // MARK: - Recipients

    /// "Sent to …" summary on a sent card. 1–3 recipients render inline;
    /// longer lists collapse to "A, B +N" and expand on tap into the full
    /// avatar + name list.
    @ViewBuilder
    private func recipientRow(for group: DaySongGroup) -> some View {
        if group.primary.sender.id == appState.currentUser?.id, !group.recipients.isEmpty {
            if group.recipients.count <= 3 {
                Text("Sent to \(inlineNames(group.recipients))")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            } else {
                let expanded = expandedRecipientGroupIds.contains(group.id)
                VStack(spacing: 8) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if expanded {
                                expandedRecipientGroupIds.remove(group.id)
                            } else {
                                expandedRecipientGroupIds.insert(group.id)
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(expanded
                                 ? "Sent to \(group.recipients.count) people"
                                 : "Sent to \(collapsedNames(group.recipients))")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white.opacity(0.5))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white.opacity(0.4))
                                .rotationEffect(.degrees(expanded ? 180 : 0))
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(expanded ? "Hide recipients" : "Show all recipients")

                    if expanded {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(group.shares) { share in
                                    HStack(spacing: 8) {
                                        AppUserAvatar(user: share.recipient, size: 22, background: Color.white.opacity(0.16))
                                        Text(displayName(share.recipient))
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundStyle(.white.opacity(0.85))
                                        Spacer(minLength: 0)
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                        }
                        .frame(maxHeight: 132)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal, 8)
                    }
                }
            }
        }
    }

    private func displayName(_ user: AppUser) -> String {
        user.firstName.isEmpty ? "@\(user.username)" : user.firstName
    }

    /// "Alice", "Alice & Bob", "Alice, Bob & Cara".
    private func inlineNames(_ users: [AppUser]) -> String {
        let names = users.map(displayName)
        switch names.count {
        case 1: return names[0]
        case 2: return "\(names[0]) & \(names[1])"
        default: return "\(names.dropLast().joined(separator: ", ")) & \(names[names.count - 1])"
        }
    }

    /// "Alice, Bob +3" for collapsed long lists.
    private func collapsedNames(_ users: [AppUser]) -> String {
        let shown = users.prefix(2).map(displayName)
        return "\(shown.joined(separator: ", ")) +\(users.count - shown.count)"
    }

    // MARK: - Actions

    private func likeButton(song: Song, share: SongShare) -> some View {
        let liked = appState.isLikedSong(song.id)
        return Button {
            appState.toggleLikeSong(song, share: share)
        } label: {
            Image(systemName: liked ? "heart.fill" : "heart")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(liked ? AnyShapeStyle(AppAccentGradient.button) : AnyShapeStyle(Color.white.opacity(0.85)))
                .padding(10)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: liked)
    }

    private func actionRow(song: Song, share: SongShare) -> some View {
        HStack(spacing: 12) {
            Button {
                audioPlayer.play(song: song)
                recordListenIfReceived(share, source: "preview")
            } label: {
                Image(systemName: isPlaying(song) ? "pause.fill" : "play.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .foregroundStyle(.black)
                    .frame(width: 52, height: 40)
                    .background(.white)
                    .clipShape(.capsule)
            }
            .sensoryFeedback(.impact(weight: .light), trigger: isPlaying(song))

            openInServiceButton(
                song: song,
                service: appState.preferredMusicService,
                shareId: share.id,
                onOpened: { recordListenIfReceived(share, source: "service") }
            )

            Button {
                sendShare = share
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.08))
                    .clipShape(.capsule)
            }
        }
    }

    // MARK: - Thumbnail strip

    private var thumbnailStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(groups) { group in
                        let isCurrent = group.id == currentGroupId
                        Button {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                currentGroupId = group.id
                            }
                        } label: {
                            AlbumArtSquare(
                                url: group.song.albumArtURL,
                                cornerRadius: 8,
                                showsPlaceholderProgress: false,
                                showsShadow: false,
                                targetDecodeSide: 60
                            )
                            .frame(width: 44, height: 44)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(AppAccentGradient.button, lineWidth: isCurrent ? 2.5 : 0)
                            )
                            .opacity(isCurrent ? 1 : 0.5)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .id("thumb-\(group.id)")
                    }
                }
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)
            .onChange(of: currentGroupId) { _, newValue in
                guard let newValue else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo("thumb-\(newValue)", anchor: .center)
                }
            }
        }
    }

    // MARK: - Helpers

    private func isPlaying(_ song: Song) -> Bool {
        audioPlayer.currentSongId == song.id && audioPlayer.isPlaying
    }

    private func playCurrent() {
        guard let id = currentGroupId,
              let group = groups.first(where: { $0.id == id }) else { return }
        if audioPlayer.currentSongId != group.song.id {
            audioPlayer.play(song: group.song)
        }
        recordListenIfReceived(group.primary, source: "preview")
    }

    private func recordListenIfReceived(_ share: SongShare, source: String) {
        guard let me = appState.currentUser?.id,
              share.recipient.id == me, share.sender.id != me else { return }
        Task { await FirebaseService.shared.markShareListened(shareId: share.id, source: source) }
    }

    // MARK: - Formatters

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM d"
        return f
    }()

    private static let yearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy"
        return f
    }()
}
