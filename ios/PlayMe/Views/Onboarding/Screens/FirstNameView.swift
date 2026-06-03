import SwiftUI

/// Screen 6 — Name.
struct FirstNameView: View {
    @Binding var firstName: String
    @Binding var lastName: String
    let stepIdx: Int
    let totalSteps: Int
    let onContinue: () -> Void
    let onBack: (() -> Void)?

    private var canContinue: Bool {
        !firstName.trimmingCharacters(in: .whitespaces).isEmpty
            && !lastName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        RiffScreenChrome(stepIdx: stepIdx, totalSteps: totalSteps, onBack: onBack) {
            OnboardingUpperFormSlot {
                VStack(alignment: .leading, spacing: 0) {
                    RiffHeadline(text: "You're in. Now, what should we call you?")

                    RiffFieldInput(
                        text: $firstName,
                        placeholder: "First name",
                        contentType: .givenName,
                        capitalization: .words,
                        autocorrection: false,
                        maxLength: 24,
                        autoFocus: true,
                        onSubmit: {
                            if canContinue { onContinue() }
                        }
                    )
                    .padding(.top, 24)

                    RiffFieldInput(
                        text: $lastName,
                        placeholder: "Last name",
                        contentType: .familyName,
                        capitalization: .words,
                        autocorrection: false,
                        maxLength: 32,
                        onSubmit: {
                            if canContinue { onContinue() }
                        }
                    )
                    .padding(.top, 18)

                    Spacer(minLength: 0)
                }
            }
        } footer: {
            RiffPrimaryButton(
                title: "Continue",
                disabled: !canContinue,
                action: onContinue
            )
        }
        .appKeyboardDismiss()
    }
}
