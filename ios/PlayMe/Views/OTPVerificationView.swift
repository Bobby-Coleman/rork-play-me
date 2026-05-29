import SwiftUI
import UIKit

// MARK: - UIViewRepresentable OTP TextField

// Intentional exception to the app-wide `AppTextField` rule: OTP entry
// needs a UIKit `UITextField` for one-time-code autofill and precise digit
// filtering without SwiftUI focus churn.

struct OTPTextField: UIViewRepresentable {
    @Binding var text: String
    /// When true, the field claims first responder once it is in a window.
    /// Driven explicitly by the parent instead of an internal timer so focus
    /// is deterministic across slow/fast devices (the old fixed 250ms delay
    /// raced the SMS QuickType handoff differently per device).
    var shouldFocus: Bool = true
    /// Parent bumps this to deterministically clear the field (e.g. after a
    /// failed verify). We never clear based on the binding going empty, which
    /// previously raced the autofill -> re-render gap and wiped the code.
    var resetToken: Int = 0
    var onSixDigits: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSixDigits: onSixDigits)
    }

    func makeUIView(context: Context) -> UITextField {
        let tf = UITextField()
        tf.keyboardType = .numberPad
        tf.textContentType = .oneTimeCode
        // Visible field: a single, real text field is the most reliable target
        // for the QuickType "From Messages" autofill candidate (an invisible
        // overlay field was the source of the "code disappears on tap" flake).
        tf.textColor = .white
        tf.tintColor = UIColor(red: 0.98, green: 0.78, blue: 0.13, alpha: 1)
        tf.font = .monospacedDigitSystemFont(ofSize: 28, weight: .semibold)
        tf.defaultTextAttributes[.kern] = 6
        tf.textAlignment = .left
        tf.delegate = context.coordinator
        // `editingChanged` is the single source of truth for input, including
        // QuickType "From Messages" autofill (which inserts all 6 digits at
        // once). We let UIKit own the buffer and only observe it here.
        tf.addTarget(context.coordinator, action: #selector(Coordinator.textChanged(_:)), for: .editingChanged)
        return tf
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        // Deterministic focus: claim first responder exactly once, only after
        // the field is actually in a window. No arbitrary delay to race the
        // autofill candidate.
        if shouldFocus, !context.coordinator.didFocus, uiView.window != nil {
            context.coordinator.didFocus = true
            uiView.becomeFirstResponder()
        }

        // Explicit, intentional clear only. The parent bumps `resetToken` after
        // a failed verify; we never clear based on the binding being empty,
        // because autofill inserts via `shouldChangeCharactersIn` WITHOUT firing
        // `editingChanged`, leaving a window where the field holds the code but
        // the binding is still "". A re-render in that window (e.g. the resend
        // countdown tick) used to wipe the freshly autofilled code.
        if context.coordinator.lastResetToken != resetToken {
            context.coordinator.lastResetToken = resetToken
            uiView.text = ""
            context.coordinator.resetCompletion()
            return
        }
    }

    class Coordinator: NSObject, UITextFieldDelegate {
        @Binding var text: String
        let onSixDigits: () -> Void
        /// Ensures we only call `becomeFirstResponder` once.
        var didFocus = false
        /// Mirrors the parent's `resetToken` so we clear exactly once per bump.
        var lastResetToken = 0
        /// Guards against firing `onSixDigits` more than once for the same code.
        private var hasCompleted = false
        /// Debounce token so a re-tapped QuickType candidate (iOS 17+ "first
        /// tap fails" bug) doesn't double-submit, and the user sees the filled
        /// code briefly before we auto-submit.
        private var submitWorkItem: DispatchWorkItem?

        init(text: Binding<String>, onSixDigits: @escaping () -> Void) {
            _text = text
            self.onSixDigits = onSixDigits
        }

        /// Re-arms the completion guard after an external clear so a fresh code
        /// (manual or re-autofilled) can submit again.
        func resetCompletion() {
            submitWorkItem?.cancel()
            hasCompleted = false
        }

        // `shouldChangeCharactersIn` is the SOURCE OF TRUTH for input. It fires
        // for both manual typing and QuickType "From Messages" autofill (which
        // `editingChanged` does NOT reliably do on recent iOS). We compute the
        // new value, apply it ourselves, and return false so the system doesn't
        // double-apply. Because we set `.text` programmatically, `editingChanged`
        // won't re-enter — making this the single, reliable path.
        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            let current = textField.text ?? ""
            guard let r = Range(range, in: current) else { return false }
            let filtered = String(current.replacingCharacters(in: r, with: string).filter { $0.isNumber }.prefix(6))
            textField.text = filtered
            sync(filtered)
            return false
        }

        // Safety net for any input path that bypasses the delegate (idempotent).
        @objc func textChanged(_ textField: UITextField) {
            let filtered = String((textField.text ?? "").filter { $0.isNumber }.prefix(6))
            if textField.text != filtered { textField.text = filtered }
            sync(filtered)
        }

        /// Pushes the filtered value to the binding and schedules the debounced
        /// auto-submit once 6 digits are present.
        private func sync(_ filtered: String) {
            if text != filtered { text = filtered }

            submitWorkItem?.cancel()
            if filtered.count < 6 {
                hasCompleted = false
            } else if !hasCompleted {
                hasCompleted = true
                // ~200ms debounce: lets the user see the completed code and
                // absorbs the iOS 17+ re-tap quirk before we verify.
                let work = DispatchWorkItem { [weak self] in self?.onSixDigits() }
                submitWorkItem = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
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
    @State private var fieldIsFocused = false
    @State private var isResending = false
    @State private var resendCooldownRemaining = 0
    @State private var resendCountThisSession = 0
    @State private var resendConfirmation: String?

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

                OTPTextField(text: $codeText, shouldFocus: fieldIsFocused, resetToken: otpResetToken) {
                    verifyCode()
                }
                .frame(height: 56)
                .padding(.horizontal, 18)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.white.opacity(fieldIsFocused ? 0.22 : 0.10), lineWidth: 1)
                        )
                )
                .task {
                    // Brief settle so the field is in a window before it
                    // claims first responder; the actual becomeFirstResponder
                    // is gated on window presence inside OTPTextField.
                    try? await Task.sleep(for: .milliseconds(150))
                    fieldIsFocused = true
                }

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
