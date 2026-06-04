import SwiftUI
import UIKit

// MARK: - Native one-time-code field

/// Native `UITextField` wrapper for SMS one-time-code entry.
///
/// UIKit is the most reliable target for iOS "From Messages" autofill:
/// - SwiftUI's `TextField` can silently drop the autofilled value on iOS 17+
///   (the tap on the suggestion doesn't reach the binding).
/// - Our earlier UIKit version *blocked* autofill by returning `false` from
///   `shouldChangeCharactersIn`, which cancels the system's insertion.
///
/// This version never blocks input. It lets the system insert the code and
/// reads the result via the `.editingChanged` control event, which fires for
/// both manual typing and autofill. Clearing is done explicitly through
/// `resetToken` so a re-render never wipes a freshly autofilled code.
struct OTPCodeField: UIViewRepresentable {
    @Binding var text: String
    var maxDigits: Int = 6
    /// Bump to clear the field (e.g. after a failed verify / on resend).
    var resetToken: Int = 0
    var textColor: UIColor = .white
    var onComplete: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextField {
        let tf = UITextField()
        tf.keyboardType = .numberPad
        tf.textContentType = .oneTimeCode
        tf.textColor = textColor
        tf.tintColor = UIColor(red: 0.80, green: 0.69, blue: 0.96, alpha: 1)
        tf.font = .monospacedDigitSystemFont(ofSize: 28, weight: .semibold)
        tf.defaultTextAttributes[.kern] = 6
        tf.textAlignment = .left
        // No `shouldChangeCharactersIn` override — the system is free to insert
        // the autofilled code. We observe the result here.
        tf.addTarget(context.coordinator,
                     action: #selector(Coordinator.editingChanged(_:)),
                     for: .editingChanged)
        return tf
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        context.coordinator.parent = self

        // Explicit clear only, gated on the reset token. We never clear off the
        // binding going empty, which previously raced the autofill -> binding
        // sync and wiped freshly filled codes.
        if context.coordinator.lastResetToken != resetToken {
            context.coordinator.lastResetToken = resetToken
            uiView.text = ""
            context.coordinator.didComplete = false
        }

        // Claim first responder once, after the field is in a window, so the
        // autofill candidate attaches to a focused, empty field.
        if !context.coordinator.didFocus, uiView.window != nil {
            context.coordinator.didFocus = true
            uiView.becomeFirstResponder()
        }
    }

    final class Coordinator: NSObject {
        var parent: OTPCodeField
        var didFocus = false
        var didComplete = false
        var lastResetToken = 0

        init(_ parent: OTPCodeField) { self.parent = parent }

        @objc func editingChanged(_ tf: UITextField) {
            let digits = String((tf.text ?? "").filter { $0.isNumber }.prefix(parent.maxDigits))
            if tf.text != digits { tf.text = digits }
            if parent.text != digits { parent.text = digits }

            if digits.count >= parent.maxDigits {
                if !didComplete {
                    didComplete = true
                    parent.onComplete()
                }
            } else {
                didComplete = false
            }
        }
    }
}

// MARK: - OTP Verification View

struct OTPVerificationView: View {
    let appState: AppState
    let onVerified: () -> Void
    var onBack: (() -> Void)? = nil

    @State private var codeText: String = ""
    @State private var otpResetToken = 0
    @State private var isVerifying = false
    @State private var errorMessage: String?
    @State private var isResending = false
    @State private var resendCooldownRemaining = 0
    @State private var resendCountThisSession = 0
    @State private var resendConfirmation: String?
    @State private var autoSubmitWork: DispatchWorkItem?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let onBack {
                VStack {
                    HStack {
                        Button(action: onBack) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 40, height: 40)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    .padding(.leading, 12)
                    .padding(.top, 8)
                    Spacer()
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                Spacer()

                Text("Enter the code")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.bottom, 8)

                Text("We sent a 6-digit code to your phone")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.bottom, 32)

                OTPCodeField(text: $codeText, resetToken: otpResetToken) {
                    handleComplete()
                }
                .frame(height: 56)
                .padding(.horizontal, 18)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.white.opacity(0.18), lineWidth: 1)
                        )
                )

                if isVerifying {
                    HStack(spacing: 6) {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.7)
                        Text("Verifying...")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
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
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(.top, 6)
                }

                Button {
                    Task { await resendCode() }
                } label: {
                    Group {
                        if isResending {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .tint(.white.opacity(0.75))
                                    .scaleEffect(0.85)
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
                    .foregroundStyle(.white.opacity(
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

                Spacer()
                Spacer()
            }
            .padding(.horizontal, 24)
        }
    }

    /// Called by `OTPCodeField` once six digits are present. Debounced ~250ms
    /// so the user sees the filled code before we verify.
    private func handleComplete() {
        autoSubmitWork?.cancel()
        guard codeText.count == 6, !isVerifying else { return }
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
                otpResetToken += 1
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
                otpResetToken += 1
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

    /// Render a countdown like "0:42" (mm:ss) so the resend label stays
    /// visually stable as the timer ticks instead of jittering between
    /// 1-, 2-, and 3-digit widths.
    private func formattedCountdown(_ seconds: Int) -> String {
        let s = max(0, seconds)
        if s < 60 { return "\(s)s" }
        let m = s / 60
        let r = s % 60
        return String(format: "%d:%02d", m, r)
    }
}
