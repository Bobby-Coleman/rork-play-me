import SwiftUI

/// Foreground interactive layer for the Discovery screen. Sits on top of the
/// ambient `AlbumArtGridBackgroundView`.
///
/// * Center: "search a song" label + large magnifying glass icon. Entire
///   column is one big tap target.
/// * Bottom: "history" chevron hint telling the user they can scroll up to
///   see the feed below. No avatar — we intentionally keep the hint minimal
///   so it reads as a system affordance rather than a profile element.
struct DiscoveryOverlayView: View {
    let onSearchTap: () -> Void

    @State private var isPressed: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            Button(action: onSearchTap) {
                VStack(spacing: 20) {
                    Text("search a song")
                        .font(.system(size: 22, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                        .shadow(color: .black.opacity(0.5), radius: 10, y: 2)

                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 68, weight: .semibold))
                        .foregroundStyle(.white)
                        .shadow(color: .white.opacity(0.35), radius: 18)
                        .shadow(color: .black.opacity(0.55), radius: 18, y: 4)
                }
                .padding(.horizontal, 40)
                .padding(.vertical, 28)
                .contentShape(Rectangle())
                .scaleEffect(isPressed ? 0.97 : 1.0)
            }
            .buttonStyle(.plain)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in if !isPressed { isPressed = true } }
                    .onEnded { _ in isPressed = false }
            )

            Spacer(minLength: 0)

            historyHint
                .padding(.bottom, 24)
        }
    }

    private var historyHint: some View {
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
        DiscoveryOverlayView(onSearchTap: {})
    }
}
