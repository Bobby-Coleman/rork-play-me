import SwiftUI
import Contacts

/// Step-driven coordinator for the new RIFF onboarding. Each step is a
/// case in `RiffOnboardingStep`; transitions use `RiffSlideContainer`
/// which mirrors the React `SlideTransition` (slide + spring + opacity).
///
/// State that needs to survive across transitions (firstName, username,
/// invite contacts, contacts auth status) lives here on the orchestrator
/// rather than each step screen.
enum RiffOnboardingStep: Int, CaseIterable {
    case coldOpen
    case socialProof
    case inviteCodeOnly
    case phoneEntry
    case otpVerify
    case intro
    case firstName
    case username
    case musicService
    case taste
    case theme
    case contactsPermission
    case inviteIntro
    case pickFriends
    case notifications
    case widget
    case sendFirstSong
}

struct OnboardingView: View {
    let appState: AppState
    let onComplete: () -> Void

    @State private var step: RiffOnboardingStep = .coldOpen
    @State private var lastStepIndex: Int = 0

    @State private var firstName: String = ""
    @State private var username: String = ""
    @State private var contacts: [SimpleContact] = []
    @State private var contactsStatus: CNAuthorizationStatus = CNContactStore.authorizationStatus(for: .contacts)

    private var isForward: Bool { step.rawValue >= lastStepIndex }

    /// Steps that participate in the progress dots. Excludes cold open,
    /// social proof, invite, phone, and OTP. `intro` remains an enum case but is not routed.
    private static let progressSteps: [RiffOnboardingStep] = [
        .firstName, .username, .musicService, .taste, .theme,
        .contactsPermission, .inviteIntro, .pickFriends, .notifications, .widget,
    ]

    private func progressIndex(for step: RiffOnboardingStep) -> Int? {
        Self.progressSteps.firstIndex(of: step)
    }

    private var totalProgress: Int { Self.progressSteps.count }

    var body: some View {
        ZStack {
            appState.appTheme.bg.ignoresSafeArea()

            currentStepView
                .id(step.rawValue)
                .transition(slideTransition)
        }
        .riffTheme(appState.appTheme)
        .preferredColorScheme(appState.appTheme.isLight ? .light : .dark)
        .animation(.riffSlide, value: step)
    }

    private var slideTransition: AnyTransition {
        AnyTransition.asymmetric(
            insertion: .move(edge: isForward ? .trailing : .leading)
                .combined(with: .opacity),
            removal: .move(edge: isForward ? .leading : .trailing)
                .combined(with: .opacity)
        )
    }

