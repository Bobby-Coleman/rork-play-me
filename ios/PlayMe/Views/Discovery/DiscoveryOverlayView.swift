import SwiftUI

/// Foreground components for the Discovery hero page. Exposed as two small,
/// intrinsically-sized views so the parent VStack can control vertical
/// positioning without fighting internal Spacers:
///
/// * `DiscoverySearchCTA` — "search a song" text + large magnifier button.
/// * `DiscoveryHistoryHint` — the "history" capsule + chevron.
///
/// The old `DiscoveryOverlayView` wrapper used infinite Spacers to center
/// itself, which collided with the new layout where we want the grid + CTA
/// centered and the history hint pinned to the bottom.

/// Primary search CTA. Flows at natural size so the parent lays it out.
struct DiscoverySearchCTA: View {
    let action: () -> Void
    @State private var isPressed: Bool = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 14) {
                Text("search a song")
                    .font(.system(size: 22, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(color: .black.opacity(0.5), radius: 10, y: 2)

                Image(systemName: "magnifyingglass")
                    .font(.system(size: 62, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .white.opacity(0.35), radius: 18)
                    .shadow(color: .black.opacity(0.55), radius: 18, y: 4)
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 18)
            .contentShape(Rectangle())
            .scaleEffect(isPressed ? 0.97 : 1.0)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if !isPressed { isPressed = true } }
                .onEnded { _ in isPressed = false }
        )
    }
}

/// Pill-shaped hint telling the user they can swipe up to see the
/// history/feed. Rendered as a standalone view so the parent can anchor it
/// to the bottom of the hero.
struct DiscoveryHistoryHint: View {
    var body: some View {
        HStack(spacing: 8) {
            Text("history")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
            Image(systemName: "chevron.down")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white.opacity(0.8))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.4), radius: 10, y: 2)
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack(spacing: 40) {
            DiscoverySearchCTA(action: {})
            DiscoveryHistoryHint()
        }
    }
}
