import SwiftUI
import MessageUI
import FirebaseAuth
import UserNotifications

struct AddFriendsView: View {
    let appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var searchResults: [AppUser] = []
    @State private var isSearching = false
    @State private var addedIds: Set<String> = []
    /// Username matches are capped to the top few for compactness; the
    /// contact list below is the longer scroll. Tapping "Show more"
    /// expands to the full username match list.
    @State private var showAllUsernameResults = false
    private let usernameResultCap = 3

    @State private var allContacts: [SimpleContact] = []
    @State private var contactsLoaded = false
    @State private var visibleContactCount = 20

    @State private var messageRecipient: MessageRecipient?
    @State private var shareInvite: ShareInvite?
    @State private var preparingInviteID: String?
    /// The contact whose SMS invite is currently being composed, so a
    /// successful send can be recorded in `appState.invitedContacts`. Nil
    /// for the generic "Messages" / "Other apps" share rows.
    @State private var invitingContact: SimpleContact?

    @State private var showFriendsList: Bool = true
    @State private var reportTarget: ReportTarget?
    @State private var showReportedToast: Bool = false
    @State private var pendingBlock: AppUser?
    @State private var pendingRemoveFriend: AppUser?
    @State private var unfriendErrorMessage: String?

    @FocusState private var searchFocused: Bool

    private var fallbackInviteBody: String {
        "wanna do this? \(DeepLinkService.publicTestFlightInviteURL)"
    }

    private var isActive: Bool { !searchText.isEmpty }

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
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {

                        // MARK: - Header
                        // Header now includes the friend cap so users always
                        // know how many slots they have left. When the cap is
                        // reached we also show a soft toast on accept attempts.
                        let atCap = appState.isAtFriendCap
                        Text("\(appState.friendCountDisplay) of \(appState.friendLimit) friends")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 4)
                            .padding(.bottom, 2)

