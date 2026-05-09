import SwiftUI

/// Screen 1 — Cold open + reveal.
///
/// Beats:
/// - 0.0–1.4s: 6 album-art images flicker, ~230ms each
/// - 1.4–1.9s: last image collapses → 6 dots in a hex around center
/// - 1.9–2.35s: dots converge to a single pulsing center dot
/// - 2.35–2.95s: dot expands → RIFF wordmark + scattered thumbnails
/// - 2.95s+: revealed state with typewriter tagline + CTAs
///
/// Album-art assets ship as image-set names `coldopen_1…coldopen_6` and
/// `reveal_1…reveal_10`. While the user has not provided photos yet,
/// `RiffPlaceholderImage` fills in.
struct ColdOpenSplashView: View {
    let onContinue: () -> Void
    let onSignIn: () -> Void

    /// Bumped by the orchestrator (or via `replayKey` from a re-render)
    /// to restart the cold-open animation. Mirrors the React `replayKey`
    /// pattern.
    var replayKey: Int = 0

    @State private var phase: Phase = .cold
    @State private var ckey: Int = 0

    private enum Phase { case cold, revealed }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch phase {
            case .cold:
                ColdOpenAnimation(key: ckey) {
                    withAnimation(.easeInOut(duration: 0.3)) { phase = .revealed }
                }
            case .revealed:
                ColdOpenRevealed(onContinue: onContinue, onSignIn: onSignIn)
            }
        }
        .onChange(of: replayKey) { _, _ in
            ckey += 1
            phase = .cold
        }
    }
}

// MARK: - Cold open animation

/// 4-beat timeline. We drive a single `progress` (0…1) and gate sub-views
/// on the elapsed seconds rather than per-beat booleans for smoother
/// transitions between beats.
private struct ColdOpenAnimation: View {
    var key: Int
    let onDone: () -> Void

    @State private var t: Double = 0

    private let flickerCount = 6
    private let flickerStep: Double = 0.23           // sec per flicker frame
    private var beat1End: Double { flickerStep * Double(flickerCount) }     // ~1.38
    private var beat2End: Double { beat1End + 0.5 }                         // ~1.88
    private var beat3End: Double { beat2End + 0.45 }                        // ~2.33
    private var beat4End: Double { beat3End + 0.6 }                         // ~2.93

    var body: some View {
        TimelineView(.animation) { context in
            Canvas { _, _ in }   // No-op; just to hook into TimelineView.
                .hidden()

            let elapsed = max(0, context.date.timeIntervalSince(startDate))
            let _ = handleProgress(elapsed)

            ZStack {
                if elapsed < beat1End {
                    flickerView(at: elapsed)
                } else if elapsed < beat2End {
                    collapseToDots(progress: clamp01((elapsed - beat1End) / 0.5))
                } else if elapsed < beat3End {
                    convergeToCenter(progress: clamp01((elapsed - beat2End) / 0.45))
                } else {
                    expandToWordmark(progress: clamp01((elapsed - beat3End) / 0.6))
                }
            }
        }
        .id(key)
        .onAppear {
            startDate = Date()
        }
    }

    // Persistent across timeline ticks.
    @State private var startDate: Date = Date()

    private func handleProgress(_ elapsed: Double) -> Double {
        if elapsed > beat4End + 0.6 {
            DispatchQueue.main.async { onDone() }
        }
        return elapsed
    }

    @ViewBuilder
    private func flickerView(at elapsed: Double) -> some View {
        let frame = min(flickerCount - 1, Int(elapsed / flickerStep))
        ZStack {
            ForEach(0..<flickerCount, id: \.self) { i in
                let isActive = i == frame
                let localT = (elapsed - Double(i) * flickerStep) / flickerStep
                let fade = clamp01(localT * 4)
                let scale = 1.04 - fade * 0.04

                ColdOpenArt(index: i)
                    .frame(width: 280, height: 280)
                    .opacity(isActive ? fade : 0)
                    .scaleEffect(isActive ? scale : 1.04)
            }
        }
    }

    @ViewBuilder
    private func collapseToDots(progress p: Double) -> some View {
        ZStack {
            // shrinking last image
            ColdOpenArt(index: flickerCount - 1)
                .frame(width: 280, height: 280)
                .scaleEffect(1 - p * 0.95)
                .opacity(1 - p)

            // emerging hex dots
            HexDots(progress: p, radius: 70)
        }
    }

    @ViewBuilder
    private func convergeToCenter(progress p: Double) -> some View {
        ZStack {
            // Dots travel from hex toward center.
            HexDotsConverging(progress: p, radius: 70)

            // Unified glowing dot becomes visible at end of beat.
            Circle()
                .fill(Color.white)
                .frame(width: 12, height: 12)
                .opacity(clamp01((p - 0.7) * 3))
                .shadow(color: Color.white.opacity(0.6), radius: 8)
        }
    }

    @ViewBuilder
    private func expandToWordmark(progress p: Double) -> some View {
        ZStack {
            // Expanding dot trace.
            Circle()
                .fill(Color.white)
                .frame(width: 12, height: 12)
                .scaleEffect(1 + p * 18)
                .opacity(max(0, 1 - p * 1.2))

            // Wordmark.
            RiffWordmark(size: 84, color: .white, style: .heavy)
                .scaleEffect(0.92 + p * 0.08)
                .opacity(clamp01((p - 0.3) * 2))

            // Scattered thumbnails.
            ColdOpenScatteredThumbs(progress: p)
        }
    }
}

// Beat 2: 6 dots emerge in a hexagon.
private struct HexDots: View {
    let progress: Double
    let radius: CGFloat

