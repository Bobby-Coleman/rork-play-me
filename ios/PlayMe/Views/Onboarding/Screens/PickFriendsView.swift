import SwiftUI
import MessageUI
import Contacts
import FirebaseAuth
import UIKit

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
    @State private var showAllSuggestions = false
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

    private let suggestionPreviewCount = 3

    private var displayedSuggestions: [AppUser] {
        showAllSuggestions ? suggestedUsers : Array(suggestedUsers.prefix(suggestionPreviewCount))
    }

    private var hasMoreSuggestions: Bool {
        !showAllSuggestions && suggestedUsers.count > suggestionPreviewCount
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

    /// While searching (field focused or query present), collapse the slot
    /// meter + external-share row so results get the full viewport height and
    /// aren't pinned behind a tall header when the keyboard is up.
    private var searchActive: Bool {
        searchFocused || !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
                    if !searchActive {
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
                        .transition(.opacity)

                        InviteSlotRow(items: slotItems, limit: friendLimit)
                            .transition(.opacity)
                    }

                    searchBar

                    if !searchActive {
                        externalShareRow
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 4)
                .animation(.spring(response: 0.38, dampingFraction: 0.9), value: searchActive)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if !searchActive && suggestedUsers.isEmpty && appState.isLoadingContactSuggestions {
                            sectionHeader("Suggestions", icon: "sparkles")
                                .padding(.top, 16)
                            HStack(spacing: 10) {
                                ProgressView()
                                    .tint(Color.white.opacity(0.66))
                                    .scaleEffect(0.85)
                                Text("Finding friends from your contacts…")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Color.white.opacity(0.5))
                            }
                            .padding(.vertical, 12)
                            Divider().background(theme.border)
                                .padding(.vertical, 12)
                        } else if !searchActive && !suggestedUsers.isEmpty {
                            sectionHeader("Suggestions", icon: "sparkles")
                                .padding(.top, 16)
                            ForEach(displayedSuggestions) { user in
                                suggestionRow(user, pinned: user.id == appState.inviteSuggestedUser?.id)
                                Divider().background(theme.border)
                            }
                            if hasMoreSuggestions {
                                showMoreSuggestionsButton
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
                    .padding(.bottom, 24)
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
            // Run the contact match concurrently with the friend refreshes
            // instead of after them, so suggestions aren't gated behind two
            // sequential round-trips. The match itself is deduped/prefetched
            // in AppState, so this usually resolves instantly here.
            async let suggestions: Void = appState.refreshContactSuggestions(from: contacts)
            await appState.refreshFriends()
            await appState.refreshFriendRequests()
            await suggestions
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
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color.white.opacity(0.82))
                    .font(.system(size: 16, weight: .semibold))
                AppTextField("Search contacts", text: $search, submitLabel: .search) {
                    searchFocused = false
                }
                .foregroundStyle(.white)
                .font(.system(size: 17, weight: .semibold))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($searchFocused)
            }
            .padding(.horizontal, 18)
            .frame(height: 58)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.white.opacity(0.14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    )
                    .shadow(color: Color.white.opacity(0.05), radius: 16, y: 6)
            )

            if searchActive {
                Button(action: exitSearch) {
                    Text("Cancel")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(theme.fg)
                }
                .buttonStyle(.plain)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
    }

    private var externalShareRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Share your link with friends", icon: "square.and.arrow.up")
                .padding(.bottom, 0)

            HStack(spacing: 14) {
                shareSourceButton(
                    title: "Messages",
                    systemImage: "message.fill",
                    tint: Color(red: 0.20, green: 0.78, blue: 0.35),
                    isLoading: preparingInviteID == "messages"
                ) {
                    prepareMessageInvite(contact: nil, id: "messages")
                }

                Spacer(minLength: 0)
            }
        }
        .padding(.top, 2)
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

    private var showMoreSuggestionsButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { showAllSuggestions = true }
        } label: {
            Text("Show more (\(suggestedUsers.count - suggestionPreviewCount))")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(theme.sub)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
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
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.66))
            Text(title.uppercased())
                .font(.system(size: 12, weight: .bold))
                .tracking(0.7)
                .foregroundStyle(Color.white.opacity(0.66))
        }
        .padding(.bottom, 8)
    }

    private func shareSourceButton(
        title: String,
        systemImage: String,
        tint: Color,
        isLoading: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(tint)
                        .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1))
                        .frame(width: 58, height: 58)
                        .shadow(color: tint.opacity(0.35), radius: 14, y: 6)

                    if isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: systemImage)
                            .font(.system(size: 23, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }

                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.82))
            }
            .frame(width: 76)
        }
        .buttonStyle(.plain)
        .disabled(preparingInviteID != nil)
        .opacity(preparingInviteID != nil && !isLoading ? 0.45 : 1)
    }

    private func suggestionRow(_ user: AppUser, pinned: Bool) -> some View {
        let slotFull = slotItems.count >= friendLimit

        return HStack(spacing: 12) {
            UserAvatar(user: user, side: 42, inverted: true)

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
                exitSearch()
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
            UserAvatar(user: user, side: 38)

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
                    exitSearch()
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
            ContactAvatar(contact: contact, side: 38)

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
                    statusPill("Added")
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
                        actionPill("Add", disabled: limitReached)
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
        .foregroundStyle(disabled ? Color.white.opacity(0.30) : Color.black)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(disabled ? Color.white.opacity(0.08) : Color.white)
                .overlay(Capsule().stroke(Color.white.opacity(disabled ? 0.08 : 0.22), lineWidth: 1))
                .shadow(color: disabled ? .clear : Color.white.opacity(0.10), radius: 10, y: 4)
        )
    }

    private func statusPill(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.64))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.08))
                    .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 1))
            )
    }

    /// Returns the screen from search mode back to the default slots/circles
    /// view (clears the query + unfocuses, which un-collapses the header). Used
    /// after an add so the newly added person shows up in the circles.
    private func exitSearch() {
        search = ""
        searchResults = []
        searchTask?.cancel()
        isSearching = false
        searchFocused = false
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
        exitSearch()
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

    var thumbnailData: Data? {
        switch self {
        case .user: return nil
        case .contact(let contact, _): return contact.thumbnailData
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
            SlotAvatar(item: item, side: 58)
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
            Text("Not added")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(theme.faint)
        }
        .frame(width: 76)
    }
}

