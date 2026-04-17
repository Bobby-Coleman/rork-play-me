import SwiftUI
import MessageUI
import FirebaseAuth

struct AddFriendsView: View {
    let appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var searchResults: [AppUser] = []
    @State private var isSearching = false
    @State private var addedIds: Set<String> = []

    @State private var allContacts: [SimpleContact] = []
    @State private var contactsLoaded = false
    @State private var visibleContactCount = 20

    @State private var messageRecipient: MessageRecipient?
    @State private var showShareSheet = false
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
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {

                        // MARK: - Header
                        Text("\(appState.friends.count) friends")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 4)
                            .padding(.bottom, 2)

                        Text("Add your friends")
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.5))
                            .frame(maxWidth: .infinity)
                            .padding(.bottom, 16)

                        // MARK: - Search bar
                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.white.opacity(0.4))
                            TextField("Search or add friends", text: $searchText)
                                .foregroundStyle(.white)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .focused($searchFocused)
                                .onChange(of: searchText) { _, newValue in
                                    performSearch(newValue)
                                }

                            if isActive {
                                Button("Cancel") {
                                    searchText = ""
                                    searchResults = []
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
                        .padding(.bottom, 16)

                        if isActive {
                            searchContent
                        } else {
                            browseContent
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
            if let uid = Auth.auth().currentUser?.uid,
               let username = appState.currentUser?.username {
                inviteLink = await DeepLinkService.shared.createInviteLink(userId: uid, username: username) ?? ""
            }

            let granted = await ContactsService.shared.requestAccess()
            if granted {
                allContacts = ContactsService.shared.fetchContacts()
            }
            contactsLoaded = true
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

    // MARK: - Search active content

    private var searchContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !filteredContacts.isEmpty {
                sectionHeader("Your contacts", icon: "person.crop.rectangle.stack")

                LazyVStack(spacing: 0) {
                    ForEach(filteredContacts) { contact in
                        contactRow(contact)
                    }
                }
                .padding(.horizontal, 20)

                Divider()
                    .background(Color.white.opacity(0.06))
                    .padding(.vertical, 12)
            }

            if isSearching {
                sectionHeader("Add by username", icon: "at")
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
            } else if !searchResults.isEmpty {
                sectionHeader("Add by username", icon: "at")

                LazyVStack(spacing: 0) {
                    ForEach(searchResults) { user in
                        userRow(user)
                    }
                }
                .padding(.horizontal, 20)
            }

            if !isSearching && filteredContacts.isEmpty && searchResults.isEmpty {
                Text("No results found")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.3))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)
            }

            Divider()
                .background(Color.white.opacity(0.06))
                .padding(.vertical, 12)

            shareLinkSection
        }
    }

    // MARK: - Browse (no search) content

    private var browseContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Share link first
            shareLinkSection

            Divider()
                .background(Color.white.opacity(0.06))
                .padding(.vertical, 12)

            // Contacts
            sectionHeader("Your contacts", icon: "person.crop.rectangle.stack")

            if contactsLoaded {
                if allContacts.isEmpty {
                    Text("No contacts with phone numbers found")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.3))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 12)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(paginatedContacts) { contact in
                            contactRow(contact)
                        }
                    }
                    .padding(.horizontal, 20)

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
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                    }
                }
            } else {
                Button {
                    Task {
                        let granted = await ContactsService.shared.requestAccess()
                        if granted {
                            allContacts = ContactsService.shared.fetchContacts()
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
    }

    // MARK: - Share link section

    private var shareLinkSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Share your Play Me link", icon: "square.and.arrow.up")

            shareRow(icon: "message.fill", color: .green, title: "Messages") {
                messageRecipient = MessageRecipient(numbers: [])
            }

            Divider().background(Color.white.opacity(0.06)).padding(.leading, 62)

            shareRow(icon: "square.and.arrow.up", color: .gray, title: "Other apps") {
                showShareSheet = true
            }
        }
    }

    // MARK: - Subviews

    private func sectionHeader(_ title: String, icon: String? = nil) -> some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
            }
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
                .textCase(.uppercase)
        }
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
                    addButtonLabel("Add")
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
                messageRecipient = MessageRecipient(numbers: [contact.phoneNumber])
            } label: {
                addButtonLabel("Invite")
            }
        }
        .padding(.vertical, 8)
    }

    private func addButtonLabel(_ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .bold))
            Text(text)
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(red: 0.76, green: 0.38, blue: 0.35))
        .clipShape(.capsule)
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

private struct MessageRecipient: Identifiable {
    let id = UUID()
    let numbers: [String]
}
