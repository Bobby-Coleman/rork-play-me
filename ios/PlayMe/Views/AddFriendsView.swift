import SwiftUI
import MessageUI

struct AddFriendsView: View {
    let appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var searchResults: [AppUser] = []
    @State private var isSearching = false
    @State private var addedIds: Set<String> = []

    @State private var contacts: [SimpleContact] = []
    @State private var contactsLoaded = false

    @State private var showMessageCompose = false
    @State private var messageRecipients: [String] = []
    @State private var showShareSheet = false

    private var inviteURL: String {
        let base = Bundle.main.object(forInfoDictionaryKey: "InviteBaseURL") as? String
            ?? "https://rork-play-me.web.app"
        let username = appState.currentUser?.username ?? ""
        return "\(base)/invite/u/\(username)"
    }

    private var inviteBody: String {
        "I found this app where we can send songs to each other's home screen you should add me \(inviteURL)"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // MARK: - Search users
                        sectionHeader("Search users")

                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.white.opacity(0.4))
                            TextField("Search by username", text: $searchText)
                                .foregroundStyle(.white)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .onChange(of: searchText) { _, newValue in
                                    performSearch(newValue)
                                }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.08))
                        .clipShape(.rect(cornerRadius: 10))
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)

                        if isSearching {
                            ProgressView()
                                .tint(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 12)
                        } else if !searchResults.isEmpty {
                            LazyVStack(spacing: 0) {
                                ForEach(searchResults) { user in
                                    userRow(user)
                                }
                            }
                            .padding(.horizontal, 20)
                        } else if !searchText.isEmpty && !isSearching {
                            Text("No users found")
                                .font(.system(size: 14))
                                .foregroundStyle(.white.opacity(0.3))
                                .frame(maxWidth: .infinity)
                                .padding(.top, 12)
                        }

                        Divider()
                            .background(Color.white.opacity(0.06))
                            .padding(.vertical, 16)

                        // MARK: - Share link
                        sectionHeader("Share your Play Me link")

                        shareRow(icon: "message.fill", color: .green, title: "Messages") {
                            messageRecipients = []
                            showMessageCompose = true
                        }

                        Divider().background(Color.white.opacity(0.06)).padding(.leading, 62)

                        shareRow(icon: "square.and.arrow.up", color: .gray, title: "Other apps") {
                            showShareSheet = true
                        }

                        Divider()
                            .background(Color.white.opacity(0.06))
                            .padding(.vertical, 16)

                        // MARK: - Contacts
                        sectionHeader("Your contacts")

                        if contactsLoaded {
                            LazyVStack(spacing: 0) {
                                ForEach(contacts) { contact in
                                    contactRow(contact)
                                }
                            }
                            .padding(.horizontal, 20)

                            if contacts.isEmpty {
                                Text("No contacts with phone numbers found")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.white.opacity(0.3))
                                    .frame(maxWidth: .infinity)
                                    .padding(.top, 12)
                            }
                        } else {
                            Button {
                                Task {
                                    let granted = await ContactsService.shared.requestAccess()
                                    if granted {
                                        contacts = ContactsService.shared.fetchContacts()
                                    }
                                    contactsLoaded = true
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "person.crop.circle")
                                    Text("Allow contacts access")
                                }
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.white.opacity(0.08))
                                .clipShape(.rect(cornerRadius: 10))
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Add Friends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .task {
            let granted = await ContactsService.shared.requestAccess()
            if granted {
                contacts = ContactsService.shared.fetchContacts()
            }
            contactsLoaded = true
        }
        .sheet(isPresented: $showMessageCompose) {
            if MessageComposeView.canSendText {
                MessageComposeView(
                    recipients: messageRecipients,
                    body: inviteBody
                ) { showMessageCompose = false }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheetView(items: [inviteBody])
        }
    }

    // MARK: - Subviews

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white.opacity(0.5))
            .textCase(.uppercase)
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
    }

    private func userRow(_ user: AppUser) -> some View {
        let alreadyFriend = appState.friends.contains(where: { $0.id == user.id })
        let justAdded = addedIds.contains(user.id)

        return HStack(spacing: 14) {
            Text(user.initials)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(Color.white.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(user.firstName)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
                Text("@\(user.username)")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.4))
            }

            Spacer()

            if alreadyFriend || justAdded {
                Text("Added")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.06))
                    .clipShape(.capsule)
            } else {
                Button {
                    Task {
                        await FirebaseService.shared.addFriend(
                            friendUID: user.id,
                            friendUsername: user.username,
                            friendFirstName: user.firstName,
                            friendLastName: user.lastName
                        )
                        addedIds.insert(user.id)
                        await appState.refreshFriends()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                        Text("Add")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(red: 0.76, green: 0.38, blue: 0.35))
                    .clipShape(.capsule)
                }
            }
        }
        .padding(.vertical, 8)
    }

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

            Text(contact.fullName)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)

            Spacer()

            Button {
                messageRecipients = [contact.phoneNumber]
                showMessageCompose = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                    Text("Invite")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(red: 0.76, green: 0.38, blue: 0.35))
                .clipShape(.capsule)
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Search

    private func performSearch(_ query: String) {
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        isSearching = true
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard searchText == query else { return }
            searchResults = await appState.searchAllUsers(query: query)
            isSearching = false
        }
    }
}
