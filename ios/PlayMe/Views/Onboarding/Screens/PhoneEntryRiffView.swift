import SwiftUI

/// Phone-only step: sends SMS verification, then advances to OTP.
struct PhoneEntryRiffView: View {
    let appState: AppState
    let onCodeSent: () -> Void
    let onBack: (() -> Void)?

    @State private var phone: String = ""
    @State private var isSending = false
    @State private var errorMessage: String?

    private var canSubmit: Bool {
        let digits = phone.filter(\.isNumber)
        return !isSending && digits.count >= 7
    }

    var body: some View {
        RiffScreenChrome(
            onBack: onBack,
            showProgressDots: false
        ) {
            OnboardingUpperFormSlot {
                VStack(alignment: .leading, spacing: 0) {
                    RiffHeadline(text: "What's your number?")
                    RiffSubhead(text: "We'll text you a code to verify it's you.")
                        .padding(.top, 12)

                    VStack(alignment: .leading, spacing: 8) {
                        RiffLabel(text: "Phone number")
                        RiffFieldInput(
                            text: $phone,
                            placeholder: "(555) 555-0142",
                            prefix: "🇺🇸 +1",
                            keyboard: .phonePad,
                            contentType: .telephoneNumber,
                            autocorrection: false,
                            onSubmit: {
                                if canSubmit { submit() }
                            }
                        )
                    }
                    .padding(.top, 24)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 12))
                            .foregroundStyle(.red)
                            .padding(.top, 12)
                    }

                    Spacer(minLength: 0)
                }
            }
        } footer: {
            RiffPrimaryButton(
                title: isSending ? "Sending…" : "Send code",
                disabled: !canSubmit,
                action: submit
            )
        }
        .appKeyboardDismiss()
    }

    private func submit() {
        guard canSubmit else { return }
        errorMessage = nil
        isSending = true

        var formattedPhone = phone
        if !formattedPhone.hasPrefix("+") {
            formattedPhone = "+1\(formattedPhone.filter(\.isNumber))"
        }

        Task {
            let success = await appState.sendCode(phoneNumber: formattedPhone)
            isSending = false
            if success {
                onCodeSent()
            } else {
                errorMessage = appState.registrationError ?? "Could not send code. Check your number."
            }
        }
    }
}
