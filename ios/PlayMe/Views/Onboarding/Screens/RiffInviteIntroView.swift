import SwiftUI

/// Screen 11 — Invite intro (cinematic 8-dot reveal + premium teaser).
///
/// The premium copy ("first month of Premium is on us") is marketing-only;
/// no backend redemption is wired up here. It's safe to drop the line
/// later by hand if Premium never ships.
struct RiffInviteIntroView: View {
    let stepIdx: Int
    let totalSteps: Int
    let onContinue: () -> Void
    let onBack: (() -> Void)?

    var body: some View {
        RiffScreenChrome(stepIdx: stepIdx, totalSteps: totalSteps, onBack: onBack) {
            RiffStagger(delay: 0.06) {
                RiffHeadline(text: "Who do you want to discover music with?")
            }
            VStack(spacing: 26) {
                Spacer()
                Offer10Reveal()
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 30)
        } footer: {
            // The React reference holds the CTA reveal until ~4.8s so the
            // animation breathes. Match that with a Stagger delay.
            RiffStagger(delay: 4.8) {
                RiffPrimaryButton(title: "Continue", action: onContinue)
            }
        }
    }
}

private struct Offer10Reveal: View {
    @State private var phase: Int = 0          // 0 nothing → 4 sweep
    @State private var dotsFilled: Int = 0

    @Environment(\.riffTheme) private var theme

    var body: some View {
        VStack(spacing: 26) {
            Text("Invite up to 8 friends right now.")
                .font(.system(size: 22, weight: .medium))
                .tracking(-0.48)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .foregroundStyle(theme.fg)
                .frame(maxWidth: 300)
                .opacity(phase >= 1 ? 1 : 0)
                .offset(y: phase >= 1 ? 0 : 14)
                .scaleEffect(phase >= 1 ? 1 : 0.96)
                .animation(.spring(response: 0.7, dampingFraction: 0.7), value: phase)

            HStack(spacing: 10) {
                ForEach(0..<8, id: \.self) { i in
                    let filled = i < dotsFilled
                    Circle()
                        .fill(filled ? theme.fg : Color.clear)
                        .overlay(Circle().stroke(filled ? theme.fg : theme.border, lineWidth: 1.5))
                        .frame(width: 16, height: 16)
                        .scaleEffect(filled ? 1 : 0.85)
                        .shadow(color: filled ? theme.fg.opacity(0.18) : Color.clear, radius: filled ? 8 : 0)
                        .animation(.spring(response: 0.32, dampingFraction: 0.65), value: dotsFilled)
                }
            }

            ZStack {
                let copy = Group {
                    Text("Send all 8 and your first month of Premium ")
                        .font(.system(size: 26, weight: .bold))
                        .tracking(-0.65)
                    +
                    Text("is on us.")
                        .font(.system(size: 26, weight: .bold))
                        .tracking(-0.65)
                }
                copy
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .foregroundStyle(theme.fg)
                    .frame(maxWidth: 320)
                    .opacity(phase >= 3 ? 1 : 0)
                    .offset(y: phase >= 3 ? 0 : 14)
                    .scaleEffect(phase >= 3 ? 1 : 0.96)
                    .animation(.spring(response: 0.6, dampingFraction: 0.78), value: phase)
            }
        }
        .task { await runReveal() }
    }

    private func runReveal() async {
        try? await Task.sleep(for: .milliseconds(350));   phase = 1
        try? await Task.sleep(for: .milliseconds(1350));  phase = 2
        for i in 0..<8 {
            try? await Task.sleep(for: .milliseconds(170))
            dotsFilled = i + 1
        }
        try? await Task.sleep(for: .milliseconds(150));   phase = 3
        try? await Task.sleep(for: .milliseconds(700));   phase = 4
    }
}
