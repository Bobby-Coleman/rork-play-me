import SwiftUI

struct BlockedUsersView: View {
    @Bindable var appState: AppState

    @State private var blocked: [AppUser] = []
    @State private var isLoading: Bool = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
            } else if blocked.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(blocked) { user in
                        HStack(spacing: 14) {
                            Text(user.initials)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 38, height: 38)
                                .background(Color.white.opacity(0.12))
                                .clipShape(Circle())

                            VStack(alignment: .leading, spacing: 2) {
                                Text(user.firstName.isEmpty ? "User" : user.firstName)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(.white)
                                if !user.username.isEmpty {
                                    Text("@\(user.username)")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.white.opacity(0.4))
                                }
                            }

                            Spacer()

                            Button("Unblock") {
                                Task { await unblock(user) }
                            }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.15))
                            .clipShape(.capsule)
                        }
                        .listRowBackground(Color.white.opacity(0.04))
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(Color.black)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("Blocked")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await loadBlocked() }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "hand.raised")
                .font(.system(size: 32))
                .foregroundStyle(.white.opacity(0.2))
            Text("No blocked users")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
            Text("You can block someone from their profile, a song they sent you, or a message thread.")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.3))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    private func loadBlocked() async {
        isLoading = true
        blocked = await FirebaseService.shared.loadBlockedUsers()
        isLoading = false
    }

    private func unblock(_ user: AppUser) async {
        await appState.unblockUser(user.id)
        blocked.removeAll { $0.id == user.id }
    }
}