    @ViewBuilder
    private var currentStepView: some View {
        switch step {
        case .coldOpen:
            ColdOpenSplashView(
                onContinue: { advance(to: .inviteCodeOnly) },
                onSignIn: { advance(to: .inviteCodeOnly) }
            )

        // Disabled in default graph: re-enable by routing cold open through `.socialProof` first.
        case .socialProof:
            SocialProofView(
                stepIdx: 0,
                totalSteps: totalProgress,
                onContinue: { advance(to: .inviteCodeOnly) },
                onBack: { advance(to: .coldOpen, isBack: true) }
            )

        case .inviteCodeOnly:
            InviteCodeOnlyView(
                appState: appState,
                onValidated: { advance(to: .phoneEntry) },
                onBack: { advance(to: .coldOpen, isBack: true) }
            )

        case .phoneEntry:
            PhoneEntryRiffView(
                appState: appState,
                onCodeSent: { advance(to: .otpVerify) },
                onBack: { advance(to: .inviteCodeOnly, isBack: true) }
            )

        case .otpVerify:
            OTPVerifyView(
                appState: appState,
                onVerified: {
                    Task {
                        if await appState.checkForExistingUser() {
                            onComplete()
                        } else {
                            await MainActor.run { advance(to: .firstName) }
                        }
                    }
                },
                onBack: { advance(to: .phoneEntry, isBack: true) }
            )

        // Kept for potential reuse; not used in the default graph (OTP goes to firstName).
        case .intro:
            RiffIntroView(
                stepIdx: 0,
                totalSteps: totalProgress,
                onContinue: { advance(to: .firstName) },
                onBack: nil
            )

        case .firstName:
            FirstNameView(
                firstName: $firstName,
                stepIdx: progressIndex(for: .firstName) ?? 0,
                totalSteps: totalProgress,
                onContinue: { advance(to: .username) },
                onBack: { advance(to: .otpVerify, isBack: true) }
            )

        case .username:
            UsernameRiffView(
                appState: appState,
                firstName: firstName,
                username: $username,
                stepIdx: progressIndex(for: .username) ?? 0,
                totalSteps: totalProgress,
                onContinue: {
                    Task {
                        let ok = await appState.register(
                            username: username,
                            firstName: firstName.trimmingCharacters(in: .whitespaces)
                        )
                        if ok {
                            await MainActor.run { advance(to: .musicService) }
                        }
                    }
                },
                onBack: { advance(to: .firstName, isBack: true) }
            )

        case .musicService:
            MusicServiceView(
                appState: appState,
                stepIdx: progressIndex(for: .musicService) ?? 0,
                totalSteps: totalProgress,
                onContinue: { advance(to: .taste) },
                onBack: { advance(to: .username, isBack: true) }
            )

        case .taste:
            TasteView(
                appState: appState,
                stepIdx: progressIndex(for: .taste) ?? 0,
                totalSteps: totalProgress,
                onContinue: { advance(to: .theme) },
                onBack: { advance(to: .musicService, isBack: true) }
            )

        case .theme:
            ThemePickerView(
                appState: appState,
                stepIdx: progressIndex(for: .theme) ?? 0,
                totalSteps: totalProgress,
                onContinue: { advance(to: .contactsPermission) },
                onBack: { advance(to: .taste, isBack: true) }
            )

        case .contactsPermission:
            RiffContactsPermissionView(
                stepIdx: progressIndex(for: .contactsPermission) ?? 0,
                totalSteps: totalProgress,
                onContinue: { advance(to: .inviteIntro) },
                onBack: { advance(to: .theme, isBack: true) },
                contacts: $contacts,
                status: $contactsStatus
            )

        case .inviteIntro:
            RiffInviteIntroView(
                stepIdx: progressIndex(for: .inviteIntro) ?? 0,
                totalSteps: totalProgress,
                onContinue: { advance(to: .pickFriends) },
                onBack: { advance(to: .contactsPermission, isBack: true) }
            )

        case .pickFriends:
            PickFriendsView(
                appState: appState,
                stepIdx: progressIndex(for: .pickFriends) ?? 0,
                totalSteps: totalProgress,
                onContinue: { advance(to: .notifications) },
                onSkip: { advance(to: .notifications) },
                onBack: { advance(to: .inviteIntro, isBack: true) },
                contacts: $contacts
            )

        case .notifications:
            NotificationsPermissionView(
                appState: appState,
                stepIdx: progressIndex(for: .notifications) ?? 0,
                totalSteps: totalProgress,
                onContinue: { advance(to: .widget) },
                onBack: { advance(to: .pickFriends, isBack: true) }
            )

        case .widget:
            RiffWidgetView(
                stepIdx: progressIndex(for: .widget) ?? 0,
                totalSteps: totalProgress,
                onDone: { advance(to: .sendFirstSong) },
                onSkip: { advance(to: .sendFirstSong) },
                onBack: { advance(to: .notifications, isBack: true) }
            )

        case .sendFirstSong:
            SendFirstSongRiffView(
                appState: appState,
                stepIdx: 0,
                totalSteps: totalProgress,
                onContinue: { onComplete() },
                onSkip: { onComplete() },
                onReopenInvites: { advance(to: .pickFriends, isBack: true) },
                onBack: { advance(to: .widget, isBack: true) }
            )
        }
    }

    private func advance(to next: RiffOnboardingStep, isBack: Bool = false) {
        lastStepIndex = step.rawValue
        withAnimation(.riffSlide) {
            step = next
        }
    }
}
