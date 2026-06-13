import SwiftUI
import WidgetKit

/// Screen 14 — Add the widget.
///
/// Replaces `WidgetInstructionsView`. Shows a swipeable carousel of
/// realistic widget-face previews (CD / CD dark / Classic) — the centered
/// page is the selection — plus the numbered instructions, inside
/// `RiffScreenChrome` so it inherits the active theme.
struct RiffWidgetView: View {
    let appState: AppState
    let stepIdx: Int
    let totalSteps: Int
    let onDone: () -> Void
    let onSkip: () -> Void
    let onBack: (() -> Void)?

    @Environment(\.riffTheme) private var theme

    @State private var isChecking = false
    @State private var showNotFoundAlert = false

    /// Widget kind string declared by the `PlayMeWidget` extension. Must match
    /// `StaticConfiguration(kind:)` for detection to work.
    private let widgetKind = "PlayMeWidget"

    var body: some View {
        RiffScreenChrome(stepIdx: stepIdx, totalSteps: totalSteps, onBack: onBack) {
            RiffStagger(delay: 0.06) {
                RiffHeadline(text: "Add the RIFF widget to your home screen.")
            }

            WidgetStyleCarousel(appState: appState, tileSize: 180, foreground: theme.fg)
                .padding(.top, 14)
                .padding(.bottom, 12)

            VStack(alignment: .leading, spacing: 14) {
                instructionRow(number: "1", text: "Hold down on any app to edit your Home Screen.")
                instructionRow(number: "2", text: "Tap the + button in the top left.")
                instructionRow(number: "3", text: "Search for \"RIFF\" and add the widget.")
            }
            .padding(.top, 4)

            Spacer(minLength: 0)
        } footer: {
            VStack(spacing: 0) {
                RiffPrimaryButton(
                    title: isChecking ? "Checking…" : "I added the widget",
                    disabled: isChecking,
                    action: verifyWidgetInstalled
                )
                RiffTextLink(title: "I'll do it later", action: onSkip)
                    .padding(.top, 4)
            }
        }
        .alert("We can't see the RIFF widget yet", isPresented: $showNotFoundAlert) {
            Button("Try again", action: verifyWidgetInstalled)
            Button("Continue anyway", action: onDone)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Make sure you added the RIFF widget to your Home Screen, then tap Try again.")
        }
    }

    /// Confirms the user actually installed the widget before advancing.
    /// `WidgetCenter.getCurrentConfigurations` returns the widgets of our kinds
    /// currently on the Home Screen. If none are found we prompt rather than
    /// silently advancing; if the API errors we fall back to the same prompt
    /// so the user is never hard-blocked.
    private func verifyWidgetInstalled() {
        guard !isChecking else { return }
        isChecking = true
        WidgetCenter.shared.getCurrentConfigurations { result in
            DispatchQueue.main.async {
                isChecking = false
                switch result {
                case .success(let infos):
                    if infos.contains(where: { $0.kind == widgetKind }) {
                        onDone()
                    } else {
                        showNotFoundAlert = true
                    }
                case .failure:
                    showNotFoundAlert = true
                }
            }
        }
    }

    private func instructionRow(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(number)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(theme.bg)
                .frame(width: 26, height: 26)
                .background(Circle().fill(theme.fg))

            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(theme.fg.opacity(0.7))
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

