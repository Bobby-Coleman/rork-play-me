import SwiftUI
import MessageUI
import FirebaseAuth

struct OnboardingInviteView: View {
    let appState: AppState
    let username: String
    let onContinue: () -> Void

    @State private var allContacts: [SimpleContact] = []
    @State private var contactsGranted = false
    @State private var contactsDenied = false
    @State private var visibleContactCount = 20
    @State private var messageRecipient: MessageRecipient?
    @State private var showShareSheet = false
    @State private var searchText = ""
    @State private var inviteLink: String = ""

    @FocusState private var searchFocused: Bool

    private var inviteBody: String {
        let link = inviteLink.isEmpty
            ? DeepLinkService.publicTestFlightInviteURL
            : inviteLink
        return "I found this app where we can send songs to each other's home screen you should add me \(link)"
    }

    private var isActive: Bool { !searchText.isEmpty }

    private var filteredContacts: [SimpleContact] {
        guard isActive else { return [] }
        let q = searchText.lowercased()
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

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                    Text("Find your friends!")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                        .padding(.bottom, 4)

                    Text("Invite friends so you can send\nsongs to each other")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 20)

                    // MARK: - Search bar
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
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)

                    // MARK: - Share your PlayMe link
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Share your Play Me link")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.5))
                            .textCase(.uppercase)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 8)

                        shareRow(icon: "message.fill", color: .green, title: "Messages") {
                            messageRecipient = MessageRecipient(numbers: [])
                        }

                        Divider().background(Color.white.opacity(0.06)).padding(.leading, 62)

                        shareRow(icon: "square.and.arrow.up", color: .gray, title: "Other apps") {
                            showShareSheet = true
                        }
                    }
                    .padding(.bottom, 16)

                    // MARK: - Contacts (single scroll column — no nested ScrollView)
                    if contactsGranted {
                        Text("Your contacts")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.5))
                            .textCase(.uppercase)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 8)

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
                    } else if contactsDenied {
                        VStack(spacing: 12) {
                            Image(systemName: "person.crop.circle.badge.xmark")
                                .font(.system(size: 36))
                                .foregroundStyle(.white.opacity(0.3))
                            Text("Contacts access was denied.\nYou can enable it in Settings.")
                                .font(.system(size: 14))
                                .foregroundStyle(.white.opacity(0.5))
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                        .padding(.horizontal, 20)
                    } else {
                        ProgressView()
                            .tint(.white.opacity(0.6))
                            .frame(maxWidth: .infinity)
                            .padding(.top, 48)
                    }

                    Color.clear.frame(height: 24)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 8) {
                    Button(action: onContinue) {
                        Text("Continue")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(.white)
                            .clipShape(.rect(cornerRadius: 25))
                    }

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
        }
        .toolbar {
            ToolbarItem(placement: .keyboard) {
                HStack {
                    Spacer(minLength: 0)
                    Button("Done") {
                        searchFocused = false
                    }
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                }
            }
        }
        .task {
            if let uid = Auth.auth().currentUser?.uid {
                inviteLink = await DeepLinkService.shared.createInviteLink(userId: uid, username: username) ?? ""
            }

            let granted = await ContactsService.shared.requestAccess()
            contactsGranted = granted
            contactsDenied = !granted
            if granted {
                allContacts = ContactsService.shared.fetchContacts()
            }
        }
        .sheet(item: $messageRecipient) { recipient in
            if MessageComposeView.canSendText {
                MessageComposeView(
                    recipients: recipient.numbers,
                    body: inviteBody
                ) { messageRecipient = nil }
                .ignoresSafeArea()
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheetView(items: [inviteBody])
        }
    }

    // MARK: - Rows

    private func shareRow(icon: String, color: Color, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(color)
                    .clipShape(.rect(cornerRadius: 8))

                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func contactRow(_ contact: SimpleContact) -> some View {
        HStack(spacing: 14) {
            Text(contact.initials)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(Color.white.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(contact.fullName)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                messageRecipient = MessageRecipient(numbers: [contact.phoneNumber])
                recordInvitedContact(contact)
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
        }
        .padding(.vertical, 8)
    }

    private func alreadyInvited(_ contact: SimpleContact) -> Bool {
        appState.invitedContacts.contains(where: { $0.id == contact.id })
    }

    private func recordInvitedContact(_ contact: SimpleContact) {
        if !alreadyInvited(contact) {
            appState.invitedContacts.append(contact)
        }
    }
}

private struct MessageRecipient: Identifiable {
    let id = UUID()
    let numbers: [String]
}

// MARK: - Share Sheet (UIActivityViewController)
struct ShareSheetView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
