import SwiftUI

struct UsernamePickerView: View {
    @Binding var username: String
    let appState: AppState
    let onComplete: () -> Void

    @State private var usernameAvailable: Bool? = nil
    @State private var checkingUsername = false
    @State private var usernameCheckFailed = false
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            BlobShape()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.05), Color.clear],
                        center: .center,
                        startRadius: 20,
                        endRadius: 180
                    )
                )
                .frame(width: 300, height: 300)
                .offset(y: -140)

            VStack(alignment: .leading, spacing: 0) {
                Spacer()

                Text("Choose a\nusername")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.bottom, 24)

                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Text("@")
                            .font(.system(size: 18))
                            .foregroundStyle(.white.opacity(0.4))
                        AppTextField("username", text: $username, submitLabel: .done) {
                            completeIfAvailable()
                        }
                            .font(.system(size: 18))
                            .foregroundStyle(.white)
                            .textContentType(.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($isFocused)
                            .onChange(of: username) { _, newValue in
                                checkUsernameAvailability(newValue)
                            }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color.white.opacity(0.1))
                    .clipShape(.rect(cornerRadius: 12))

                    Button(action: completeIfAvailable) {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(width: 48, height: 48)
                            .background(.white)
                            .clipShape(Circle())
                    }
                    .disabled(username.isEmpty || usernameAvailable != true)
                    .opacity(username.isEmpty || usernameAvailable != true ? 0.4 : 1)
                }

                if checkingUsername {
                    HStack(spacing: 6) {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.7)
                        Text("checking...")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .padding(.top, 8)
                } else if usernameCheckFailed && !username.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                        Text("Could not verify \u{2014} check connection")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    .padding(.top, 8)
                } else if let available = usernameAvailable, !username.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: available ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(available ? .green : .red)
                            .font(.caption)
                        Text(available ? "available" : "taken")
                            .font(.caption)
                            .foregroundStyle(available ? .green : .red)
                    }
                    .padding(.top, 8)
                }

                if let error = appState.registrationError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.top, 8)
                }

                Spacer()
                Spacer()
            }
            .padding(.horizontal, 24)
        }
        .appKeyboardDismiss()
        .onAppear { isFocused = true }
    }

    private func completeIfAvailable() {
        guard !username.isEmpty, usernameAvailable == true else { return }
        onComplete()
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
