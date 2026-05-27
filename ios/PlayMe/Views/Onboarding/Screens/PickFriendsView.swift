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
    @State private var searchResults: [AppUser] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var inviteRecipient: OutgoingInvite?
    @State private var preparingInviteID: String?
    @State private var visibleContactCount: Int = 20
    @FocusState private var searchFocused: Bool

    @Environment(\.riffTheme) private var theme

    private let contactPageSize = 20

    private var fallbackInviteBody: String {
        "wanna do this? \(DeepLinkService.publicTestFlightInviteURL)"
    }

    private var friendLimit: Int {
        appState.friendCap?.limit ?? 8
    }

    private var orderedContacts: [SimpleContact] {
        let invitedIds = Set(appState.invitedContacts.map(\.id))
        return contacts.suggestedInviteOrder(prioritizedContactIds: invitedIds)
    }

    private var filteredContacts: [SimpleContact] {
        let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return orderedContacts }
        let q = (trimmed.hasPrefix("@") ? String(trimmed.dropFirst()) : trimmed).lowercased()
        return orderedContacts.filter {
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

    private var suggestedUsers: [AppUser] {
        let excluded = Set(
            appState.friends.map(\.id)
                + appState.outgoingRequests.map(\.id)
                + appState.onboardingRequestedUsers.map(\.id)
                + [appState.currentUser?.id].compactMap { $0 }
        )
        var seen = Set<String>()
        let ordered = [appState.inviteSuggestedUser].compactMap { $0 } + appState.contactSuggestedUsers
        return ordered.filter { user in
            !excluded.contains(user.id) && seen.insert(user.id).inserted
        }
    }

    private var slotItems: [InviteSlotItem] {
        var seen = Set<String>()
        var items: [InviteSlotItem] = []

        for friend in appState.friends where seen.insert("user-\(friend.id)").inserted {
            items.append(.user(friend, status: "Friend"))
        }
        for user in appState.outgoingRequests + appState.onboardingRequestedUsers where seen.insert("user-\(user.id)").inserted {
            items.append(.user(user, status: "Requested"))
        }
        for contact in appState.invitedContacts where seen.insert("contact-\(contact.id)").inserted {
            items.append(.contact(contact, status: "Invited"))
        }
        return Array(items.prefix(friendLimit))
    }

    private var canContinue: Bool {
        !slotItems.isEmpty
    }

    var body: some View {
        RiffScreenChrome(
            stepIdx: stepIdx,
            totalSteps: totalSteps,
            onBack: onBack,
            horizontalPadding: 0
        ) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Invite your \(friendLimit) favorite people")
                                .font(.system(size: 24, weight: .semibold))
                                .tracking(-0.48)
                                .foregroundStyle(theme.fg)
                            Spacer()
                            Counter(count: slotItems.count, limit: friendLimit)
                        }
                        Text("\(max(friendLimit - slotItems.count, 0)) invites left. Add someone now so you can send your first song right away.")
                            .font(.system(size: 13))
                            .foregroundStyle(theme.sub)
                            .lineSpacing(2)
                    }
                    InviteSlotRow(items: slotItems, limit: friendLimit)

                    inviteViaMessagesButton
                    searchBar
                }
                .padding(.horizontal, 24)
                .padding(.top, 4)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if !suggestedUsers.isEmpty {
                            sectionHeader("Suggestions", icon: "sparkles")
                                .padding(.top, 16)
                            ForEach(suggestedUsers) { user in
                                suggestionRow(user, pinned: user.id == appState.inviteSuggestedUser?.id)
                                Divider().background(theme.border)
                            }
                            Divider().background(theme.border)
                                .padding(.vertical, 12)
                        }

                        if search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            contactsContent
                        } else {
                            searchContent
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        } footer: {
            RiffPrimaryButton(
                title: "Continue",
                disabled: !canContinue,
                action: onContinue
            )
        }
        .task {
            await appState.refreshFriends()
            await appState.refreshFriendRequests()
            await appState.refreshContactSuggestions(from: contacts)
        }
        .onChange(of: contacts) { _, newContacts in
            Task { await appState.refreshContactSuggestions(from: newContacts) }
        }
        .sheet(item: $inviteRecipient) { invite in
            if MessageComposeView.canSendText {
                MessageComposeView(
                    recipients: invite.contact.phoneNumber.isEmpty ? [] : [invite.contact.phoneNumber],
                    body: invite.body
                ) { result in
                    handleComposeResult(result, for: invite.contact)
                }
                .ignoresSafeArea()
            }
        }
        .onChange(of: search) { _, _ in
            visibleContactCount = contactPageSize
            performSearch(search)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(theme.faint)
                .font(.system(size: 14))
            AppTextField("Search username or contacts", text: $search, submitLabel: .search) {
                searchFocused = false
            }
            .foregroundStyle(theme.fg)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .focused($searchFocused)
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(theme.softBg)
        )
    }

    private var inviteViaMessagesButton: some View {
        Button {
            prepareMessageInvite(contact: nil, id: "messages")
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.green)
                        .frame(width: 42, height: 42)
                    Image(systemName: "message.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Invite via iMessage")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(theme.bg)
                    Text("Sends your one-use invite code and link")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.bg.opacity(0.72))
                }

                Spacer()

                if preparingInviteID == "messages" {
                    ProgressView()
                        .tint(theme.bg)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(theme.bg.opacity(0.55))
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(theme.fg)
            )
        }
        .buttonStyle(.plain)
        .disabled(preparingInviteID != nil)
    }

    @ViewBuilder
    private var contactsContent: some View {
        sectionHeader("Add your contacts", icon: "person.crop.rectangle.stack")
            .padding(.top, 16)

        if contacts.isEmpty {
            Text("Contacts access is off. Use iMessage above or search by username.")
                .font(.system(size: 13))
                .foregroundStyle(theme.sub)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 24)
                .padding(.horizontal, 8)
        } else {
            ForEach(displayedContacts) { contact in
                row(for: contact)
                Divider().background(theme.border)
            }
            seeMoreButton
        }
    }

    @ViewBuilder
    private var searchContent: some View {
        if isSearching {
            sectionHeader("Add by username", icon: "at")
                .padding(.top, 16)
            ProgressView()
                .tint(theme.fg)
                .frame(maxWidth: .infinity)
                .padding(.top, 18)
        } else if !searchResults.isEmpty {
            sectionHeader("Add by username", icon: "at")
                .padding(.top, 16)
            ForEach(searchResults) { user in
                userRow(user)
                Divider().background(theme.border)
            }
        }

        if !filteredContacts.isEmpty {
            sectionHeader("Matching contacts", icon: "person.crop.rectangle.stack")
                .padding(.top, searchResults.isEmpty ? 16 : 24)
            ForEach(displayedContacts) { contact in
                row(for: contact)
                Divider().background(theme.border)
            }
            seeMoreButton
        }

        if !isSearching && searchResults.isEmpty && filteredContacts.isEmpty {
            Text("No results found")
                .font(.system(size: 14))
                .foregroundStyle(theme.faint)
                .frame(maxWidth: .infinity)
                .padding(.top, 24)
        }
    }

    @ViewBuilder
    private var seeMoreButton: some View {
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

    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.faint)
            Text(title.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.7)
                .foregroundStyle(theme.faint)
        }
        .padding(.bottom, 8)
    }

    private func suggestionRow(_ user: AppUser, pinned: Bool) -> some View {
        let slotFull = slotItems.count >= friendLimit

        return HStack(spacing: 12) {
            Text(user.initials)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(theme.bg)
                .frame(width: 42, height: 42)
                .background(Circle().fill(theme.fg))

            VStack(alignment: .leading, spacing: 2) {
                Text(user.firstName.isEmpty ? "@\(user.username)" : user.firstName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.fg)
                Text(pinned ? "Sent you the invite" : "Already on Riff")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.sub)
            }

            Spacer()

            Button {
                guard !slotFull else { return }
                Task { await appState.sendFriendRequest(to: user) }
            } label: {
                actionPill("Add", disabled: slotFull)
            }
            .buttonStyle(.plain)
            .disabled(slotFull)
        }
        .padding(.vertical, 12)
        .opacity(slotFull ? 0.45 : 1)
    }

    private func userRow(_ user: AppUser) -> some View {
        let alreadyFriend = appState.friends.contains(where: { $0.id == user.id })
        let requested = appState.outgoingRequestUIDs.contains(user.id)
        let slotFull = !requested && !alreadyFriend && slotItems.count >= friendLimit

        return HStack(spacing: 12) {
            Text(user.initials)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(theme.fg)
                .frame(width: 38, height: 38)
                .background(Circle().fill(theme.softBg))

            VStack(alignment: .leading, spacing: 2) {
                Text(user.firstName)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(theme.fg)
                Text("@\(user.username)")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.faint)
            }

            Spacer(minLength: 8)

            if alreadyFriend {
                statusPill("Friend")
            } else if requested {
                Button {
                    Task { await appState.cancelOutgoingRequest(to: user) }
                } label: {
                    statusPill("Requested")
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    guard !slotFull else { return }
                    Task { await appState.sendFriendRequest(to: user) }
                } label: {
                    actionPill("Add", disabled: slotFull)
                }
                .buttonStyle(.plain)
                .disabled(slotFull)
            }
        }
        .padding(.vertical, 12)
        .opacity(slotFull ? 0.45 : 1)
    }

    private func row(for contact: SimpleContact) -> some View {
        let invited = appState.invitedContacts.contains(where: { $0.id == contact.id })
        let limitReached = !invited && slotItems.count >= friendLimit
        let isPreparing = preparingInviteID == contact.id

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
                    statusPill("Invited")
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    guard !limitReached else { return }
                    prepareMessageInvite(contact: contact, id: contact.id)
                } label: {
                    if isPreparing {
                        ProgressView()
                            .tint(theme.fg)
                            .frame(width: 58, height: 30)
                    } else {
                        actionPill("Invite", disabled: limitReached)
                    }
                }
                .buttonStyle(.plain)
                .disabled(limitReached || preparingInviteID != nil)
            }
        }
        .padding(.vertical, 12)
        .opacity(limitReached && !invited ? 0.45 : 1)
    }

    private func actionPill(_ title: String, disabled: Bool = false) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .bold))
            Text(title)
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(disabled ? theme.faint : theme.bg)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Capsule().fill(disabled ? theme.softBg : theme.fg))
    }

    private func statusPill(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(theme.sub)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(theme.softBg))
    }

    private func prepareMessageInvite(contact: SimpleContact?, id: String) {
        guard preparingInviteID == nil else { return }
        preparingInviteID = id
        Task {
            let body = await buildFreshInviteBody()
            if let contact {
                inviteRecipient = OutgoingInvite(contact: contact, body: body)
            } else {
                inviteRecipient = OutgoingInvite(contact: SimpleContact(id: "manual-\(UUID().uuidString)", firstName: "", lastName: "", phoneNumber: ""), body: body)
            }
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

    private func handleComposeResult(_ result: MessageComposeResult, for contact: SimpleContact) {
        inviteRecipient = nil
        guard result == .sent else { return }
        guard !contact.phoneNumber.isEmpty else { return }
        if !appState.invitedContacts.contains(where: { $0.id == contact.id }) {
            appState.invitedContacts.append(contact)
        }
    }

    private func performSearch(_ text: String) {
        searchTask?.cancel()
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            searchResults = []
            isSearching = false
            return
        }

        isSearching = true
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            let results = await appState.searchAllUsers(query: normalized)
            guard !Task.isCancelled else { return }
            searchResults = results
            isSearching = false
            await appState.hydrateOutgoingRequests(for: results.map { $0.id })
        }
    }
}