// MARK: - Avatars

private struct UserAvatar: View {
    let user: AppUser
    let side: CGFloat
    var inverted: Bool = false
    @Environment(\.riffTheme) private var theme

    var body: some View {
        Text(user.initials)
            .font(.system(size: side > 40 ? 13 : 12, weight: .bold))
            .foregroundStyle(inverted ? theme.bg : theme.fg)
            .frame(width: side, height: side)
            .background(
                Circle()
                    .fill(inverted ? theme.fg : Color.white.opacity(0.08))
                    .overlay(Circle().stroke(Color.white.opacity(0.10), lineWidth: 1))
            )
    }
}

private struct ContactAvatar: View {
    let contact: SimpleContact
    let side: CGFloat
    @Environment(\.riffTheme) private var theme

    var body: some View {
        Group {
            if let data = contact.thumbnailData,
               let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Circle().fill(Color.white.opacity(0.08))
                    Text(contact.initials.isEmpty ? "?" : contact.initials)
                        .font(.system(size: side > 40 ? 16 : 13, weight: .bold))
                        .foregroundStyle(theme.fg)
                }
            }
        }
        .frame(width: side, height: side)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
    }
}

private struct SlotAvatar: View {
    let item: InviteSlotItem
    let side: CGFloat
    @Environment(\.riffTheme) private var theme

    var body: some View {
        Group {
            if let data = item.thumbnailData,
               let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Circle().fill(theme.fg)
                    Text(item.initials)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(theme.bg)
                }
            }
        }
        .frame(width: side, height: side)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
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
