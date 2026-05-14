import SwiftUI

private let inviteTypewriterLine = "Right now, Riff is invite only."

/// Invite-only step: validates code via Cloud Function, then advances to phone.
struct InviteCodeOnlyView: View {
    let appState: AppState
    let onValidated: () -> Void
    let onBack: (() -> Void)?

    @State private var inviteCode: String = ""
    @State private var isChecking = false
    @State private var errorMessage: String?
    @State private var showForm = false

    @Environment(\.riffTheme) private var theme

    private var canContinue: Bool {
        let code = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines)
        return !isChecking && code.count >= 4
    }

    var body: some View {
        RiffScreenChrome(
            onBack: onBack,
            showProgressDots: false
        ) {
            Group {
                if showForm {
                    OnboardingUpperFormSlot {
                        formStack
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                } else {
                    GeometryReader { geo in
                        VStack {
                            Spacer()
                            RiffTypewriter(
                                text: inviteTypewriterLine,
                                startDelay: 0.22,
                                charDelay: 0.034,
                                font: .system(size: 30, weight: .semibold),
                                alignment: .center,
                                color: theme.fg,
                                onFinishTyping: {
                                    withAnimation(.easeOut(duration: 0.38)) {
                                        showForm = true
                                    }
                                }
                            )
                            .padding(.horizontal, 8)
                            Spacer()
                        }
                        .frame(width: geo.size.width, height: geo.size.height)
                    }
                }
            }
        } footer: {
            if showForm {
                VStack(spacing: 0) {
                    RiffPrimaryButton(
                        title: isChecking ? "Checking…" : "Continue",
                        disabled: !canContinue,
                        action: submit
                    )
                    #if DEBUG
                    RiffTextLink(title: "Skip invite (dev)") {
                        appState.inviteCode = ""
                        appState.inviteCodeError = nil
                        onValidated()
                    }
                    .padding(.top, 12)
                    #endif
                }
                .transition(.opacity)
            }
        }
        .appKeyboardDismiss()
    }

    private var formStack: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(inviteTypewriterLine)
                .font(.system(size: 30, weight: .semibold))
                .tracking(-30 * 0.022)
                .foregroundStyle(theme.fg)
                .fixedSize(horizontal: false, vertical: true)

            RiffSubhead(text: "Enter your invite code to continue.")
                .padding(.top, 12)

            VStack(alignment: .leading, spacing: 8) {
                RiffLabel(text: "Invite code")
                RiffFieldInput(
                    text: $inviteCode,
                    placeholder: "••••••",
                    monospace: true,
                    capitalization: .characters,
                    autocorrection: false,
                    maxLength: 8,
                    autoFocus: true,
                    onChange: { v in
                        inviteCode = v.uppercased()
                    },
                    onSubmit: {
                        if canContinue { submit() }
                    }
                )
            }
            .padding(.top, 24)

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .padding(.top, 12)
            }

            Spacer(minLength: 0)
        }
    }

    private func submit() {
        guard canContinue else { return }
        errorMessage = nil
        isChecking = true
        let trimmed = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        Task {
            let ok = await appState.validateInviteCode(trimmed)
            isChecking = false
            if ok {
                appState.inviteCode = trimmed
                onValidated()
            } else {
                errorMessage = appState.inviteCodeError ?? "That invite code didn't work."
            }
        }
    }
}
