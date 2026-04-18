import SwiftUI

/// Single-step delete-account confirmation. A destructive red button after an
/// explicit warning screen is the mobile pattern used by Instagram, Snapchat,
/// Twitter/X, etc. — enough friction without the awkwardness of retyping a
/// username on a phone keyboard.
struct DeleteAccountConfirmView: View {
    @Bindable var appState: AppState
    let onCancel: () -> Void
    let onDeleted: () -> Void

    @State private var isDeleting: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 18) {
            Capsule()
                .fill(Color.white.opacity(0.2))
                .frame(width: 36, height: 4)
                .padding(.top, 6)

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 34))
                .foregroundStyle(.red)

            Text("Delete your account?")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)

            Text("This permanently removes your profile, username, friends list, and unread messages. Songs you've already sent will show as \u{201C}Deleted user\u{201D} to recipients. This cannot be undone.")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.red.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }

            Spacer(minLength: 0)

            VStack(spacing: 10) {
                Button {
                    Task { await performDelete() }
                } label: {
                    HStack {
                        if isDeleting { ProgressView().tint(.white) }
                        Text(isDeleting ? "Deleting..." : "Delete my account")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(isDeleting ? Color.red.opacity(0.4) : Color.red)
                    .clipShape(.rect(cornerRadius: 12))
                }
                .disabled(isDeleting)

                Button("Cancel") {
                    onCancel()
                }
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .disabled(isDeleting)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
    }

    private func performDelete() async {
        isDeleting = true
        errorMessage = nil
        let result = await appState.deleteAccount()
        isDeleting = false
        switch result {
        case .success:
            onDeleted()
        case .failure(let err):
            errorMessage = err.errorDescription ?? "Delete failed. Please try again."
        }
    }
}
