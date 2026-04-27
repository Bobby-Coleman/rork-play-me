import SwiftUI

/// Small overlay cluster that renders a deduped, count-suffixed group
/// of emoji reactions on a message bubble. Sits on the bottom-trailing
/// (or bottom-leading, depending on bubble alignment) corner of the
/// bubble — positioning is the parent's responsibility.
///
/// Example: { aliceUID: "❤️", bobUID: "❤️", carolUID: "😂" }
/// renders as `❤️😂 3` because there are two distinct emoji and three
/// total reactors.
struct ReactionBadgeCluster: View {
    /// `[uid: emoji]` map straight from `ChatMessage.reactions`.
    let reactions: [String: String]

    /// Highlights the current user's reaction with a subtle ring so
    /// they can quickly see what they've already picked.
    let currentUserUID: String

    /// Order-stable, deduped list of distinct emojis. Sorted by first
    /// occurrence in the underlying map for visual stability across
    /// snapshot updates (so adding a third reactor doesn't reshuffle
    /// the cluster).
    private var distinctEmojis: [String] {
        var seen: Set<String> = []
        var ordered: [String] = []
        // Iterate in a deterministic order — sorted UIDs — so the
        // visual order is the same on every device.
        for uid in reactions.keys.sorted() {
            guard let emoji = reactions[uid], !seen.contains(emoji) else { continue }
            seen.insert(emoji)
            ordered.append(emoji)
        }
        return ordered
    }

    private var totalCount: Int { reactions.count }

    private var currentUserEmoji: String? { reactions[currentUserUID] }

    var body: some View {
        if reactions.isEmpty {
            EmptyView()
        } else {
            HStack(spacing: 2) {
                ForEach(distinctEmojis, id: \.self) { emoji in
                    Text(emoji)
                        .font(.system(size: 13))
                        .overlay {
                            if emoji == currentUserEmoji {
                                Circle()
                                    .stroke(Color(red: 0.76, green: 0.38, blue: 0.35), lineWidth: 1.5)
                                    .padding(-2)
                            }
                        }
                }
                if totalCount > 1 {
                    Text("\(totalCount)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.leading, 2)
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.85))
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                    )
            )
            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
        }
    }
}
