import SwiftUI

/// Invite-only step: validates code via Cloud Function, then advances to phone.
struct InviteCodeOnlyView: View {
    let appState: AppState
    let onValidated: () -> Void
    let onBack: (() -> Void)?

    @State private var inviteCode: String = ""
    @State private var isChecking = false
    @State private var errorMessage: String?

    private var canContinue: Bool {
        let code = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines)
        return !isChecking && code.count >= 4
    }

    var body: some View {
        RiffScreenChrome(
            onBack: onBack,
            showProgressDots: false
        ) {
            RiffStagger(delay: 0.06) {
                RiffHeadline(text: "RIFF is invite-only.")
            }
            RiffStagger(delay: 0.14) {
                RiffSubhead(text: "Enter your invite code to continue.")
                    .padding(.top, 12)
            }

            RiffStagger(delay: 0.22) {
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
                .padding(.top, 36)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .padding(.top, 12)
            }

            Spacer(minLength: 0)
        } footer: {
            VStack(spacing: 0) {
                RiffStagger(delay: 0.42) {
                    RiffPrimaryButton(
                        title: isChecking ? "Checking…" : "Continue",
                        disabled: !canContinue,
                        action: submit
                    )
                }
                #if DEBUG
                RiffTextLink(title: "Skip invite (dev)") {
                    appState.inviteCode = ""
                    appState.inviteCodeError = nil
                    onValidated()
                }
                .padding(.top, 12)
                #endif
            }
        }
        .appKeyboardDismiss()
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
