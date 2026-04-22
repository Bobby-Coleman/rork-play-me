import SwiftUI

struct OnboardingView: View {
    let appState: AppState
    let onComplete: () -> Void

    @State private var step: Int = 0
    @State private var phoneNumber: String = ""
    @State private var firstName: String = ""
    @State private var lastName: String = ""
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
                OTPVerificationView(
                    appState: appState,
                    onVerified: {
                        Task {
                            if await appState.checkForExistingUser() {
                                onComplete()
                            } else {
                                withAnimation(.easeInOut(duration: 0.4)) { step = 3 }
                            }
                        }
                    },
                    onBack: {
                        withAnimation(.easeInOut(duration: 0.4)) { step = 1 }
                    }
                )
            case 3:
                NameEntryView(
                    firstName: $firstName,
                    lastName: $lastName,
                    onComplete: {
                        withAnimation(.easeInOut(duration: 0.4)) { step = 4 }
                    },
                    onBack: {
                        withAnimation(.easeInOut(duration: 0.4)) { step = 2 }
                    }
                )
            case 4:
                UsernamePickerView(username: $username, appState: appState) {
                    Task {
                        let success = await appState.register(
                            username: username,
                            firstName: firstName.trimmingCharacters(in: .whitespaces),
                            lastName: lastName.trimmingCharacters(in: .whitespaces)
                        )
                        if success {
                            withAnimation(.easeInOut(duration: 0.4)) { step = 5 }
                        }
                    }
                }
            case 5:
                OnboardingInviteView(appState: appState, username: username.lowercased()) {
                    withAnimation(.easeInOut(duration: 0.4)) { step = 6 }
                }
            case 6:
                SendFirstSongView(
                    appState: appState,
                    onContinue: {
                        withAnimation(.easeInOut(duration: 0.4)) { step = 7 }
                    },
                    onSkip: {
                        withAnimation(.easeInOut(duration: 0.4)) { step = 7 }
                    },
                    onReopenInvites: {
                        withAnimation(.easeInOut(duration: 0.4)) { step = 5 }
                    }
                )
            case 7:
                WidgetInstructionsView { onComplete() }
            default:
                EmptyView()
            }
        }
        .transition(.opacity)
    }
}
