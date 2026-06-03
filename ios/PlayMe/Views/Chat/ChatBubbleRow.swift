import SwiftUI
import UIKit

/// Full row content for the chat collection view's message cell.
///
/// Renders:
///  - The bubble visuals (quoted-reply chip + song card + text bubble)
///  - The reaction-badge cluster floating off the bubble corner
///  - A small absolute timestamp underneath the bubble
///  - An iMessage-style "Read" indicator below the most recently-read send
///
/// Long-press fires `onLongPress` with the bubble's frame in window
/// coordinates so the overlay can animate from-position into the
/// centered lift, matching iMessage's reaction-tray feel.
struct ChatBubbleRow: View {
    let message: ChatMessage
    let isMe: Bool
    let isHighlighted: Bool
    let isMostRecentRead: Bool
    let currentUID: String
    let friendName: String

    let onTapSong: (ChatMessage) -> Void
    let onTapArtist: (Song) -> Void
    let onTapQuotedReply: (String) -> Void
    let onLongPress: (CGRect) -> Void

    @State private var capturedFrame: CGRect = .zero

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            HStack(spacing: 0) {
                if isMe { Spacer(minLength: 60) }

                VStack(alignment: isMe ? .trailing : .leading, spacing: 4) {
                    ChatBubbleVisuals(
                        message: message,
                        isMe: isMe,
                        currentUID: currentUID,
                        friendName: friendName,
                        onTapSong: onTapSong,
                        onTapArtist: onTapArtist,
                        onTapQuotedReply: onTapQuotedReply
                    )
                    .scaleEffect(isHighlighted ? 1.04 : 1)
                    .animation(.spring(response: 0.35, dampingFraction: 0.65), value: isHighlighted)
                    .overlay(alignment: isMe ? .bottomLeading : .bottomTrailing) {
                        if !message.reactions.isEmpty {
                            ReactionBadgeCluster(
                                reactions: message.reactions,
                                currentUserUID: currentUID
                            )
                            // Tuck the cluster onto the bubble's bottom corner
                            // (overlapping inward, iMessage-style) instead of
                            // floating off to the side.
                            .offset(x: isMe ? 12 : -12, y: 6)
                            .zIndex(1)
                        }
                    }
                    .padding(.bottom, message.reactions.isEmpty ? 0 : 12)
                    .background(
                        GeometryReader { proxy in
                            // Publish the bubble's frame in window
                            // coordinates so the long-press handler can
                            // pass it up to the overlay for from-position
                            // lift animation, iMessage-style.
                            Color.clear
                                .preference(
                                    key: BubbleFramePreferenceKey.self,
                                    value: proxy.frame(in: .global)
                                )
                        }
                    )
                    .onPreferenceChange(BubbleFramePreferenceKey.self) { frame in
                        capturedFrame = frame
                    }
                    .onLongPressGesture(minimumDuration: 0.35) {
                        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                        onLongPress(capturedFrame)
                    }

                    Text(ChatBubbleRow.formattedTimestamp(message.timestamp))
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.2))
                }

                if !isMe { Spacer(minLength: 60) }
            }

            if isMostRecentRead {
                Text("Read")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.trailing, 4)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isMostRecentRead)
    }

    /// Same casing/format as the previous in-line ChatView implementation
    /// so the visual is identical after the refactor.
    static func formattedTimestamp(_ date: Date) -> String {
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
}

private struct BubbleFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

// MARK: - Bubble visuals (shared between row + reaction overlay)

/// Bare bubble content: quoted-reply chip + song card + text bubble.
/// No timestamp, no reaction overlay, no spacer alignment — those are
/// the row wrapper's responsibility. Factored out so the lifted copy
/// in `ReactionMenuOverlay` can render the same pixels as the in-list
/// row from a single source of truth.
struct ChatBubbleVisuals: View {
    let message: ChatMessage
    let isMe: Bool
    let currentUID: String
    let friendName: String

    /// Optional callbacks. The reaction-overlay's lifted copy passes nil
    /// for these because in-overlay taps would be ambiguous against the
    /// dismiss-on-tap-outside gesture.
    var onTapSong: ((ChatMessage) -> Void)? = nil
    var onTapArtist: ((Song) -> Void)? = nil
    var onTapQuotedReply: ((String) -> Void)? = nil

    var body: some View {
        VStack(alignment: isMe ? .trailing : .leading, spacing: 4) {
            if let preview = message.replyToPreview {
                quotedReplySnippet(preview, isMe: isMe)
                    .contentShape(.rect)
                    .onTapGesture {
                        onTapQuotedReply?(preview.messageId)
                    }
            }

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
        }
    }

    @ViewBuilder
    private func quotedReplySnippet(_ preview: ReplyPreview, isMe: Bool) -> some View {
        let displaySnippet: String = {
            if let songTitle = preview.songTitle, !songTitle.isEmpty {
                return "🎵 \(songTitle)"
            }
            return preview.textSnippet.isEmpty ? "Message" : preview.textSnippet
        }()
        let parentSenderName: String = preview.senderId == currentUID ? "You" : friendName

        HStack(spacing: 8) {
            Capsule()
                .fill(Color.white.opacity(0.45))
                .frame(width: 2)
            VStack(alignment: .leading, spacing: 1) {
                Text(parentSenderName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.65))
                Text(displaySnippet)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: 240, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }

    private func inlineSongCard(_ song: Song) -> some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: URL(string: song.albumArtURL)) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Color(.systemGray5)
                }
            }
            .frame(width: 190, height: 190)
            .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.72)],
                startPoint: .center,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(song.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                if song.artistId != nil, let onTapArtist {
                    Button {
                        onTapArtist(song)
                    } label: {
                        Text(song.artist)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.72))
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(song.artist)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)
                }
            }
            .padding(12)
        }
        .frame(width: 190, height: 190)
        .clipShape(.rect(cornerRadius: 14))
        .contentShape(.rect)
        .onTapGesture {
            onTapSong?(message)
        }
    }
}
