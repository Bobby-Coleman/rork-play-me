import SwiftUI

/// Screen 7 — Username with the animated "Nice to meet you, {name}." headline.
///
/// Reuses `appState.checkUsername` for live availability checking with
/// the same 400ms debounce as the previous `UsernamePickerView`.
struct UsernameRiffView: View {
    let appState: AppState
    let firstName: String
    @Binding var username: String

    let stepIdx: Int
    let totalSteps: Int
    let onContinue: () -> Void
    let onBack: (() -> Void)?

    @State private var usernameAvailable: Bool? = nil
    @State private var checkingUsername = false
    @State private var usernameCheckFailed = false

    @Environment(\.riffTheme) private var theme

    private var canContinue: Bool {
        !username.isEmpty && usernameAvailable == true
    }

    var body: some View {
        RiffScreenChrome(stepIdx: stepIdx, totalSteps: totalSteps, onBack: onBack) {
            RiffStagger(delay: 0.06) {
                animatedGreeting
            }
            RiffStagger(delay: 0.76) {
                RiffSubhead(text: "Now choose a username.")
                    .padding(.top, 12)
            }
            RiffStagger(delay: 0.92) {
                RiffFieldInput(
                    text: $username,
                    placeholder: "username",
                    prefix: "@",
                    keyboard: .asciiCapable,
                    contentType: .username,
                    capitalization: .never,
                    autocorrection: false,
                    maxLength: 20,
                    autoFocus: true,
                    onChange: { v in
                        let cleaned = v.replacingOccurrences(of: " ", with: "").lowercased()
                        if cleaned != username { username = cleaned }
                        checkUsernameAvailability(cleaned)
                    },
                    onSubmit: {
                        if canContinue { onContinue() }
                    }
                )
                .padding(.top, 36)

                availabilityMeta
                    .padding(.top, 8)
            }
            Spacer(minLength: 0)
        } footer: {
            RiffStagger(delay: 0.52) {
                RiffPrimaryButton(
                    title: "Continue",
                    disabled: !canContinue,
                    action: onContinue
                )
            }
        }
        .appKeyboardDismiss()
    }

    private var animatedGreeting: some View {
        let displayName = firstName.isEmpty ? "you" : firstName
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            RiffHeadline(text: "Nice to meet you,")
            RiffStagger(delay: 0.42, fromOffsetY: 6, duration: 0.6) {
                Text("\(displayName).")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(theme.fg)
            }
        }
    }

    @ViewBuilder
    private var availabilityMeta: some View {
        if checkingUsername {
            HStack(spacing: 6) {
                ProgressView().tint(theme.fg).scaleEffect(0.7)
                Text("checking…")
                    .font(.caption)
                    .foregroundStyle(theme.sub)
            }
        } else if usernameCheckFailed && !username.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
                Text("Could not verify — check connection")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        } else if let available = usernameAvailable, !username.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: available ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(available ? .green : .red)
                    .font(.caption)
                Text(available ? "available" : "taken")
                    .font(.caption)
                    .foregroundStyle(available ? .green : .red)
            }
        }
    }

    private func checkUsernameAvailability(_ value: String) {
        guard !value.isEmpty else {
            usernameAvailable = nil
            usernameCheckFailed = false
            return
        }
        checkingUsername = true
        usernameCheckFailed = false
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard username == value else { return }
            let result = await appState.checkUsername(value)
            checkingUsername = false
            if let available = result {
                usernameAvailable = available
                usernameCheckFailed = false
            } else {
                usernameAvailable = nil
                usernameCheckFailed = true
            }
        }
    }
}
