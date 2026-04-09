import SwiftUI

struct OTPVerificationView: View {
    let appState: AppState
    let onVerified: () -> Void

    @State private var codeText: String = ""
    @State private var isVerifying = false
    @State private var errorMessage: String?
    @FocusState private var isCodeFieldFocused: Bool

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
                    TextField("", text: $codeText)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .focused($isCodeFieldFocused)
                        .opacity(0)
                        .frame(width: 1, height: 1)
                        .onChange(of: codeText) { _, newValue in
                            let filtered = String(newValue.filter { $0.isNumber }.prefix(6))
                            if filtered != newValue {
                                codeText = filtered
                            }
                            if filtered.count == 6 {
                                verifyCode()
                            }
                        }

                    HStack(spacing: 10) {
                        ForEach(0..<6, id: \.self) { index in
                            let characters = Array(codeText)
                            let digit = index < characters.count ? String(characters[index]) : ""
                            let isCurrent = index == codeText.count && isCodeFieldFocused

                            Text(digit)
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 52)
                                .background(Color.white.opacity(isCurrent ? 0.15 : 0.08))
                                .clipShape(.rect(cornerRadius: 10))
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        isCodeFieldFocused = true
                    }
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
        .onAppear { isCodeFieldFocused = true }
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
                isCodeFieldFocused = true
            }
        }
    }
}
