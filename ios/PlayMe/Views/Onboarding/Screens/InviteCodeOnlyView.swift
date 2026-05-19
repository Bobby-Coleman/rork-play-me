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
    /// Set when a deep-link-supplied code has been validated and we're
    /// flashing a brief "Invite code accepted" affordance before
    /// auto-advancing. While true, the form is locked.
    @State private var autoAdvanceConfirming = false
    /// One-shot guard so a re-render of this view (e.g. theme change)
    /// doesn't re-trigger the deep-link auto-fill after the user has
    /// already typed over it.
    @State private var didAttemptDeepLinkAutofill = false

    @Environment(\.riffTheme) private var theme

    private var canContinue: Bool {
        let code = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines)
        return !isChecking && !autoAdvanceConfirming && code.count >= 4
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

            if autoAdvanceConfirming {
                Text("Invite code accepted — welcome to RIFF.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.fg.opacity(0.8))
                    .padding(.top, 12)
                    .transition(.opacity)
            } else if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .padding(.top, 12)
            }

            Spacer(minLength: 0)
        }
        .task(id: showForm) {
            // Auto-fill from a deep-link-supplied invite code the first
            // time the form actually appears. Gating on `showForm`
            // (rather than `.onAppear`) avoids racing the typewriter
            // intro and avoids re-firing if SwiftUI rebuilds the view
            // body. The deep-link code is consumed immediately so a
            // subsequent gate visit (e.g. user backs out + comes back)
            // shows the empty form rather than re-auto-fill.
            guard showForm, !didAttemptDeepLinkAutofill else { return }
            didAttemptDeepLinkAutofill = true
            guard let pending = DeepLinkService.shared.pendingInviteCode,
                  !pending.isEmpty else { return }
            DeepLinkService.shared.clearPendingInviteCode()
            await autoSubmit(code: pending.uppercased())
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

    /// Validates a deep-link-supplied code and, if it's good, briefly
    /// confirms before advancing. On failure, the code shows up in the
    /// field so the user can correct it manually.
    private func autoSubmit(code: String) async {
        inviteCode = code
        isChecking = true
        errorMessage = nil

        let ok = await appState.validateInviteCode(code)
        isChecking = false

        if ok {
            appState.inviteCode = code
            withAnimation(.easeOut(duration: 0.18)) {
                autoAdvanceConfirming = true
            }
            try? await Task.sleep(for: .milliseconds(650))
            onValidated()
        } else {
            errorMessage = appState.inviteCodeError ?? "That invite code didn't work."
        }
    }
}
