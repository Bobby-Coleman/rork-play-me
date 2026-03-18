import SwiftUI

struct NameUsernameView: View {
    @Binding var firstName: String
    @Binding var username: String
    let appState: AppState
    let onComplete: () -> Void

    @State private var step: Int = 0
    @State private var usernameAvailable: Bool? = nil
    @State private var checkingUsername = false
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

                if step == 0 {
                    Text("What's your\nfirst name?")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.bottom, 24)

                    HStack(spacing: 12) {
                        TextField("John", text: $firstName)
                            .font(.system(size: 18))
                            .foregroundStyle(.white)
                            .textContentType(.givenName)
                            .focused($isFocused)
                            .submitLabel(.next)
                            .onSubmit { advanceToUsername() }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(Color.white.opacity(0.1))
                            .clipShape(.rect(cornerRadius: 12))

                        Button(action: advanceToUsername) {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(.black)
                                .frame(width: 48, height: 48)
                                .background(.white)
                                .clipShape(Circle())
                        }
                        .disabled(firstName.isEmpty)
                        .opacity(firstName.isEmpty ? 0.4 : 1)
                    }
                } else {
                    Text("Choose a\nusername")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.bottom, 24)

                    HStack(spacing: 12) {
                        HStack(spacing: 4) {
                            Text("@")
                                .font(.system(size: 18))
                                .foregroundStyle(.white.opacity(0.4))
                            TextField("username", text: $username)
                                .font(.system(size: 18))
                                .foregroundStyle(.white)
                                .textContentType(.username)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .focused($isFocused)
                                .submitLabel(.done)
                                .onSubmit { completeIfAvailable() }
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
                }

                Spacer()
                Spacer()
            }
            .padding(.horizontal, 24)
            .animation(.spring(duration: 0.4), value: step)
        }
        .onAppear { isFocused = true }
    }

    private func advanceToUsername() {
        guard !firstName.isEmpty else { return }
        step = 1
        Task {
            try? await Task.sleep(for: .milliseconds(100))
            isFocused = true
        }
    }

    private func completeIfAvailable() {
        guard !username.isEmpty, usernameAvailable == true else { return }
        onComplete()
    }

    private func checkUsernameAvailability(_ value: String) {
        guard !value.isEmpty else {
            usernameAvailable = nil
            return
        }
        checkingUsername = true
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard username == value else { return }
            let available = await appState.checkUsername(value)
            checkingUsername = false
            usernameAvailable = available
        }
    }
}