                        Text(atCap
                             ? "You've reached your friend limit"
                             : "Add your friends")
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(atCap ? 0.7 : 0.5))
                            .frame(maxWidth: .infinity)
                            .padding(.bottom, 16)

                        if let msg = appState.friendCapMessage {
                            Text(msg)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.orange)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, 20)
                                .padding(.bottom, 12)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        // MARK: - Search bar (always visible, at the top)
                        // Moved above the friend requests / your friends
                        // sections so username search is the primary
                        // affordance. Matches industry-standard add-by-
                        // handle flows (Instagram, Snapchat).
                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.white.opacity(0.4))
                            AppTextField("Search by username or name", text: $searchText, submitLabel: .search) {
                                searchFocused = false
                            }
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
                            if !appState.invitedContacts.isEmpty {
                                invitedSection
                                    .padding(.bottom, 16)
                            }

                            if !appState.incomingRequests.isEmpty {
                                friendRequestsSection
                                    .padding(.bottom, 16)
                            }

                            if !appState.outgoingRequests.isEmpty {
                                sentRequestsSection
                                    .padding(.bottom, 16)
                            }

                            if !appState.friends.isEmpty {
                                yourFriendsSection
                                    .padding(.bottom, 16)
                            }

                            browseContent
                        }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
                .scrollDismissesKeyboard(.interactively)
                .appKeyboardDismiss()
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
                allContacts = ContactsService.shared.fetchContacts()
            }
            contactsLoaded = true
        }
        .onAppear {
            clearDeliveredFriendRequestNotifications()
            ActiveScreenTracker.shared.isViewingAddFriends = true
        }
        .onDisappear {
            ActiveScreenTracker.shared.isViewingAddFriends = false
        }
        .sheet(item: $messageRecipient) { recipient in
            if MessageComposeView.canSendText {
                MessageComposeView(
                    recipients: recipient.numbers,
                    body: recipient.body
                ) { result in
                    recordInviteIfSent(result)
                    messageRecipient = nil
                }
                .ignoresSafeArea()
            }
        }
        .sheet(item: $shareInvite) { invite in
            ShareSheetView(items: [invite.body])
        }
        .sheet(item: $reportTarget) { target in
            ReportSheet(target: target, appState: appState) {
                withAnimation { showReportedToast = true }
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    withAnimation { showReportedToast = false }
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .overlay(alignment: .top) {
            if showReportedToast {
                Text("Report submitted. Thanks for keeping RIFF safe.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.9))
                    .clipShape(.capsule)
                    .padding(.top, 50)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .overlay(alignment: .top) {
            if let toast = appState.friendRequestToast {
                friendRequestToastView(message: toast, isError: false)
            } else if let err = appState.friendRequestError {
                friendRequestToastView(message: err, isError: true)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: appState.friendRequestToast)
        .animation(.easeInOut(duration: 0.2), value: appState.friendRequestError)
        .alert("Block \(pendingBlock?.firstName ?? "user")?", isPresented: blockAlertBinding) {
            Button("Cancel", role: .cancel) { pendingBlock = nil }
            Button("Block", role: .destructive) {
                if let user = pendingBlock {
                    Task { await appState.blockUser(user) }
                }
                pendingBlock = nil
            }
        } message: {
            Text("They won't be able to send you songs or messages, and you won't see their content.")
        }
        .alert("Remove \(pendingRemoveFriend?.firstName ?? "friend")?", isPresented: removeFriendAlertBinding) {
            Button("Cancel", role: .cancel) { pendingRemoveFriend = nil }
            Button("Remove Friend", role: .destructive) {
                if let friend = pendingRemoveFriend {
                    removeFriend(friend)
                }
                pendingRemoveFriend = nil
            }
        } message: {
            Text("You can add them again later if you both have an open friend slot.")
        }
        .alert("Couldn't remove friend", isPresented: unfriendErrorBinding) {
            Button("OK", role: .cancel) { unfriendErrorMessage = nil }
        } message: {
            Text(unfriendErrorMessage ?? "Please try again.")
        }
    }

    private var blockAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingBlock != nil },
            set: { if !$0 { pendingBlock = nil } }
        )
    }

    private var removeFriendAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingRemoveFriend != nil },
            set: { if !$0 { pendingRemoveFriend = nil } }
        )
    }

    private var unfriendErrorBinding: Binding<Bool> {
        Binding(
            get: { unfriendErrorMessage != nil },
            set: { if !$0 { unfriendErrorMessage = nil } }
        )
    }

    // MARK: - Search active content

    private var searchContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Username results lead — searching by @handle is the primary
            // intent for this screen.
            if isSearching {
                sectionHeader("Add by username", icon: "at")
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
            } else if !searchResults.isEmpty {
                sectionHeader("Add by username", icon: "at")

                let visibleResults = showAllUsernameResults
                    ? searchResults
                    : Array(searchResults.prefix(usernameResultCap))

                LazyVStack(spacing: 0) {
                    ForEach(visibleResults) { user in
                        userRow(user)
                    }
                }
                .padding(.horizontal, 20)

                if !showAllUsernameResults && searchResults.count > usernameResultCap {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showAllUsernameResults = true
                        }
                    } label: {
                        Text("Show more")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.08))
                            .clipShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)
                }
            }

            if !searchResults.isEmpty && !filteredContacts.isEmpty {
                Divider()
                    .background(Color.white.opacity(0.06))
                    .padding(.vertical, 12)
            }

            if !filteredContacts.isEmpty {
                sectionHeader("Your contacts", icon: "person.crop.rectangle.stack")

                LazyVStack(spacing: 0) {
                    ForEach(filteredContacts) { contact in
                        contactRow(contact)
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

    // MARK: - Your Friends (collapsible)

    private var yourFriendsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Your Friends", icon: "person.2.fill")

            if showFriendsList {
                LazyVStack(spacing: 0) {
                    ForEach(appState.friends) { friend in
                        friendRow(friend)
                    }
                }
                .padding(.horizontal, 20)
            }

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showFriendsList.toggle()
                }
            } label: {
                Text(showFriendsList ? "Show less" : "Show more")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.08))
                    .clipShape(.capsule)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 12)
        }
    }

    private func friendRow(_ friend: AppUser) -> some View {
        HStack(spacing: 14) {
            AppUserAvatar(
                user: friend,
                size: 42,
                background: Color.white.opacity(0.12),
                border: AppAccentGradient.pink,
                borderWidth: 2
            )

            Text(friend.firstName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)

            Spacer()

            Menu {
                Button(role: .destructive) {
                    pendingRemoveFriend = friend
                } label: {
                    Label("Unfriend", systemImage: "person.badge.minus")
                }

                Button(role: .destructive) {
                    pendingBlock = friend
                } label: {
                    Label("Block", systemImage: "hand.raised.fill")
                }

                Button {
                    reportTarget = .user(friend)
                } label: {
                    Label("Report", systemImage: "flag.fill")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
    }

    private func removeFriend(_ friend: AppUser) {
        let previousFriends = appState.friends
        // Optimistically drop the friend. The displayed count is derived from
        // appState.friends (live via the friends listener), so this is the
        // single source of truth — no separate server `friendCount` read,
        // which used to pop the counter back up before the onFriendDeleted
        // Cloud Function had decremented it.
        withAnimation(.easeInOut(duration: 0.2)) {
            appState.friends.removeAll { $0.id == friend.id }
        }
        Task {
            let ok = await FirebaseService.shared.removeFriend(friendUID: friend.id)
            if ok {
                // Refresh only to keep the server-backed friend limit fresh.
                await appState.refreshFriendCap()
            } else {
                withAnimation(.easeInOut(duration: 0.2)) {
                    appState.friends = previousFriends
                }
                unfriendErrorMessage = "We couldn't remove \(friend.firstName). Check your connection and try again."
            }
        }
    }

    // MARK: - Share link section

    private var shareLinkSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Share your RIFF link", icon: "square.and.arrow.up")

            shareRow(icon: "message.fill", color: .green, title: "Messages") {
                prepareMessageInvite(numbers: [], id: "messages")
            }

            Divider().background(Color.white.opacity(0.06)).padding(.leading, 62)

            shareRow(icon: "square.and.arrow.up", color: .gray, title: "Other apps") {
                prepareShareInvite()
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
        let requested = appState.outgoingRequestUIDs.contains(user.id)

        return HStack(spacing: 14) {
            AppUserAvatar(user: user, size: 38, background: Color.white.opacity(0.12))

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
            } else if requested {
                Button {
                    Task { await appState.cancelOutgoingRequest(to: user) }
                } label: {
                    Text("Requested")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.12))
                        .clipShape(.capsule)
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    Task { await appState.sendFriendRequest(to: user) }
                } label: {
                    addButtonLabel("Add")
                }
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Incoming friend requests

    private var friendRequestsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Friend Requests", icon: "person.crop.circle.badge.plus")

            LazyVStack(spacing: 0) {
                ForEach(appState.incomingRequests) { user in
                    friendRequestRow(user)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func friendRequestRow(_ user: AppUser) -> some View {
        HStack(spacing: 14) {
            AppUserAvatar(user: user, size: 38, background: Color.white.opacity(0.12))

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName(for: user))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
                if !user.username.isEmpty {
                    Text("@\(user.username)")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }

            Spacer()

            HStack(spacing: 8) {
                let atCap = appState.isAtFriendCap
                Button {
                    Task { await appState.acceptFriendRequest(user) }
                } label: {
                    Text(atCap ? "Full" : "Accept")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(atCap ? .white : .black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background {
                            if atCap {
                                Color.white.opacity(0.15)
                            } else {
                                AppAccentGradient.button
                            }
                        }
                        .clipShape(.capsule)
                }
                .buttonStyle(.plain)
                .disabled(atCap)

                Button {
                    Task { await appState.declineFriendRequest(user) }
                } label: {
                    Text("Decline")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.08))
                        .clipShape(.capsule)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Sent (outgoing) friend requests

    private var sentRequestsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Sent Requests", icon: "checkmark.circle")

            LazyVStack(spacing: 0) {
                ForEach(appState.outgoingRequests) { user in
                    sentRequestRow(user)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func sentRequestRow(_ user: AppUser) -> some View {
        HStack(spacing: 14) {
            AppUserAvatar(user: user, size: 38, background: Color.white.opacity(0.12))

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName(for: user))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
                Text("Request sent")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.4))
            }

            Spacer()

            HStack(spacing: 8) {
                Button {
                    Task { await appState.sendFriendRequest(to: user) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                Button {
                    Task { await appState.cancelOutgoingRequest(to: user) }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
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

            if isInvited(contact) {
                invitedTrailing(contact)
            } else {
                Button {
                    prepareMessageInvite(numbers: [contact.phoneNumber], id: contact.id, contact: contact)
                } label: {
                    if preparingInviteID == contact.id {
                        ProgressView()
                            .tint(.black)
                            .frame(width: 62, height: 28)
                            .background(AppAccentGradient.button)
                            .clipShape(.capsule)
                    } else {
                        addButtonLabel("Invite")
                    }
                }
                .disabled(preparingInviteID != nil)
            }
        }
        .padding(.vertical, 8)
    }

    /// "Invited" status pill + an undo (X) control, shared by the Invited
    /// section and any contact row that's already been invited.
    private func invitedTrailing(_ contact: SimpleContact) -> some View {
        HStack(spacing: 8) {
            Text("Invited")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.08))
                .clipShape(.capsule)

            Button {
                undoInvite(contact)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Undo invite to \(contact.fullName)")
        }
    }

    private var invitedSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Invited", icon: "paperplane.fill")

            LazyVStack(spacing: 0) {
                ForEach(appState.invitedContacts) { contact in
                    invitedContactRow(contact)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func invitedContactRow(_ contact: SimpleContact) -> some View {
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

            invitedTrailing(contact)
        }
        .padding(.vertical, 8)
    }

    private func prepareMessageInvite(numbers: [String], id: String, contact: SimpleContact? = nil) {
        guard preparingInviteID == nil else { return }
        preparingInviteID = id
        invitingContact = contact
        Task {
            let body = await buildFreshInviteBody()
            messageRecipient = MessageRecipient(numbers: numbers, body: body)
            preparingInviteID = nil
        }
    }

    /// Records a contact as invited once their SMS compose reports `.sent`,
    /// so it surfaces in the Invited section and the row flips to "Invited".
    private func recordInviteIfSent(_ result: MessageComposeResult) {
        defer { invitingContact = nil }
        guard result == .sent, let contact = invitingContact else { return }
        if !isInvited(contact) {
            withAnimation(.easeInOut(duration: 0.2)) {
                appState.invitedContacts.append(contact)
            }
        }
    }

    private func isInvited(_ contact: SimpleContact) -> Bool {
        appState.invitedContacts.contains {
            $0.id == contact.id
                || (!$0.phoneNumber.isEmpty && $0.phoneNumber == contact.phoneNumber)
        }
    }

    private func undoInvite(_ contact: SimpleContact) {
        withAnimation(.easeInOut(duration: 0.2)) {
            appState.invitedContacts.removeAll {
                $0.id == contact.id
                    || (!$0.phoneNumber.isEmpty && $0.phoneNumber == contact.phoneNumber)
            }
        }
    }

    private func prepareShareInvite() {
        guard preparingInviteID == nil else { return }
        preparingInviteID = "share"
        Task {
            let body = await buildFreshInviteBody()
            shareInvite = ShareInvite(body: body)
            preparingInviteID = nil
        }
    }

    private func buildFreshInviteBody() async -> String {
        guard let username = appState.currentUser?.username,
              Auth.auth().currentUser != nil,
              let invite = await DeepLinkService.shared.createPersonalInvite(for: username) else {
            return fallbackInviteBody
        }
        return "wanna do this? I have an extra invite code \(invite.code) — \(invite.shortURL)"
    }

    private func addButtonLabel(_ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .bold))
            Text(text)
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(.black)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(AppAccentGradient.button)
        .clipShape(.capsule)
    }

    private func friendRequestToastView(message: String, isError: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
            Text(message)
                .font(.system(size: 13, weight: .medium))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            isError
                ? AnyShapeStyle(Color(red: 0.78, green: 0.22, blue: 0.22).opacity(0.95))
                : AnyShapeStyle(AppAccentGradient.bubble.opacity(0.95))
        )
        .clipShape(.capsule)
        .padding(.top, 50)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func displayName(for user: AppUser) -> String {
        let last = user.lastName.trimmingCharacters(in: .whitespaces)
        return last.isEmpty ? user.firstName : "\(user.firstName) \(last)"
    }

    // MARK: - Search

    /// Remove any delivered push notifications whose payload is tagged
    /// `data.type == "friend_request"`. Seeing this screen implies the user
    /// has satisfied the banner's intent, so leaving the notification in
    /// the notification center would be noise. Cloud Functions write the
    /// `type` key on every friend-request push, so this is a straight
    /// filter + removeDeliveredNotifications call.
    private func clearDeliveredFriendRequestNotifications() {
        UNUserNotificationCenter.current().getDeliveredNotifications { delivered in
            let ids = delivered
                .filter { ($0.request.content.userInfo["type"] as? String) == "friend_request" }
                .map { $0.request.identifier }
            guard !ids.isEmpty else { return }
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
        }
    }

    private func performSearch(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = (trimmed.hasPrefix("@") ? String(trimmed.dropFirst()) : trimmed).lowercased()
        guard !normalized.isEmpty else {
            searchResults = []
            isSearching = false
            return
        }
        isSearching = true
        showAllUsernameResults = false
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard searchText == query else { return }
            let results = await appState.searchAllUsers(query: normalized)
            searchResults = results
            isSearching = false
            // Hydrate outgoing request state so any previously-requested user
            // shows the "Requested" chip on first paint.
            await appState.hydrateOutgoingRequests(for: results.map { $0.id })
        }
    }
}

private struct MessageRecipient: Identifiable {
    let id = UUID()
    let numbers: [String]
    let body: String
}

private struct ShareInvite: Identifiable {
    let id = UUID()
    let body: String
}
