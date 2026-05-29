import SwiftUI

/// Screen 8 — Music service selection (Spotify / Apple Music).
///
/// Persists `appState.preferredMusicService` and, only when Apple Music
/// is chosen, calls `AppleMusicSearchService.requestUserAuthorizationForPersonalization()`
/// before advancing — matching the deferred-prompt policy that the rest
/// of the app already follows.
struct MusicServiceView: View {
    let appState: AppState
    let stepIdx: Int
    let totalSteps: Int
    let onContinue: () -> Void
    let onBack: (() -> Void)?

    @State private var selected: MusicService? = nil
    @State private var requesting: Bool = false

    var body: some View {
        RiffScreenChrome(stepIdx: stepIdx, totalSteps: totalSteps, onBack: onBack) {
            RiffStagger(delay: 0.04) {
                RiffHeadline(text: "Where do you listen?")
            }

            Spacer(minLength: 0)

            // Single stagger wrapping both cards keeps the entrance subtle and,
            // crucially, avoids per-card spring offsets that were swallowing
            // early taps while the cards were still settling.
            RiffStagger(delay: 0.16) {
                VStack(spacing: 14) {
                    ServiceCard(
                        label: "Spotify",
                        on: selected == .spotify,
                        loading: requesting && selected == .spotify,
                        action: { select(.spotify) }
                    )
                    ServiceCard(
                        label: "Apple Music",
                        on: selected == .appleMusic,
                        loading: requesting && selected == .appleMusic,
                        action: { select(.appleMusic) }
                    )
                }
            }
            .disabled(requesting)

            Spacer(minLength: 0)
        } footer: {
            RiffStagger(delay: 0.30) {
                RiffPrimaryButton(
                    title: requesting ? "Just a sec…" : "Continue",
                    disabled: selected == nil || requesting,
                    action: handleContinue
                )
            }
        }
    }

    /// Tapping a card only selects it; advancing happens via the Continue
    /// button so the choice can be reviewed/changed before proceeding.
    private func select(_ service: MusicService) {
        guard !requesting else { return }
        selected = service
    }

    private func handleContinue() {
        guard let service = selected, !requesting else { return }
        appState.preferredMusicService = service

        guard service == .appleMusic else {
            onContinue()
            return
        }

        requesting = true
        Task {
            let status = await AppleMusicSearchService.shared.requestUserAuthorizationForPersonalization()
            await MainActor.run {
                appState.musicAuthStatus = status
                requesting = false
                onContinue()
            }
        }
    }
}

private struct ServiceCard: View {
    let label: String
    let on: Bool
    var loading: Bool = false
    let action: () -> Void

    @Environment(\.riffTheme) private var theme

    var body: some View {
        Button(action: action) {
            ZStack {
                Text(label)
                    .font(.system(size: 17, weight: .semibold))
                    .tracking(-0.2)
                    .foregroundStyle(on ? theme.bg : theme.fg)

                if loading {
                    HStack {
                        Spacer()
                        ProgressView()
                            .tint(on ? theme.bg : theme.fg)
                    }
                    .padding(.trailing, 22)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .contentShape(RoundedRectangle(cornerRadius: 18))
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(on ? theme.fg : Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.white.opacity(on ? 0 : 0.10), lineWidth: 1)
            )
        }
        .buttonStyle(PressableCardStyle())
        .animation(.easeInOut(duration: 0.18), value: on)
    }
}

/// Minimal press feedback that keeps a stable, full-card hit target (avoids
/// the "buttons not reliably pressing" feel from default plain-button styling
/// during entrance animations).
private struct PressableCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
