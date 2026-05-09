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
            RiffStagger(delay: 0.06) {
                RiffHeadline(text: "Where do you listen?")
            }
            VStack(spacing: 12) {
                RiffStagger(delay: 0.22) {
                    ServiceCard(
                        label: "Spotify",
                        on: selected == .spotify,
                        markBg: Color(red: 0.118, green: 0.843, blue: 0.376),
                        markFg: .black,
                        markText: "S",
                        action: { selected = .spotify }
                    )
                }
                RiffStagger(delay: 0.30) {
                    ServiceCard(
                        label: "Apple Music",
                        on: selected == .appleMusic,
                        markBg: Color(red: 0.98, green: 0.141, blue: 0.235),
                        markFg: .white,
                        markText: "♪",
                        action: { selected = .appleMusic }
                    )
                }
            }
            .padding(.top, 28)

            Spacer(minLength: 0)
        } footer: {
            RiffStagger(delay: 0.52) {
                RiffPrimaryButton(
                    title: requesting ? "Just a sec…" : "Continue",
                    disabled: selected == nil || requesting,
                    action: handleContinue
                )
            }
        }
    }

    private func handleContinue() {
        guard let service = selected else { return }
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
    let markBg: Color
    let markFg: Color
    let markText: String
    let action: () -> Void

    @Environment(\.riffTheme) private var theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    if label == "Spotify" {
                        Circle().fill(markBg)
                    } else {
                        RoundedRectangle(cornerRadius: 7).fill(markBg)
                    }
                    Text(markText)
                        .font(.system(size: label == "Spotify" ? 14 : 12, weight: .heavy))
                        .foregroundStyle(markFg)
                }
                .frame(width: 28, height: 28)

                Text(label)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(theme.fg)

                Spacer()

                ZStack {
                    Circle()
                        .stroke(on ? theme.fg : theme.border, lineWidth: 1.5)
                        .background(Circle().fill(on ? theme.fg : Color.clear))
                        .frame(width: 22, height: 22)
                    if on {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(theme.bg)
                    }
                }
            }
            .padding(.horizontal, 18)
            .frame(height: 76)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(on ? theme.softBg : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(on ? theme.fg : theme.border, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}
