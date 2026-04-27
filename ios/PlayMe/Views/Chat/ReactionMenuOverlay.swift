import SwiftUI
import UIKit

/// iMessage-style reaction tray + action panel that appears full-screen
/// when a user long-presses on a chat bubble. The original message is
/// dimmed in the underlying list and a re-rendered copy floats centered
/// on a `.ultraThinMaterial` backdrop. Six default emoji reactions sit
/// above the floated bubble; a compact Reply/Copy action panel sits
/// below it. Tapping anywhere outside the tray dismisses with a spring.
///
/// The overlay is intentionally stateless — it owns no Firestore
/// writes, focus state, or pasteboard side effects beyond Copy. All
/// persistence flows back through callbacks so `ChatView` remains the
/// single source of truth for message state.
struct ReactionMenuOverlay<BubbleContent: View>: View {
    /// The message being acted on. Drives the reaction-tray highlight
    /// (so the user sees what they've already picked) and the Copy
    /// button's enabled state (disabled on empty-text song messages).
    let message: ChatMessage

    /// True when the long-pressed bubble was sent by the current user.
    /// Used purely for layout — the lifted bubble, tray, and action
    /// panel all align to the same side as the original bubble so the
    /// transition reads as a "lift" rather than a teleport.
    let isMe: Bool

    /// Current user's Firebase UID. Required because reactions are
    /// keyed by UID and the overlay needs to know which entry (if any)
    /// belongs to the active user for toggle semantics + highlight.
    let currentUserUID: String

    /// Tap-an-emoji callback. Caller is responsible for the Firestore
    /// write. Empty string is never passed; emoji is always one of the
    /// six in `Self.emojis`.
    let onReact: (String) -> Void

    /// Fired when the user re-taps the emoji they already reacted with
    /// (toggle-off semantics, matches iMessage). Caller should delete
    /// the user's `reactions.<uid>` field.
    let onClearReaction: () -> Void

    /// Tap-Reply callback. Caller sets `pendingReplyTo` on `ChatView`,
    /// dismisses this overlay, and focuses the composer.
    let onReply: () -> Void

    /// Tap-Copy callback. The overlay copies `message.text` to the
    /// system pasteboard before invoking this — caller's only job is
    /// to dismiss + show any toast.
    let onCopy: () -> Void

    /// Dismiss callback for tap-outside or after a successful action.
    let onDismiss: () -> Void

    /// Re-rendered bubble content, supplied as a `@ViewBuilder` from
    /// `ChatView` so the overlay's lifted copy is pixel-identical to
    /// the original (same gradient, padding, song card, quoted reply,
    /// etc.) without us having to maintain a parallel renderer.
    @ViewBuilder let bubbleContent: () -> BubbleContent

    @State private var animateIn: Bool = false

    /// Default reaction set — heart, thumbs up, thumbs down, ha-ha,
    /// emphasis, question. Mirrors iMessage's tapback options aside
    /// from "??" (we use the question emoji directly for clarity).
    private static var emojis: [String] {
        ["❤️", "👍", "👎", "😂", "‼️", "❓"]
    }

    var body: some View {
        ZStack {
            // Dimmed + blurred backdrop. The .contentShape ensures the
            // tap target covers the whole screen so users can dismiss
            // by tapping any non-tray pixel.
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
                .overlay(Color.black.opacity(0.35).ignoresSafeArea())
                .contentShape(.rect)
                .onTapGesture { dismiss() }

            VStack(spacing: 14) {
                trayRow
                bubbleRow
                actionPanelRow
            }
            .padding(.horizontal, 20)
            .opacity(animateIn ? 1 : 0)
            .scaleEffect(animateIn ? 1 : 0.92)
        }
        .onAppear {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                animateIn = true
            }
        }
    }

    // MARK: - Subviews

    private var trayRow: some View {
        HStack {
            if isMe { Spacer(minLength: 0) }
            emojiTray
            if !isMe { Spacer(minLength: 0) }
        }
    }

    private var bubbleRow: some View {
        HStack {
            if isMe { Spacer(minLength: 0) }
            bubbleContent()
            if !isMe { Spacer(minLength: 0) }
        }
    }

    private var actionPanelRow: some View {
        HStack {
            if isMe { Spacer(minLength: 0) }
            actionPanel
            if !isMe { Spacer(minLength: 0) }
        }
    }

    private var emojiTray: some View {
        HStack(spacing: 6) {
            ForEach(Self.emojis, id: \.self) { emoji in
                emojiButton(emoji)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.7))
                .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.5))
        )
        .shadow(color: .black.opacity(0.4), radius: 12, x: 0, y: 4)
    }

    private func emojiButton(_ emoji: String) -> some View {
        let isActive = message.reactions[currentUserUID] == emoji
        return Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            if isActive {
                onClearReaction()
            } else {
                onReact(emoji)
            }
        } label: {
            Text(emoji)
                .font(.system(size: 28))
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(isActive
                              ? Color(red: 0.76, green: 0.38, blue: 0.35).opacity(0.55)
                              : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(accessibilityLabel(for: emoji)))
    }

    private var actionPanel: some View {
        VStack(spacing: 0) {
            actionRow(systemImage: "arrowshape.turn.up.left.fill", title: "Reply") {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onReply()
            }
            Divider().background(Color.white.opacity(0.1))
            actionRow(systemImage: "doc.on.doc", title: "Copy", isEnabled: !message.text.isEmpty) {
                UIPasteboard.general.string = message.text
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onCopy()
            }
        }
        .frame(width: 180)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.7))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                )
        )
        .shadow(color: .black.opacity(0.4), radius: 12, x: 0, y: 4)
    }

    private func actionRow(
        systemImage: String,
        title: String,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .medium))
                Text(title)
                    .font(.system(size: 15))
                Spacer()
            }
            .foregroundStyle(.white.opacity(isEnabled ? 1 : 0.35))
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    private func accessibilityLabel(for emoji: String) -> String {
        switch emoji {
        case "❤️": return "Love"
        case "👍": return "Like"
        case "👎": return "Dislike"
        case "😂": return "Laugh"
        case "‼️": return "Emphasize"
        case "❓": return "Question"
        default: return emoji
        }
    }

    private func dismiss() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            animateIn = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            onDismiss()
        }
    }
}
