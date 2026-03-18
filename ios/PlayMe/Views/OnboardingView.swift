import SwiftUI

struct OnboardingView: View {
    let appState: AppState
    let onComplete: () -> Void

    @State private var step: Int = 0
    @State private var phone: String = ""
    @State private var firstName: String = ""
    @State private var username: String = ""

    var body: some View {
        Group {
            switch step {
            case 0:
                SplashView { withAnimation(.easeInOut(duration: 0.4)) { step = 1 } }
            case 1:
                PhoneEntryView(phoneNumber: $phone) { withAnimation(.easeInOut(duration: 0.4)) { step = 2 } }
            case 2:
                OTPVerificationView { withAnimation(.easeInOut(duration: 0.4)) { step = 3 } }
            case 3:
                NameUsernameView(firstName: $firstName, username: $username, appState: appState) {
                    Task {
                        await appState.register(phone: phone, firstName: firstName, username: username)
                        withAnimation(.easeInOut(duration: 0.4)) { step = 4 }
                    }
                }
            case 4:
                WidgetInstructionsView { onComplete() }
            default:
                EmptyView()
            }
        }
        .transition(.opacity)
    }
}
