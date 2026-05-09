import SwiftUI

/// Screen 4 — OTP verify.
///
/// Restyled chrome around the existing UIKit `OTPTextField` so iOS SMS
/// autofill ("From Messages" QuickType candidate) keeps working — the
/// autofill timing is fragile and is preserved verbatim from
/// `OTPVerificationView` rather than rewritten in pure SwiftUI.
struct OTPVerifyView: View {
    let appState: AppState
    let onVerified: () -> Void
    let onBack: (() -> Void)?

    @State private var codeText: String = ""
    @State private var isVerifying = false
    @State private var errorMessage: String?
    @State private var fieldIsFocused = false
    @State private var isResending = false
    @State private var resendCooldownRemaining = 0
    @State private var resendConfirmation: String?

    @Environment(\.riffTheme) private var theme

    var body: some View {
        RiffScreenChrome(onBack: onBack, showProgressDots: false) {
            RiffStagger(delay: 0.06) {
                RiffHeadline(text: "Enter the code")
            }
            RiffStagger(delay: 0.14) {
                RiffSubhead(text: "We sent a 6-digit code to your phone.")
                    .padding(.top, 8)
            }

            RiffStagger(delay: 0.24) {
                ZStack {
                    HStack(spacing: 10) {
                        ForEach(0..<6, id: \.self) { index in
                            let chars = Array(codeText)
                            let digit = index < chars.count ? String(chars[index]) : ""
                            let isCurrent = index == codeText.count && fieldIsFocused
                            Text(digit)
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(theme.fg)
                                .frame(width: 44, height: 52)
                                .background(theme.fg.opacity(isCurrent ? 0.15 : 0.08))
                                .clipShape(.rect(cornerRadius: 10))
                        }
                    }
                    .allowsHitTesting(false)

                    OTPTextField(text: $codeText) { verifyCode() }
                        .frame(height: 52)
                        .task {
                            try? await Task.sleep(for: .milliseconds(250))
                            fieldIsFocused = true
                        }
                }
                .padding(.top, 32)
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
                    } else if resendCooldownRemaining > 0 {
                        Text("Resend code in \(resendCooldownRemaining)s")
                    } else {
                        Text("Didn't receive a code?")
                    }
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(theme.fg.opacity(resendCooldownRemaining > 0 || isResending ? 0.35 : 0.65))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 20)
            }
            .buttonStyle(.plain)
            .disabled(isResending || resendCooldownRemaining > 0 || appState.phoneNumber.isEmpty)

            Spacer(minLength: 0)
        } footer: {
            EmptyView()
        }
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
        guard !isResending, resendCooldownRemaining == 0 else { return }
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
                resendConfirmation = "We sent a new code."
                resendCooldownRemaining = 60
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
}
