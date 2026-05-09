import SwiftUI
import MessageUI
import Contacts
import FirebaseAuth

/// Screen 12 — Pick friends to invite via SMS.
///
/// 8-slot meter + counter + search + paginated list. Each row has **+ Add**
/// (opens `MFMessageComposeViewController`); after a successful send the row
/// shows **Invited**. Continue stays disabled until at least one invite is sent.
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
    @State private var visibleContactCount: Int = 20
    @FocusState private var searchFocused: Bool

    @Environment(\.riffTheme) private var theme

    private let contactPageSize = 20

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

    private var displayedContacts: [SimpleContact] {
        Array(filteredContacts.prefix(visibleContactCount))
    }

    private var hasMoreContacts: Bool {
        visibleContactCount < filteredContacts.count
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
                            ForEach(displayedContacts) { contact in
                                row(for: contact)
                                Divider().background(theme.border)
                            }
                            if hasMoreContacts {
                                Button {
                                    visibleContactCount = min(
                                        visibleContactCount + contactPageSize,
                                        filteredContacts.count
                                    )
                                } label: {
                                    Text("See more")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(theme.sub)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 16)
                                }
                                .buttonStyle(.plain)
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
                    title: "Continue",
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
        .onChange(of: search) { _, _ in
            visibleContactCount = contactPageSize
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

        return HStack(spacing: 12) {
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

            Spacer(minLength: 8)

            if invited {
                Button {
                    appState.invitedContacts.removeAll { $0.id == contact.id }
                } label: {
                    Text("Invited")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.sub)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(theme.fg.opacity(theme.isLight ? 0.08 : 0.12))
                        )
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    guard !limitReached else { return }
                    inviteRecipient = OutgoingInvite(contact: contact)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                        Text("Add")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(limitReached ? theme.faint : theme.fg)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        Capsule()
                            .stroke(theme.border, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(limitReached)
            }
        }
        .padding(.vertical, 12)
        .opacity(limitReached && !invited ? 0.45 : 1)
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
