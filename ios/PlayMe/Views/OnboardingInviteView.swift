import SwiftUI
import MessageUI
import Contacts
import FirebaseAuth

struct OnboardingInviteView: View {
    let appState: AppState
    let username: String
    let onContinue: () -> Void

    @State private var allContacts: [SimpleContact] = []
    @State private var contactsStatus: CNAuthorizationStatus = CNContactStore.authorizationStatus(for: .contacts)
    @State private var visibleContactCount = 20
    @State private var messageRecipient: OutgoingInvite?
    @State private var showShareSheet = false
    @State private var searchText = ""
    @State private var inviteLink: String = ""
    @State private var gateErrorVisible = false

    @FocusState private var searchFocused: Bool

    private var inviteBody: String {
        let link = inviteLink.isEmpty
            ? DeepLinkService.publicTestFlightInviteURL
            : inviteLink
        return "wanna do this? \(link)"
    }

    private var isActive: Bool { !searchText.isEmpty }

    private var hasMinimumInvites: Bool {
        !appState.invitedContacts.isEmpty
    }

    private var filteredContacts: [SimpleContact] {
        guard isActive else { return [] }
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let q = (trimmed.hasPrefix("@") ? String(trimmed.dropFirst()) : trimmed).lowercased()
        guard !q.isEmpty else { return [] }
        return allContacts.filter {
            $0.firstName.lowercased().contains(q) ||
            $0.lastName.lowercased().contains(q) ||
            $0.phoneNumber.contains(q)
        }
    }

    private var paginatedContacts: [SimpleContact] {
        Array(allContacts.prefix(visibleContactCount))
    }

    private var hasMoreContacts: Bool {
        visibleContactCount < allContacts.count
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if contactsStatus == .notDetermined {
                permissionGate
            } else {
                mainContent
            }
        }
        .toolbar {
            ToolbarItem(placement: .keyboard) {
                HStack {
                    Spacer(minLength: 0)
                    Button("Done") { searchFocused = false }
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
        }
        .task {
            if let uid = Auth.auth().currentUser?.uid {
                inviteLink = await DeepLinkService.shared.createInviteLink(userId: uid, username: username) ?? ""
            }
            // If the user has already granted contacts previously (e.g. via
            // AddFriendsView), skip the pre-permission gate entirely.
            if CNContactStore.authorizationStatus(for: .contacts) == .authorized {
                allContacts = ContactsService.shared.fetchContacts()
                contactsStatus = .authorized
            }
        }
        .sheet(item: $messageRecipient) { invite in
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
        .sheet(isPresented: $showShareSheet) {
            ShareSheetView(items: [inviteBody])
        }
    }

    // MARK: - Pre-permission gate

    private var permissionGate: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "person.2.fill")
                .font(.system(size: 44))
                .foregroundStyle(.white.opacity(0.85))

            Text("Find your friends")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)

            Text("Play Me uses your contacts to find friends.")
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()

            Button {
                Task { await requestContactsAccess() }
            } label: {
                Text("Allow Contacts")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(.white)
                    .clipShape(.rect(cornerRadius: 25))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }

    private func requestContactsAccess() async {
        let granted = await ContactsService.shared.requestAccess()
        if granted {
            allContacts = ContactsService.shared.fetchContacts()
            contactsStatus = .authorized
        } else {
            contactsStatus = .denied
        }
    }

    // MARK: - Main content (contacts + invite flow)

    private var mainContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                Text("Invite friends to Play Me")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)
                    .padding(.bottom, 6)

                Text("You must have at least one friend added to use Play Me.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 20)

                searchBar
                    .padding(.horizontal, 20)
                    .padding(.bottom, 14)

                shareLinkRow
                    .padding(.bottom, 16)

                contactsSection

                Color.clear.frame(height: 32)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomBar
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.white.opacity(0.4))
            TextField("Search your contacts", text: $searchText)
                .foregroundStyle(.white)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .focused($searchFocused)

            if isActive {
                Button("Cancel") {
                    searchText = ""
                    searchFocused = false
                }
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.08))
        .clipShape(.rect(cornerRadius: 10))
    }

    private var shareLinkRow: some View {
        Button {
            showShareSheet = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                Text("Share your Play Me link")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var contactsSection: some View {
        if contactsStatus == .authorized {
            Group {
                if isActive {
                    ForEach(filteredContacts) { contact in
                        contactRow(contact)
                    }
                    if filteredContacts.isEmpty {
                        Text("No matching contacts")
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.3))
                            .frame(maxWidth: .infinity)
                            .padding(.top, 12)
                    }
                } else {
                    ForEach(paginatedContacts) { contact in
                        contactRow(contact)
                    }
                    if hasMoreContacts {
                        Button {
                            visibleContactCount = min(visibleContactCount + 20, allContacts.count)
                        } label: {
                            Text("Show more")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.6))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.white.opacity(0.06))
                                .clipShape(.rect(cornerRadius: 10))
                        }
                        .padding(.top, 8)
                    }
                }
            }
            .padding(.horizontal, 20)
        } else {
            VStack(spacing: 10) {
                Text("Contacts access is off. Enable it in Settings to invite friends, or share your link above.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 24)
            .padding(.horizontal, 32)
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            if gateErrorVisible {
                Text("You need at least one friend to use Play Me")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(red: 0.78, green: 0.22, blue: 0.22).opacity(0.95))
                    .clipShape(.capsule)
                    .transition(.opacity)
            }

            Button {
                if hasMinimumInvites {
                    onContinue()
                } else {
                    withAnimation(.easeInOut(duration: 0.15)) { gateErrorVisible = true }
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        withAnimation(.easeInOut(duration: 0.2)) { gateErrorVisible = false }
                    }
                }
            } label: {
                Text("Continue")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(.white.opacity(hasMinimumInvites ? 1.0 : 0.4))
                    .clipShape(.rect(cornerRadius: 25))
            }
            .buttonStyle(.plain)

            Button(action: onContinue) {
                Text("testing skip")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.94))
    }

    // MARK: - Rows

    private func contactRow(_ contact: SimpleContact) -> some View {
        HStack(spacing: 14) {
            Text(contact.initials)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(Color.white.opacity(0.12))
                .clipShape(Circle())

            Text(contact.fullName)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)

            Spacer()

            Button {
                messageRecipient = OutgoingInvite(contact: contact)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: alreadyInvited(contact) ? "checkmark" : "plus")
                        .font(.system(size: 11, weight: .bold))
                    Text(alreadyInvited(contact) ? "Invited" : "Invite")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    alreadyInvited(contact)
                        ? Color.white.opacity(0.18)
                        : Color(red: 0.76, green: 0.38, blue: 0.35)
                )
                .clipShape(.capsule)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
    }

    private func alreadyInvited(_ contact: SimpleContact) -> Bool {
        appState.invitedContacts.contains(where: { $0.id == contact.id })
    }

    private func handleComposeResult(_ result: MessageComposeResult, for contact: SimpleContact) {
        messageRecipient = nil
        // Only count an invite if the user actually sent the SMS. `.cancelled`
        // and `.failed` must not satisfy the "at least one friend" gate.
        guard result == .sent else { return }
        if !alreadyInvited(contact) {
            appState.invitedContacts.append(contact)
        }
    }
}

private struct OutgoingInvite: Identifiable {
    let id = UUID()
    let contact: SimpleContact
}

// MARK: - Share Sheet (UIActivityViewController)
struct ShareSheetView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
