import SwiftUI
import UserNotifications

/// Screen 13 — Notifications permission.
///
/// Looping animated push banner sells the value, then the CTA actually
/// calls `NotificationPermission.requestAuthorizationAndRegister()` —
/// the same code path used by the post-onboarding fallback path. We
/// always advance once the prompt resolves (granted or denied) so the
/// user can never get stuck here.
struct NotificationsPermissionView: View {
    let appState: AppState
    let stepIdx: Int
    let totalSteps: Int
    let onContinue: () -> Void
    let onBack: (() -> Void)?

    @State private var requesting: Bool = false

    var body: some View {
        RiffScreenChrome(stepIdx: stepIdx, totalSteps: totalSteps, onBack: onBack) {
            RiffStagger(delay: 0.06) {
                RiffHeadline(text: "Turn on notifications so you'll know the moment a friend sends you a song.")
            }
            NotifLoop()
                .padding(.top, 24)
                .frame(maxHeight: .infinity)
        } footer: {
            RiffStagger(delay: 0.52) {
                RiffPrimaryButton(
                    title: requesting ? "Asking…" : "Continue",
                    disabled: requesting,
                    action: handleContinue
                )
            }
        }
    }

    private func handleContinue() {
        requesting = true
        Task {
            let status = await NotificationPermission.requestAuthorizationAndRegister()
            let allowed = status == .authorized || status == .provisional || status == .ephemeral
            await appState.setNotificationsEnabled(allowed)
            UserDefaults.standard.set(true, forKey: "hasRequestedNotificationPermission")
            await MainActor.run {
                requesting = false
                onContinue()
            }
        }
    }
}

// MARK: - Animated banner

private struct NotifLoop: View {
    @State private var startDate = Date()
    @Environment(\.riffTheme) private var theme

    var body: some View {
        TimelineView(.animation) { ctx in
            let elapsed = max(0, ctx.date.timeIntervalSince(startDate))
            let loop = 3.5
            let t = elapsed.truncatingRemainder(dividingBy: loop)

            let (yOff, opacity) = phase(at: t)

            GeometryReader { proxy in
                ZStack {
                    BannerCard()
                        .frame(width: proxy.size.width - 32)
                        .position(x: proxy.size.width / 2, y: yOff)
                        .opacity(opacity)
                }
                .clipped()
            }
        }
        .onAppear { startDate = Date() }
    }

    /// Mirrors the React reference timing: rise (0–0.5s), hold (0.5–2.7s),
    /// fly out (2.7–3.2s), gap (3.2–3.5s).
    private func phase(at t: Double) -> (CGFloat, Double) {
        if t < 0.5 {
            let p = t / 0.5
            let e = 1 - pow(1 - p, 3)
            let y = -100 + e * 130
            return (CGFloat(y), p)
        } else if t < 2.7 {
            return (50, 1)
        } else if t < 3.2 {
            let p = (t - 2.7) / 0.5
            let y = 50 - p * 80
            return (CGFloat(y), 1 - p)
        } else {
            return (-100, 0)
        }
    }
}

private struct BannerCard: View {
    @Environment(\.riffTheme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            RiffPlaceholderImage(seed: 80, cornerRadius: 8)
                .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 1) {
                HStack {
                    Text("RIFF")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.fg.opacity(0.7))
                    Spacer()
                    Text("now")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.fg.opacity(0.7))
                }
                Text("Holli sent you a song")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(theme.fg)
                Text("Big Time · Angel Olsen")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.fg.opacity(0.7))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(theme.isLight ? Color.white.opacity(0.95) : Color(white: 0.16).opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(theme.fg.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.35), radius: 30, x: 0, y: 12)
    }
}
