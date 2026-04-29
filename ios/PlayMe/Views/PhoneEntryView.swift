import SwiftUI

struct PhoneEntryView: View {
    @Binding var phoneNumber: String
    let appState: AppState
    let onCodeSent: () -> Void

    @State private var isSending = false
    @State private var errorMessage: String?
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            BlobShape()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.06), Color.clear],
                        center: .center,
                        startRadius: 20,
                        endRadius: 200
                    )
                )
                .frame(width: 350, height: 350)
                .offset(y: -120)

            VStack(alignment: .leading, spacing: 0) {
                Spacer()

                Text("What's your\nphone number?")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.bottom, 24)

                HStack(spacing: 12) {
                    AppTextField("(555) 000-0000", text: $phoneNumber)
                        .font(.system(size: 18))
                        .foregroundStyle(.white)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                        .focused($isFocused)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(Color.white.opacity(0.1))
                        .clipShape(.rect(cornerRadius: 12))

                    Button(action: sendCode) {
                        ZStack {
                            if isSending {
                                ProgressView()
                                    .tint(.black)
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundStyle(.black)
                            }
                        }
                        .frame(width: 48, height: 48)
                        .background(.white)
                        .clipShape(Circle())
                    }
                    .disabled(phoneNumber.count < 7 || isSending)
                    .opacity(phoneNumber.count < 7 ? 0.4 : 1)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.top, 8)
                }

                Text("We'll send you a verification code via SMS")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.top, 12)

                Spacer()
                Spacer()
            }
            .padding(.horizontal, 24)
        }
        .appKeyboardDismiss()
        .onAppear { isFocused = true }
    }

    private func sendCode() {
        errorMessage = nil
        isSending = true

        var formatted = phoneNumber
        if !formatted.hasPrefix("+") {
            formatted = "+1\(formatted.filter { $0.isNumber })"
        }

        Task {
            let success = await appState.sendCode(phoneNumber: formatted)
            isSending = false
            if success {
                onCodeSent()
            } else {
                errorMessage = appState.registrationError ?? "Failed to send code. Check your number."
            }
        }
    }
}
