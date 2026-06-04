import SwiftUI

/// Shared pastel accent gradient (lavender -> pink -> peach) used to give
/// the app's "add friends" buttons a subtle, premium sheen and to drive
/// the attention-grabbing wave on the invite heading. Centralized here so
/// every add affordance reads from the same palette.
enum AppAccentGradient {
    static let lilac = Color(red: 0.80, green: 0.69, blue: 0.96)
    static let pink = Color(red: 0.97, green: 0.71, blue: 0.83)
    static let peach = Color(red: 0.99, green: 0.76, blue: 0.65)

    /// Diagonal fill for capsule add buttons. Pastel + light so black
    /// label text stays legible.
    static let button = LinearGradient(
        colors: [lilac, pink, peach],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Deeper members of the same hue family, used for filled surfaces that
    /// carry WHITE text (e.g. the sender's chat bubbles). The pastel
    /// `button` palette is too light for legible white text, so these are
    /// darkened versions of lilac/pink that keep the brand feel while
    /// staying high-contrast against white.
    static let deepLilac = Color(red: 0.45, green: 0.33, blue: 0.66)
    static let deepPink = Color(red: 0.67, green: 0.33, blue: 0.50)

    /// Diagonal fill for white-text surfaces (sender chat bubbles).
    static let bubble = LinearGradient(
        colors: [deepLilac, deepPink],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Horizontal stops used for the moving highlight band in
    /// `GradientWaveText`. Transparent on both ends so the band fades in
    /// and out as it sweeps across the glyphs.
    static let waveBand: [Color] = [.clear, lilac, pink, peach, .clear]
}

/// Text that periodically draws attention to itself: a soft gradient
/// "wave" sweeps across the glyphs and the whole line gives a slight
/// bounce, on a repeating interval. Used for the invite heading so the
/// user notices the "invite your N favorite people" call to action.
///
/// The base text renders in `baseColor`; the gradient is a masked,
/// horizontally translating band overlaid on top, so the effect is purely
/// visual (no layout reflow — `scaleEffect` is a render-time transform).
struct GradientWaveText: View {
    let text: String
    var font: Font = .system(size: 24, weight: .semibold)
    var tracking: CGFloat = -0.48
    var baseColor: Color = .white
    /// Seconds between waves.
    var interval: Double = 6.5

    /// -1 parks the band fully off the leading edge; +1 sends it fully
    /// past the trailing edge.
    @State private var phase: CGFloat = -1.0
    @State private var bounce: Bool = false

    var body: some View {
        Text(text)
            .font(font)
            .tracking(tracking)
            .foregroundStyle(baseColor)
            .overlay {
                GeometryReader { geo in
                    let w = geo.size.width
                    LinearGradient(
                        colors: AppAccentGradient.waveBand,
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: max(w * 0.55, 1))
                    .offset(x: phase * w * 1.3)
                    .frame(width: w, alignment: .leading)
                }
                .mask(
                    Text(text)
                        .font(font)
                        .tracking(tracking)
                )
                .allowsHitTesting(false)
            }
            .scaleEffect(bounce ? 1.05 : 1.0)
            .task { await runWaves() }
    }

    private func runWaves() async {
        try? await Task.sleep(for: .milliseconds(1500))
        while !Task.isCancelled {
            phase = -1.0
            // Slow, graceful sweep across the glyphs.
            withAnimation(.easeInOut(duration: 2.4)) { phase = 1.0 }
            withAnimation(.spring(response: 0.55, dampingFraction: 0.5)) { bounce = true }
            try? await Task.sleep(for: .milliseconds(620))
            withAnimation(.spring(response: 0.7, dampingFraction: 0.65)) { bounce = false }
            try? await Task.sleep(for: .seconds(interval))
        }
    }
}