// MARK: - Visual invite slots

private enum InviteSlotItem: Identifiable {
    case user(AppUser, status: String)
    case contact(SimpleContact, status: String)

    var id: String {
        switch self {
        case .user(let user, _): return "user-\(user.id)"
        case .contact(let contact, _): return "contact-\(contact.id)"
        }
    }

    var label: String {
        switch self {
        case .user(let user, _):
            return user.firstName.isEmpty ? user.username : user.firstName
        case .contact(let contact, _):
            return contact.firstName.isEmpty ? contact.phoneNumber : contact.firstName
        }
    }

    var initials: String {
        switch self {
        case .user(let user, _): return user.initials
        case .contact(let contact, _): return contact.initials.isEmpty ? "?" : contact.initials
        }
    }

    var status: String {
        switch self {
        case .user(_, let status), .contact(_, let status): return status
        }
    }
}

private struct InviteSlotRow: View {
    let items: [InviteSlotItem]
    let limit: Int
    @Environment(\.riffTheme) private var theme

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 18) {
                ForEach(0..<limit, id: \.self) { index in
                    if index < items.count {
                        filledSlot(items[index])
                    } else {
                        emptySlot
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func filledSlot(_ item: InviteSlotItem) -> some View {
        VStack(spacing: 7) {
            Text(item.initials)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(theme.bg)
                .frame(width: 58, height: 58)
                .background(Circle().fill(theme.fg))
            Text(item.label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.fg)
                .lineLimit(1)
            Text(item.status)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(theme.faint)
                .lineLimit(1)
        }
        .frame(width: 76)
    }

    private var emptySlot: some View {
        VStack(spacing: 7) {
            Circle()
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                .foregroundStyle(theme.faint)
                .frame(width: 58, height: 58)
            Text("Open")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.faint)
            Text("Not invited")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(theme.faint)
        }
        .frame(width: 76)
    }
}

// MARK: - Counter + meter

private struct Counter: View {
    let count: Int
    var limit: Int = 8
    @State private var bounceKey: Int = 0
    @Environment(\.riffTheme) private var theme

    var body: some View {
        Text("\(count)/\(limit)")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(theme.fg)
            .scaleEffect(bounceKey % 2 == 0 ? 1 : 1.18)
            .animation(.spring(response: 0.32, dampingFraction: 0.6), value: bounceKey)
            .onChange(of: count) { _, _ in bounceKey += 1 }
    }
}

private struct Meter: View {
    let count: Int
    var limit: Int = 8
    @Environment(\.riffTheme) private var theme

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<limit, id: \.self) { i in
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
    let body: String
}
