import SwiftUI
import MessageUI
import Contacts
import FirebaseAuth

/// Screen 12 — Pick friends to invite via SMS.
///
/// 8-slot meter + counter + search. Tapping a contact opens an
/// `MFMessageComposeViewController` (via `MessageComposeView`). On a
/// successful send we append to `appState.invitedContacts` so the
/// final "Send first song" screen can target them.
struct PickFriendsView: View {
    let appState: AppState
    let stepIdx: Int
    let totalSteps: Int
    let onContinue: () -> Void
    let onSkip: () -> Void
    let onBack: (() -> Void)?

    @Binding var contacts: [SimpleContact]

    @State private var search: String = ""
    @State private var inviteRecipient: OutgoingInvite?
    @State private var inviteLink: String = ""
    @FocusState private var searchFocused: Bool

    @Environment(\.riffTheme) private var theme

    private var inviteBody: String {
        let link = inviteLink.isEmpty
            ? DeepLinkService.publicTestFlightInviteURL
            : inviteLink
        return "wanna do this? \(link)"
    }

    private var filteredContacts: [SimpleContact] {
        let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return contacts }
        let q = trimmed.lowercased()
        return contacts.filter {
            $0.firstName.lowercased().contains(q) ||
            $0.lastName.lowercased().contains(q) ||
            $0.phoneNumber.contains(q)
        }
    }

    private var selectedCount: Int {
        appState.invitedContacts.count
    }

    private var canContinue: Bool {
        selectedCount >= 1
    }

    var body: some View {
        RiffScreenChrome(
            stepIdx: stepIdx,
            totalSteps: totalSteps,
            onBack: onBack,
            horizontalPadding: 0
        ) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Pick up to 8 friends")
                            .font(.system(size: 22, weight: .semibold))
                            .tracking(-0.44)
                        Spacer()
                        Counter(count: selectedCount)
                    }
                    Meter(count: selectedCount)
                    searchBar
                }
                .padding(.horizontal, 24)
                .padding(.top, 4)

                if contacts.isEmpty {
                    Text("Contacts access is off. Enable it in Settings to invite friends.")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.sub)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                        .padding(.horizontal, 32)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(filteredContacts) { contact in
                                row(for: contact)
                                Divider().background(theme.border)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 4)
                        .padding(.bottom, 12)
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
            }
        } footer: {
            VStack(spacing: 0) {
                RiffPrimaryButton(
                    title: "Send invites",
                    disabled: !canContinue,
                    action: onContinue
                )
                RiffTextLink(title: "Skip for now", action: onSkip)
                    .padding(.top, 4)
            }
        }
        .task {
            if let uid = Auth.auth().currentUser?.uid,
               let username = appState.currentUser?.username {
                inviteLink = await DeepLinkService.shared.createInviteLink(userId: uid, username: username) ?? ""
            }
        }
        .sheet(item: $inviteRecipient) { invite in
            if MessageComposeView.canSendText {
                MessageComposeView(
                    recipients: [invite.contact.phoneNumber],
                    body: inviteBody
                ) { result in
                    handleComposeResult(result, for: invite.contact)
                }
                .ignoresSafeArea()
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(theme.faint)
                .font(.system(size: 14))
            AppTextField("Search contacts", text: $search, submitLabel: .search) {
                searchFocused = false
            }
            .foregroundStyle(theme.fg)
            .focused($searchFocused)
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(theme.softBg)
        )
    }

    private func row(for contact: SimpleContact) -> some View {
        let invited = appState.invitedContacts.contains(where: { $0.id == contact.id })
        let limitReached = !invited && selectedCount >= 8

        return Button {
            if invited {
                appState.invitedContacts.removeAll { $0.id == contact.id }
            } else if !limitReached {
                inviteRecipient = OutgoingInvite(contact: contact)
            }
        } label: {
            HStack(spacing: 12) {
                Text(contact.initials)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(theme.fg)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(theme.softBg))

                VStack(alignment: .leading, spacing: 2) {
                    Text(contact.fullName)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(theme.fg)
                    Text(contact.phoneNumber)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.faint)
                }

                Spacer()

                ZStack {
                    Circle()
                        .stroke(invited ? theme.fg : theme.border, lineWidth: 1.5)
                        .background(Circle().fill(invited ? theme.fg : Color.clear))
                        .frame(width: 22, height: 22)
                    if invited {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(theme.bg)
                    }
                }
            }
            .padding(.vertical, 12)
            .opacity(limitReached ? 0.4 : 1)
        }
        .buttonStyle(.plain)
    }

    private func handleComposeResult(_ result: MessageComposeResult, for contact: SimpleContact) {
        inviteRecipient = nil
        guard result == .sent else { return }
        if !appState.invitedContacts.contains(where: { $0.id == contact.id }) {
            appState.invitedContacts.append(contact)
        }
    }
}

// MARK: - Counter + meter

private struct Counter: View {
    let count: Int
    @State private var bounceKey: Int = 0
    @Environment(\.riffTheme) private var theme

    var body: some View {
        Text("\(count)/8")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(theme.fg)
            .scaleEffect(bounceKey % 2 == 0 ? 1 : 1.18)
            .animation(.spring(response: 0.32, dampingFraction: 0.6), value: bounceKey)
            .onChange(of: count) { _, _ in bounceKey += 1 }
    }
}

private struct Meter: View {
    let count: Int
    @Environment(\.riffTheme) private var theme

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<8, id: \.self) { i in
                Capsule()
                    .fill(i < count ? theme.fg : theme.border)
                    .frame(height: 4)
                    .animation(.spring(response: 0.28, dampingFraction: 0.65), value: count)
            }
        }
    }
}

// MARK: - Outgoing invite

private struct OutgoingInvite: Identifiable {
    let id = UUID()
    let contact: SimpleContact
}
