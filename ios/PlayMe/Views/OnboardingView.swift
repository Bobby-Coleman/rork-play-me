import SwiftUI

struct OnboardingView: View {
    let appState: AppState
    let onComplete: () -> Void

    @State private var step: Int = 0
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
                UsernamePickerView(username: $username, appState: appState) {
                    Task {
                        let success = await appState.register(username: username)
                        if success {
                            withAnimation(.easeInOut(duration: 0.4)) { step = 2 }
                        }
                    }
                }
            case 2:
                WidgetInstructionsView { onComplete() }
            default:
                EmptyView()
            }
        }
        .transition(.opacity)
    }
}
