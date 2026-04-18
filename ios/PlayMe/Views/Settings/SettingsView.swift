import SwiftUI

/// App-wide settings screen. Accessed from the gear icon in the Profile tab.
/// Groups are ordered from most-used to most-destructive so Delete Account
/// sits at the bottom (iOS HIG + App Store 5.1.1(v)).
struct SettingsView: View {
    @Bindable var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var showDeleteConfirm: Bool = false

    private let privacyPolicyURL = URL(string: "https://rork.app/privacy")!
    private let termsURL = URL(string: "https://rork.app/terms")!
    private let supportURL = URL(string: "mailto:support@rork.app?subject=PlayMe%20Support")!

    var body: some View {
        List {
            Section("Account") {
                accountRow(label: "Name", value: displayName)
                accountRow(label: "Username", value: "@\(appState.currentUser?.username ?? "")")
                accountRow(label: "Phone", value: appState.currentUser?.phone ?? "—")
            }

            Section("Notifications") {
                Toggle(isOn: notificationsBinding) {
                    labelRow(icon: "bell.fill", title: "Allow notifications", tint: .orange)
                }
                .tint(.green)
            }

            Section("Privacy & safety") {
                NavigationLink {
                    BlockedUsersView(appState: appState)
                } label: {
                    labelRow(icon: "hand.raised.fill", title: "Blocked users", tint: .red)
                }

                Link(destination: privacyPolicyURL) {
                    externalRow(icon: "lock.shield.fill", title: "Privacy policy")
                }

                Link(destination: termsURL) {
                    externalRow(icon: "doc.text.fill", title: "Terms of service")
                }
            }

            Section("Support") {
                Link(destination: supportURL) {
                    externalRow(icon: "envelope.fill", title: "Contact support")
                }
            }

            Section {
                Button(role: .destructive) {
                    appState.logout()
                    dismiss()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                        Text("Sign out")
                    }
                    .foregroundStyle(.red)
                }

                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "trash.fill")
                        Text("Delete account")
                    }
                    .foregroundStyle(.red)
                }
            } footer: {
                Text("Deleting your account permanently removes your profile, messages, and sent songs. This cannot be undone.")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
                    .foregroundStyle(.white)
            }
        }
        .sheet(isPresented: $showDeleteConfirm) {
            DeleteAccountConfirmView(appState: appState) {
                // Caller dismissed the confirm sheet manually.
                showDeleteConfirm = false
            } onDeleted: {
                showDeleteConfirm = false
                dismiss()
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }

    private var displayName: String {
        let first = appState.currentUser?.firstName ?? ""
        let last = appState.currentUser?.lastName ?? ""
        let combined = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
        return combined.isEmpty ? "—" : combined
    }

    private var notificationsBinding: Binding<Bool> {
        Binding(
            get: { appState.notificationsEnabled },
            set: { newValue in
                Task { await appState.setNotificationsEnabled(newValue) }
            }
        )
    }

    private func accountRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.white.opacity(0.7))
            Spacer()
            Text(value)
                .foregroundStyle(.white.opacity(0.4))
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func labelRow(icon: String, title: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(tint)
                .clipShape(.rect(cornerRadius: 6))
            Text(title)
                .foregroundStyle(.white)
        }
    }

    private func externalRow(icon: String, title: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Color.white.opacity(0.15))
                .clipShape(.rect(cornerRadius: 6))
            Text(title)
                .foregroundStyle(.white)
            Spacer()
            Image(systemName: "arrow.up.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.3))
        }
    }
}
