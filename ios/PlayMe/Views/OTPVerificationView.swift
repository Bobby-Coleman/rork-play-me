import SwiftUI
import UIKit

// MARK: - UIViewRepresentable OTP TextField

struct OTPTextField: UIViewRepresentable {
    @Binding var text: String
    var onSixDigits: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSixDigits: onSixDigits)
    }

    func makeUIView(context: Context) -> UITextField {
        let tf = UITextField()
        tf.keyboardType = .numberPad
        tf.textContentType = .oneTimeCode
        tf.textColor = .clear
        tf.tintColor = .clear
        tf.font = .systemFont(ofSize: 24)
        tf.delegate = context.coordinator
        tf.addTarget(context.coordinator, action: #selector(Coordinator.textChanged(_:)), for: .editingChanged)
        // Request focus exactly once, when the view is first mounted. Doing this
        // from `updateUIView` caused focus thrash on SwiftUI re-renders that ate
        // incoming autofill insertions.
        DispatchQueue.main.async {
            guard !tf.becomeFirstResponder() else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                _ = tf.becomeFirstResponder()
            }
        }
        return tf
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        // Never let a transient empty binding wipe an autofilled 6-digit code
        // that the system just delivered — `textChanged` will publish the new
        // value on the next runloop.
        if uiView.text != text {
            let current = uiView.text ?? ""
            if text.isEmpty && current.count == 6 { return }
            uiView.text = text
        }
    }

    class Coordinator: NSObject, UITextFieldDelegate {
        @Binding var text: String
        let onSixDigits: () -> Void
        /// Guards against `textChanged` firing onSixDigits multiple times for
        /// the same autofilled code (e.g. if SwiftUI re-invokes the binding).
        private var hasCompleted = false

        init(text: Binding<String>, onSixDigits: @escaping () -> Void) {
            _text = text
            self.onSixDigits = onSixDigits
        }

        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            // Allow the native insert so iOS SMS autofill (QuickType "From Messages")
            // commits cleanly. Deletions pass through; hardware-keyboard non-digits are rejected.
            // `textChanged` is the single source of truth for filtering + binding updates.
            if string.isEmpty { return true }
            return string.allSatisfy { $0.isNumber }
        }

        @objc func textChanged(_ textField: UITextField) {
            let filtered = String((textField.text ?? "").filter { $0.isNumber }.prefix(6))
            if textField.text != filtered {
                textField.text = filtered
            }
            text = filtered
            if filtered.count < 6 {
                hasCompleted = false
            } else if !hasCompleted {
                hasCompleted = true
                DispatchQueue.main.async { self.onSixDigits() }
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
    @State private var isVerifying = false
    @State private var errorMessage: String?
    @State private var fieldIsFocused = false
    @State private var isResending = false
    @State private var resendCooldownRemaining = 0
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

                ZStack {
                    HStack(spacing: 10) {
                        ForEach(0..<6, id: \.self) { index in
                            let characters = Array(codeText)
                            let digit = index < characters.count ? String(characters[index]) : ""
                            let isCurrent = index == codeText.count && fieldIsFocused

                            Text(digit)
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 52)
                                .background(Color.white.opacity(isCurrent ? 0.15 : 0.08))
                                .clipShape(.rect(cornerRadius: 10))
                        }
                    }
                    .allowsHitTesting(false)

                    OTPTextField(text: $codeText) {
                        verifyCode()
                    }
                    .frame(height: 52)
                    .onAppear { fieldIsFocused = true }
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
                        } else if resendCooldownRemaining > 0 {
                            Text("Resend code in \(resendCooldownRemaining)s")
                        } else {
                            Text("Didn't receive a code?")
                        }
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(resendCooldownRemaining > 0 || isResending ? 0.35 : 0.65))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 20)
                }
                .buttonStyle(.plain)
                .disabled(isResending || resendCooldownRemaining > 0 || appState.phoneNumber.isEmpty)

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
