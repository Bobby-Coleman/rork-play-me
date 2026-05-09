import SwiftUI

/// Screen 6 — First name.
///
/// Replaces the legacy `NameEntryView` (last-name field is dropped per
/// the Claude design — the app only ever surfaces first name in feeds,
/// shares, and DMs).
struct FirstNameView: View {
    @Binding var firstName: String
    let stepIdx: Int
    let totalSteps: Int
    let onContinue: () -> Void
    let onBack: (() -> Void)?

    private var canContinue: Bool {
        !firstName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        RiffScreenChrome(stepIdx: stepIdx, totalSteps: totalSteps, onBack: onBack) {
            RiffStagger(delay: 0.06) {
                RiffHeadline(text: "What should we call you?")
            }
            RiffStagger(delay: 0.20) {
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
                .padding(.top, 32)
            }
            Spacer(minLength: 0)
        } footer: {
            RiffStagger(delay: 0.42) {
                RiffPrimaryButton(
                    title: "Continue",
                    disabled: !canContinue,
                    action: onContinue
                )
            }
        }
        .appKeyboardDismiss()
    }
}
