import SwiftUI

/// Screen 4 — OTP verify.
///
/// Uses a native SwiftUI `TextField` with `.oneTimeCode` so iOS SMS
/// autofill works reliably across iOS versions. SwiftUI updates the
/// binding no matter how the system injects the code (delegate path or a
/// direct `.text` set), which the previous UIKit `OTPTextField` could not
/// do consistently — that fragility is why autofill worked on some phones
/// but not others.
struct OTPVerifyView: View {
    let appState: AppState
    let onVerified: () -> Void
    let onBack: (() -> Void)?

    @State private var codeText: String = ""
    @State private var isVerifying = false
    @State private var errorMessage: String?
    @State private var isResending = false
    @State private var resendCooldownRemaining = 0
    @State private var resendCountThisSession = 0
    @State private var resendConfirmation: String?
    /// Debounce so the user sees the filled code briefly before we
    /// auto-submit, and so a re-fired autofill doesn't double-submit.
    @State private var autoSubmitWork: DispatchWorkItem?

    @FocusState private var fieldFocused: Bool

    @Environment(\.riffTheme) private var theme

    var body: some View {
        RiffScreenChrome(onBack: onBack, showProgressDots: false) {
            OnboardingUpperFormSlot {
                VStack(alignment: .leading, spacing: 0) {
                    RiffHeadline(text: "Enter the code")
                    RiffSubhead(text: "We sent a 6-digit code to your phone.")
                        .padding(.top, 8)

                    TextField("", text: $codeText)
                        .textContentType(.oneTimeCode)
                        .keyboardType(.numberPad)
                        .focused($fieldFocused)
                        .font(.system(size: 28, weight: .semibold, design: .monospaced))
                        .tracking(6)
                        .foregroundStyle(theme.fg)
                        .tint(Color(red: 0.98, green: 0.78, blue: 0.13))
                        .frame(height: 56)
                        .padding(.horizontal, 18)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(theme.fg.opacity(0.06))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(theme.fg.opacity(fieldFocused ? 0.22 : 0.10), lineWidth: 1)
                                )
                        )
                        .padding(.top, 24)
                        .onChange(of: codeText) { _, newValue in
                            handleCodeChange(newValue)
                        }
                        .task {
                            // Brief settle so the field is in a window before
                            // it claims first responder.
                            try? await Task.sleep(for: .milliseconds(150))
                            fieldFocused = true
                        }

                    if isVerifying {
                        HStack(spacing: 6) {
                            ProgressView().tint(theme.fg).scaleEffect(0.7)
                            Text("Verifying…")
                                .font(.caption)
                                .foregroundStyle(theme.sub)
                        }
                        .padding(.top, 12)
                    }
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.top, 8)
                    }
                    if let resendConfirmation {
                        Text(resendConfirmation)
                            .font(.caption)
                            .foregroundStyle(theme.sub)
                            .padding(.top, 6)
                    }

                    Button { Task { await resendCode() } } label: {
                        Group {
                            if isResending {
                                HStack(spacing: 8) {
                                    ProgressView().tint(theme.fg.opacity(0.75)).scaleEffect(0.85)
                                    Text("Sending new code…")
                                }
                            } else if resendCountThisSession >= Config.OTP_RESEND_SESSION_MAX {
                                Text("Too many attempts. Try again later.")
                            } else if resendCooldownRemaining > 0 {
                                Text("Resend code in \(formattedCountdown(resendCooldownRemaining))")
                                    .monospacedDigit()
                            } else {
                                Text("Didn't receive a code? Resend")
                            }
                        }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(theme.fg.opacity(
                            resendCountThisSession >= Config.OTP_RESEND_SESSION_MAX
                            || resendCooldownRemaining > 0
                            || isResending ? 0.35 : 0.65
                        ))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 20)
                    }
                    .buttonStyle(.plain)
                    .disabled(
                        isResending
                        || resendCooldownRemaining > 0
                        || appState.phoneNumber.isEmpty
                        || resendCountThisSession >= Config.OTP_RESEND_SESSION_MAX
                    )

                    Spacer(minLength: 0)
                }
            }
        } footer: {
            EmptyView()
        }
    }

    /// Filters to digits, caps at 6, and schedules a debounced auto-submit
    /// once the code is complete. Runs for both manual typing and SMS
    /// autofill (SwiftUI pushes autofilled text through the binding).
    private func handleCodeChange(_ newValue: String) {
        let digits = String(newValue.filter(\.isNumber).prefix(6))
        if digits != codeText {
            codeText = digits
            return
        }

        autoSubmitWork?.cancel()
        guard digits.count == 6, !isVerifying else { return }
        let work = DispatchWorkItem { verifyCode() }
        autoSubmitWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func verifyCode() {
        guard codeText.count == 6, !isVerifying else { return }
        errorMessage = nil
        isVerifying = true

        Task {
            let success = await appState.verifyCode(codeText)
            isVerifying = false
            if success {
                onVerified()
            } else {
                errorMessage = appState.registrationError ?? "Invalid code. Please try again."
                codeText = ""
            }
        }
    }

    private func resendCode() async {
        guard !isResending,
              resendCooldownRemaining == 0,
              resendCountThisSession < Config.OTP_RESEND_SESSION_MAX else { return }
        let phone = appState.phoneNumber
        guard !phone.isEmpty else { return }

        await MainActor.run {
            isResending = true
            errorMessage = nil
            resendConfirmation = nil
        }

        let success = await appState.sendCode(phoneNumber: phone)

        await MainActor.run {
            isResending = false
            if success {
                codeText = ""
                resendCountThisSession += 1
                let cooldown = Config.otpResendCooldown(forAttempt: resendCountThisSession)
                resendConfirmation = "We sent a new code."
                resendCooldownRemaining = cooldown
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(4))
                    if resendConfirmation == "We sent a new code." { resendConfirmation = nil }
                }
                Task { @MainActor in
                    while resendCooldownRemaining > 0 {
                        try? await Task.sleep(for: .seconds(1))
                        resendCooldownRemaining -= 1
                    }
                }
            } else {
                errorMessage = appState.registrationError ?? "Could not resend. Try again later."
            }
        }
    }

    /// Render a countdown like "0:42" (mm:ss). Keeps the resend label
    /// visually stable as the timer ticks, since fixed-width digits +
    /// colon don't shift the surrounding text.
    private func formattedCountdown(_ seconds: Int) -> String {
        let s = max(0, seconds)
        if s < 60 { return "\(s)s" }
        let m = s / 60
        let r = s % 60
        return String(format: "%d:%02d", m, r)
    }
}
