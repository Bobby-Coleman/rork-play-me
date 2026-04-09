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
        return tf
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
    }

    class Coordinator: NSObject, UITextFieldDelegate {
        @Binding var text: String
        let onSixDigits: () -> Void

        init(text: Binding<String>, onSixDigits: @escaping () -> Void) {
            _text = text
            self.onSixDigits = onSixDigits
        }

        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            let current = textField.text ?? ""
            guard let swiftRange = Range(range, in: current) else { return false }
            let proposed = current.replacingCharacters(in: swiftRange, with: string)
            let filtered = String(proposed.filter { $0.isNumber }.prefix(6))
            textField.text = filtered
            text = filtered
            if filtered.count == 6 {
                DispatchQueue.main.async { self.onSixDigits() }
            }
            return false
        }

        @objc func textChanged(_ textField: UITextField) {
            let filtered = String((textField.text ?? "").filter { $0.isNumber }.prefix(6))
            if textField.text != filtered {
                textField.text = filtered
            }
            text = filtered
            if filtered.count == 6 {
                DispatchQueue.main.async { self.onSixDigits() }
            }
        }
    }
}

// MARK: - OTP Verification View

struct OTPVerificationView: View {
    let appState: AppState
    let onVerified: () -> Void

    @State private var codeText: String = ""
    @State private var isVerifying = false
    @State private var errorMessage: String?
    @State private var fieldIsFocused = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

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
}
