import SwiftUI

/// Screen 14 — Add the widget.
///
/// Replaces `WidgetInstructionsView`. Shows an animated home-screen mock
/// with a pulsing widget tile and the same numbered instructions, but
/// inside `RiffScreenChrome` so it inherits the active theme.
struct RiffWidgetView: View {
    let stepIdx: Int
    let totalSteps: Int
    let onDone: () -> Void
    let onSkip: () -> Void
    let onBack: (() -> Void)?

    @Environment(\.riffTheme) private var theme

    var body: some View {
        RiffScreenChrome(stepIdx: stepIdx, totalSteps: totalSteps, onBack: onBack) {
            RiffStagger(delay: 0.06) {
                RiffHeadline(text: "Add the RIFF widget to your home screen.")
            }
            HomeScreenMock()
                .padding(.top, 18)
                .padding(.bottom, 14)

            VStack(alignment: .leading, spacing: 14) {
                instructionRow(number: "1", text: "Hold down on any app to edit your Home Screen.")
                instructionRow(number: "2", text: "Tap the + button in the top left.")
                instructionRow(number: "3", text: "Search for \"RIFF\" and add the widget.")
            }
            .padding(.top, 4)

            Spacer(minLength: 0)
        } footer: {
            VStack(spacing: 0) {
                RiffPrimaryButton(title: "I added the widget", action: onDone)
                RiffTextLink(title: "I'll do it later", action: onSkip)
                    .padding(.top, 4)
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

private struct HomeScreenMock: View {
    @State private var pulse = false
    @Environment(\.riffTheme) private var theme

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18)
                .fill(theme.softBg)

            VStack(spacing: 10) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4),
                          spacing: 10) {
                    ForEach(0..<8, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 8)
                            .fill(theme.fg.opacity(0.18))
                            .frame(height: 44)
                    }
                }
                HStack(spacing: 10) {
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(theme.fg.opacity(pulse ? 0.32 : 0.18))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("RIFF")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(theme.bg)
                            Spacer(minLength: 0)
                            HStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(theme.bg.opacity(0.55))
                                    .frame(width: 22, height: 22)
                                VStack(alignment: .leading, spacing: 1) {
                                    RoundedRectangle(cornerRadius: 2).fill(theme.bg.opacity(0.65)).frame(height: 6)
                                    RoundedRectangle(cornerRadius: 2).fill(theme.bg.opacity(0.4)).frame(width: 50, height: 5)
                                }
                            }
                        }
                        .padding(8)
                    }
                    .frame(width: 96, height: 96)
                    .scaleEffect(pulse ? 1.04 : 1)
                    .shadow(color: pulse ? theme.fg.opacity(0.35) : Color.clear, radius: 14)

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2),
                              spacing: 10) {
                        ForEach(0..<4, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 8)
                                .fill(theme.fg.opacity(0.18))
                                .frame(height: 44)
                        }
                    }
                }
            }
            .padding(14)
        }
        .frame(height: 220)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}
