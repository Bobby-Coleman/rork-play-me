import SwiftUI
import Combine

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

/// Primary search CTA. The label above the icon is purely decorative —
/// only the magnifying glass itself is the tappable button, so taps on
/// the surrounding padding / text area pass through to the grid behind
/// it. Keeps the hero's hit surface predictable.
struct DiscoverySearchCTA: View {
    let action: () -> Void
    let shazamAction: () -> Void
    var isShazamActive: Bool = false
    var shazamHint: String? = nil

    @State private var isPressed: Bool = false
    @State private var isShazamPressed: Bool = false

    var body: some View {
        VStack(spacing: 14) {
            Text("search a song")
                .font(.system(size: 22, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .shadow(color: .black.opacity(0.5), radius: 10, y: 2)
                .allowsHitTesting(false)

            // Keep the magnifier centered in the hero width; pin Shazam to the
            // left *of the magnifier* (not as a single centered HStack group).
            HStack(spacing: 0) {
                HStack {
                    Spacer(minLength: 0)
                    Button(action: shazamAction) {
                        ZStack {
                            if isShazamActive {
                                Circle()
                                    .stroke(Color.white.opacity(0.35), lineWidth: 1)
                                    .frame(width: 48, height: 48)
                                    .scaleEffect(1.08)
                            }
                            Image(systemName: "shazam.logo")
                                .symbolRenderingMode(.monochrome)
                                .font(.system(size: 30, weight: .semibold))
                                .foregroundStyle(.white.opacity(isShazamActive ? 1 : 0.82))
                                .shadow(color: .white.opacity(0.22), radius: 12)
                                .shadow(color: .black.opacity(0.55), radius: 14, y: 3)
                        }
                        .frame(width: 52, height: 52)
                        .scaleEffect(isShazamPressed ? 0.92 : 1.0)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Identify song with Shazam")
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in if !isShazamPressed { isShazamPressed = true } }
                            .onEnded { _ in isShazamPressed = false }
                    )
                }
                .frame(maxWidth: .infinity)

                Button(action: action) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 62, weight: .semibold))
                        .foregroundStyle(.white)
                        .shadow(color: .white.opacity(0.35), radius: 18)
                        .shadow(color: .black.opacity(0.55), radius: 18, y: 4)
                        .scaleEffect(isPressed ? 0.94 : 1.0)
                }
                .buttonStyle(.plain)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in if !isPressed { isPressed = true } }
                        .onEnded { _ in isPressed = false }
                )

                Color.clear
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)

            if let shazamHint {
                Text(shazamHint)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 260)
                    .transition(.opacity)
            }
        }
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

/// Small rotating album-art square rendered next to
/// `DiscoveryHistoryHint` on the hero page. Crossfades through the
/// first few received shares every ~2.2 seconds so users get a
/// subtle preview of what's waiting in the feed below, encouraging
/// them to scroll.
///
/// Pre-renders all provided thumbnails in a `ZStack` (toggled by
/// opacity) rather than swapping a single image's URL, so Nuke's
/// shared `ImageCache` serves each crossfade target instantly
/// without a network round-trip — no flash, no placeholder state
/// mid-rotation.
struct HistoryAlbumPreview: View {
    let shares: [SongShare]
    let side: CGFloat

    @State private var index: Int = 0

    var body: some View {
        ZStack {
            ForEach(Array(shares.enumerated()), id: \.element.id) { pair in
                AlbumArtSquare(
                    url: pair.element.song.albumArtURL,
                    cornerRadius: 6,
                    showsPlaceholderProgress: false,
                    showsShadow: false,
                    targetDecodeSide: side
                )
                .frame(width: side, height: side)
                .opacity(pair.offset == index ? 1 : 0)
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
        .onReceive(Timer.publish(every: 2.2, on: .main, in: .common).autoconnect()) { _ in
            guard shares.count > 1 else { return }
            withAnimation(.easeInOut(duration: 0.45)) {
                index = (index + 1) % shares.count
            }
        }
        .onChange(of: shares.map(\.id)) { _, _ in
            // When the underlying share list shrinks (e.g. user
            // refreshes and a message is removed), clamp the index
            // so we never index past the end of the new array.
            if index >= shares.count { index = 0 }
        }
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack(spacing: 40) {
            DiscoverySearchCTA(action: {}, shazamAction: {})
            DiscoveryHistoryHint()
        }
    }
}
