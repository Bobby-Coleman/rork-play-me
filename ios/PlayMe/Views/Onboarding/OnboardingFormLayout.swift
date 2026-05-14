import SwiftUI

/// Shared vertical anchor for headline + field clusters on auth/profile steps
/// so transitions do not jump between invite (phase B), phone, OTP, first name, and username.
enum OnboardingFormLayout {
    /// Portion of the **content** area (above footer) used as top inset before the form stack.
    static let upperBandFraction: CGFloat = 0.22
    static let upperBandMinimum: CGFloat = 48

    /// Headline block reserved height on username step so the `@` field lines up with other screens.
    static let usernameHeadlineBlockMinHeight: CGFloat = 120
}

/// Places `content` below a top band computed from available height (GeometryReader).
struct OnboardingUpperFormSlot<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        GeometryReader { geo in
            let top = max(
                OnboardingFormLayout.upperBandMinimum,
                geo.size.height * OnboardingFormLayout.upperBandFraction
            )
            VStack(alignment: .leading, spacing: 0) {
                Spacer()
                    .frame(height: top)
                content()
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}
