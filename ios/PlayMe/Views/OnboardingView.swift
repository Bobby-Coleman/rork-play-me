import SwiftUI

struct OnboardingView: View {
    let appState: AppState
    let onComplete: () -> Void

    @State private var step: Int = 0
    @State private var phoneNumber: String = ""
    @State private var username: String = ""

    var body: some View {
        Group {
            switch step {
            case 0:
                SplashView { service in
                    appState.preferredMusicService = service
                    withAnimation(.easeInOut(duration: 0.4)) { step = 1 }
                }
            case 1:
                PhoneEntryView(phoneNumber: $phoneNumber, appState: appState) {
                    withAnimation(.easeInOut(duration: 0.4)) { step = 2 }
                }
            case 2:
                OTPVerificationView(appState: appState) {
                    Task {
                        if await appState.checkForExistingUser() {
                            onComplete()
                        } else {
                            withAnimation(.easeInOut(duration: 0.4)) { step = 3 }
                        }
                    }
                }
            case 3:
                UsernamePickerView(username: $username, appState: appState) {
                    Task {
                        let success = await appState.register(username: username)
                        if success {
                            withAnimation(.easeInOut(duration: 0.4)) { step = 4 }
                        }
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
