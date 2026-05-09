import SwiftUI

/// Screen 5 — Onboarding intro flourish.
///
/// Brief landing between identity and personalization steps.
struct RiffIntroView: View {
    let stepIdx: Int
    let totalSteps: Int
    let onContinue: () -> Void
    let onBack: (() -> Void)?

    var body: some View {
        RiffScreenChrome(stepIdx: stepIdx, totalSteps: totalSteps, onBack: onBack) {
            VStack(alignment: .leading, spacing: 16) {
                Spacer()
                RiffStagger(delay: 0.06) {
                    RiffHeadline(text: "Now, a few questions about you.", size: 36)
                }
                RiffStagger(delay: 0.18) {
                    RiffSubhead(text: "This is how we craft your experience.")
                }
                Spacer()
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } footer: {
            RiffStagger(delay: 0.42) {
                RiffPrimaryButton(title: "Continue", action: onContinue)
            }
        }
    }
}