    var body: some View {
        ZStack {
            ForEach(0..<6, id: \.self) { i in
                let angle = (.pi / 3) * Double(i) - .pi / 2
                let x = cos(angle) * radius
                let y = sin(angle) * radius
                let appear = clamp01((progress - 0.4) * 2.5)
                let pulse = appear > 0.6 ? 1 + sin((progress - 0.7) * 18) * 0.15 : 1
                Circle()
                    .fill(Color.white)
                    .frame(width: 8, height: 8)
                    .opacity(appear)
                    .scaleEffect(appear * pulse)
                    .offset(x: x, y: y)
            }
        }
    }
}

// Beat 3: 6 dots converge to a single point.
private struct HexDotsConverging: View {
    let progress: Double
    let radius: CGFloat

    var body: some View {
        ZStack {
            ForEach(0..<6, id: \.self) { i in
                let angle = (.pi / 3) * Double(i) - .pi / 2
                let e = easeOutSpring(progress)
                let x = cos(angle) * radius * (1 - e)
                let y = sin(angle) * radius * (1 - e)
                Circle()
                    .fill(Color.white)
                    .frame(width: 8, height: 8)
                    .offset(x: x, y: y)
            }
        }
    }
}

// Beat 4: scattered thumbnails fade in around the wordmark.
private struct ColdOpenScatteredThumbs: View {
    let progress: Double

    private let scatter: [(x: CGFloat, y: CGFloat, size: CGFloat, seed: Int)] = [
        (-120, -150, 56, 11),
        ( 90, -170, 44, 12),
        (140, -70,  64, 13),
        (-160, -50, 48, 14),
        (-100, 110, 72, 15),
        ( 60, 130,  52, 16),
        (150, 80,   40, 17),
        (-150, 180, 58, 18),
        (130, 200,  46, 19),
        (-40, 230,  42, 20),
    ]

    var body: some View {
        ZStack {
            ForEach(0..<scatter.count, id: \.self) { i in
                let s = scatter[i]
                let delay = 0.25 + Double(i) / Double(scatter.count) * 0.55
                let local = clamp01((progress - delay) * 4)
                RevealThumb(seed: s.seed)
                    .frame(width: s.size, height: s.size)
                    .offset(x: s.x, y: s.y)
                    .opacity(local)
                    .scaleEffect(0.7 + local * 0.3)
            }
        }
    }
}

// MARK: - Revealed state

/// Static reveal screen mounted after the cold-open finishes. Wordmark
/// + scattered thumbs hold; tagline types out; CTAs fade in.
private struct ColdOpenRevealed: View {
    let onContinue: () -> Void
    let onSignIn: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ColdOpenStaticThumbs()

            VStack(spacing: 26) {
                Spacer()
                RiffWordmark(size: 84, color: .white, style: .heavy)
                RiffTypewriter(
                    text: "Discover new music from your best friends.",
                    startDelay: 0.3,
                    color: Color.white.opacity(0.78)
                )
                .frame(maxWidth: 280)
                Spacer()
            }

            VStack(spacing: 0) {
                Spacer()
                RiffStagger(delay: 0.42) {
                    RiffPrimaryButton(title: "Get started") { onContinue() }
                        .padding(.horizontal, 24)
                }
                RiffStagger(delay: 0.58) {
                    HStack(spacing: 4) {
                        Text("Already have an account?")
                            .foregroundStyle(Color.white.opacity(0.55))
                        Button(action: onSignIn) {
                            Text("Sign in")
                                .foregroundStyle(.white)
                                .fontWeight(.medium)
                        }
                        .buttonStyle(.plain)
                    }
                    .font(.system(size: 14))
                    .padding(.top, 16)
                }
                .padding(.bottom, 28)
            }
        }
        .riffTheme(.black)
        .preferredColorScheme(.dark)
    }
}

private struct ColdOpenStaticThumbs: View {
    private let scatter: [(x: CGFloat, y: CGFloat, size: CGFloat, seed: Int)] = [
        (-120, -120, 56, 11),
        ( 90, -140, 44, 12),
        (140, -40,  64, 13),
        (-160, -10, 48, 14),
        (-100, 110, 72, 15),
        ( 60, 130,  52, 16),
        (150, 100,  40, 17),
        (-150, 180, 58, 18),
        (100, 200,  46, 19),
    ]

    var body: some View {
        ZStack {
            ForEach(0..<scatter.count, id: \.self) { i in
                let s = scatter[i]
                RevealThumb(seed: s.seed)
                    .frame(width: s.size, height: s.size)
                    .offset(x: s.x, y: s.y)
            }
        }
    }
}

// MARK: - Helpers

/// Resolves a UIImage from an asset catalog name; falls back to placeholder.
private struct ColdOpenArt: View {
    let index: Int

    var body: some View {
        if let ui = UIImage(named: "coldopen_\(index + 1)") {
            Image(uiImage: ui)
                .resizable()
                .scaledToFill()
        } else {
            RiffPlaceholderImage(seed: index + 1)
        }
    }
}

private struct RevealThumb: View {
    let seed: Int

    var body: some View {
        if let ui = UIImage(named: "reveal_\(seed - 10)") {
            Image(uiImage: ui)
                .resizable()
                .scaledToFill()
                .clipShape(RoundedRectangle(cornerRadius: 4))
        } else {
            RiffPlaceholderImage(seed: seed, cornerRadius: 4)
        }
    }
}

private func clamp01(_ v: Double) -> Double {
    max(0, min(1, v))
}

private func easeOutSpring(_ t: Double) -> Double {
    if t >= 1 { return 1 }
    let c = 1.70158
    return 1 + (c + 1) * pow(t - 1, 3) + c * pow(t - 1, 2)
}
