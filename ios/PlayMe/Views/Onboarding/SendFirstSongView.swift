import SwiftUI
import MessageUI

/// Onboarding step 8 — the payoff screen. The user:
///   1. Picks one of ~10 auto-suggested songs (or taps "Search any song") based on
///      the favorite artists + recent-listening inputs from the prior two steps.
///   2. Types an optional message.
///   3. Selects one or more friends from a horizontal carousel (union of real
///      friends + contacts they text-invited on step 5).
///   4. Taps Send.
///
/// Sends to real friends go through `AppState.sendSong` (existing path).
/// Sends to invited contacts are queued via `AppState.sendSongToPendingContact`
/// and delivered the moment that contact finishes their own signup.
struct SendFirstSongView: View {
    let appState: AppState
    let onContinue: () -> Void
    let onSkip: () -> Void
    let onReopenInvites: () -> Void

    @State private var suggestions: [Song] = []
    @State private var isLoadingSuggestions = true
    @State private var selectedSong: Song?
    @State private var note: String = ""

    @State private var selectedFriendIds: Set<String> = []
    @State private var selectedContactIds: Set<String> = []

    @State private var showSearchSheet = false
    @State private var showSentAnimation = false
    @State private var isSending = false

    private var hasAnyRecipient: Bool {
        !appState.friends.isEmpty || !appState.invitedContacts.isEmpty
    }

    private var totalSelected: Int {
        selectedFriendIds.count + selectedContactIds.count
    }

    private var canSend: Bool {
        selectedSong != nil && totalSelected > 0 && hasAnyRecipient && !isSending
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                        .padding(.horizontal, 20)
                        .padding(.top, 16)

                    songCarousel
                        .padding(.top, 20)

                    searchAnySongButton
                        .padding(.horizontal, 20)
                        .padding(.top, 12)

                    noteField
                        .padding(.horizontal, 20)
                        .padding(.top, 20)

                    friendsSection
                        .padding(.top, 20)

                    Color.clear.frame(height: 120)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomBar
            }

            if showSentAnimation {
                sentOverlay
            }

            VStack {
                if let err = appState.queuedContactError {
                    feedbackBanner(text: err, isError: true)
                        .transition(.move(edge: .top).combined(with: .opacity))
                } else if let toast = appState.queuedContactToast {
                    feedbackBanner(text: toast, isError: false)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                Spacer()
            }
            .padding(.top, 8)
            .animation(.spring(duration: 0.3), value: appState.queuedContactError)
            .animation(.spring(duration: 0.3), value: appState.queuedContactToast)
        }
        .animation(.spring(duration: 0.3), value: showSentAnimation)
        .sheet(isPresented: $showSearchSheet) {
            SongSearchPickerSheet(appState: appState) { picked in
                selectSong(picked)
                showSearchSheet = false
            }
        }
        .task {
            await loadSuggestions()
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Send your first song")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
                Button("Skip", action: onSkip)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
            }

            Text("Pick a song, pick a friend, hit send. They'll get it on their home screen — even if they just got your invite and haven't joined yet.")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.5))
                .lineSpacing(2)
        }
    }

    private var songCarousel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Suggestions for you")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
                .textCase(.uppercase)
                .padding(.horizontal, 20)

            if isLoadingSuggestions {
                HStack {
                    Spacer()
                    ProgressView()
                        .tint(.white.opacity(0.6))
                    Spacer()
                }
                .frame(height: 160)
            } else if suggestions.isEmpty {
                Text("Tap \"Search any song\" below to pick one.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.horizontal, 20)
                    .frame(height: 160, alignment: .leading)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(suggestions) { song in
                            songCard(song)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
    }

    private func songCard(_ song: Song) -> some View {
        let isSelected = selectedSong?.id == song.id
        return Button {
            selectSong(song)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    AsyncImage(url: URL(string: song.albumArtURL)) { phase in
                        if let image = phase.image {
                            image.resizable().aspectRatio(contentMode: .fill)
                        } else {
                            Color.white.opacity(0.1)
                        }
                    }
                    .frame(width: 140, height: 140)
                    .clipShape(.rect(cornerRadius: 10))

                    if isSelected {
                        ZStack {
                            Circle()
                                .fill(Color(red: 0.76, green: 0.38, blue: 0.35))
                                .frame(width: 26, height: 26)
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        .padding(8)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(
                            isSelected ? Color(red: 0.76, green: 0.38, blue: 0.35) : .clear,
                            lineWidth: 2
                        )
                )

                Text(song.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .frame(width: 140, alignment: .leading)

                Text(song.artist)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                    .frame(width: 140, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }

    private var searchAnySongButton: some View {
        Button {
            showSearchSheet = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Text("Don't see it? Search any song")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.08))
            .clipShape(.rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private var noteField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Message")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
                .textCase(.uppercase)

            TextField("Send a note with the song?", text: $note)
                .font(.system(size: 14))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.06))
                .clipShape(.rect(cornerRadius: 10))
                .onChange(of: note) { _, newValue in
                    if newValue.count > 150 { note = String(newValue.prefix(150)) }
                }
        }
    }

    private var friendsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Send to")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
                .textCase(.uppercase)
                .padding(.horizontal, 20)

            if !hasAnyRecipient {
                emptyFriendsCallout
                    .padding(.horizontal, 20)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 14) {
                        ForEach(appState.friends) { friend in
                            friendAvatar(friend)
                        }
                        ForEach(appState.invitedContacts) { contact in
                            contactAvatar(contact)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var emptyFriendsCallout: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("You haven't invited anyone yet")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
            Text("Go back and invite a few friends — you'll be able to send them a song right here, and they'll see it the moment they join.")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
                .lineSpacing(2)

            Button(action: onReopenInvites) {
                HStack(spacing: 8) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Invite friends")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(red: 0.76, green: 0.38, blue: 0.35))
                .clipShape(.capsule)
            }
            .padding(.top, 4)
        }
        .padding(14)
        .background(Color.white.opacity(0.06))
        .clipShape(.rect(cornerRadius: 12))
    }

    private func friendAvatar(_ friend: AppUser) -> some View {
        let isSelected = selectedFriendIds.contains(friend.id)
        return Button {
            toggleFriend(friend.id)
        } label: {
            VStack(spacing: 6) {
                ZStack(alignment: .bottomTrailing) {
                    Text(friend.initials)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 60, height: 60)
                        .background(Color.white.opacity(0.14))
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(
                                    isSelected ? Color(red: 0.76, green: 0.38, blue: 0.35) : .clear,
                                    lineWidth: 3
                                )
                        )

                    if isSelected {
                        ZStack {
                            Circle()
                                .fill(Color(red: 0.76, green: 0.38, blue: 0.35))
                                .frame(width: 22, height: 22)
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        .offset(x: 2, y: 2)
                    }
                }

                Text(friend.firstName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .frame(width: 70)
            }
        }
        .buttonStyle(.plain)
    }

    private func contactAvatar(_ contact: SimpleContact) -> some View {
        let isSelected = selectedContactIds.contains(contact.id)
        return Button {
            toggleContact(contact.id)
        } label: {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    Text(contact.initials.isEmpty ? "?" : contact.initials)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 60, height: 60)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(
                                    isSelected
                                        ? Color(red: 0.76, green: 0.38, blue: 0.35)
                                        : Color.white.opacity(0.2),
                                    style: StrokeStyle(
                                        lineWidth: isSelected ? 3 : 1,
                                        dash: isSelected ? [] : [3]
                                    )
                                )
                        )

                    Text("INVITED")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.25))
                        .clipShape(.capsule)
                        .offset(x: 2, y: -2)

                    if isSelected {
                        ZStack {
                            Circle()
                                .fill(Color(red: 0.76, green: 0.38, blue: 0.35))
                                .frame(width: 22, height: 22)
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        .offset(x: 4, y: 40)
                    }
                }

                Text(contact.firstName.isEmpty ? contact.phoneNumber : contact.firstName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
                    .frame(width: 70)
            }
        }
        .buttonStyle(.plain)
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            Button(action: send) {
                Text(sendLabel)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(canSend ? .white : .white.opacity(0.4))
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        canSend
                            ? Color(red: 0.76, green: 0.38, blue: 0.35)
                            : Color.white.opacity(0.1)
                    )
                    .clipShape(.rect(cornerRadius: 25))
            }
            .disabled(!canSend)

            Button("Skip for now", action: onSkip)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.4))
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.94))
    }

    private var sendLabel: String {
        if selectedSong == nil { return "Pick a song" }
        if totalSelected == 0 { return "Pick someone to send to" }
        return totalSelected == 1 ? "Send" : "Send to \(totalSelected)"
    }

    private var sentOverlay: some View {
        Color.black.opacity(0.85)
            .ignoresSafeArea()
            .overlay {
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.green)
                        .symbolEffect(.bounce, value: showSentAnimation)
                    Text("Sent!")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .transition(.opacity)
    }

    private func feedbackBanner(text: String, isError: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(isError ? .orange : .green)
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                )
        )
        .padding(.horizontal, 20)
    }

    // MARK: - Actions

    private func selectSong(_ song: Song) {
        selectedSong = song
        if !suggestions.contains(where: { $0.id == song.id }) {
            // Insert at the front so the manually-searched pick is visible in the carousel.
            suggestions.insert(song, at: 0)
        }
    }

    private func toggleFriend(_ id: String) {
        if selectedFriendIds.contains(id) {
            selectedFriendIds.remove(id)
        } else {
            selectedFriendIds.insert(id)
        }
    }

    private func toggleContact(_ id: String) {
        if selectedContactIds.contains(id) {
            selectedContactIds.remove(id)
        } else {
            selectedContactIds.insert(id)
        }
    }

    private func loadSuggestions() async {
        isLoadingSuggestions = true
        let picks = await SongSuggestionsService.shared.buildSuggestions(
            favoriteArtists: appState.favoriteArtists,
            recentArtist: appState.recentListeningArtist,
            recentSong: appState.recentListeningSong,
            limit: 10
        )
        suggestions = picks
        isLoadingSuggestions = false

        // If the user already has a "recently listening" song, preselect it.
        if selectedSong == nil, let rec = appState.recentListeningSong {
            selectedSong = rec
        }
    }

    private func send() {
        guard let song = selectedSong, canSend else { return }
        isSending = true
        showSentAnimation = true

        let friends = appState.friends.filter { selectedFriendIds.contains($0.id) }
        let contacts = appState.invitedContacts.filter { selectedContactIds.contains($0.id) }
        let noteToSend = note

        Task {
            for friend in friends {
                await appState.sendSong(song, to: friend, note: noteToSend)
            }
            for contact in contacts {
                _ = await appState.sendSongToPendingContact(song, contact: contact, note: noteToSend)
            }
            try? await Task.sleep(for: .seconds(1.2))
            isSending = false
            onContinue()
        }
    }
}

// MARK: - Song search sheet (shared-style with SendSongSheet)

/// Thin wrapper around iTunes search so the "search any song" path on the
/// first-send screen reuses the same UX as the main SendSongSheet.
private struct SongSearchPickerSheet: View {
    let appState: AppState
    let onPick: (Song) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText: String = ""
    @State private var results: [Song] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.white.opacity(0.4))
                        TextField("Search songs or artists", text: $searchText)
                            .foregroundStyle(.white)
                            .autocorrectionDisabled()
                            .focused($searchFocused)
                            .onChange(of: searchText) { _, newValue in
                                performSearch(newValue)
                            }

                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                                results = []
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.white.opacity(0.4))
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.08))
                    .clipShape(.rect(cornerRadius: 12))
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                    ScrollView {
                        LazyVStack(spacing: 0) {
                            if isSearching {
                                ProgressView()
                                    .tint(.white)
                                    .padding(.top, 48)
                            } else if results.isEmpty && !searchText.isEmpty {
                                Text("No results for \"\(searchText)\"")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.white.opacity(0.3))
                                    .padding(.top, 48)
                            } else {
                                ForEach(results) { song in
                                    Button {
                                        onPick(song)
                                    } label: {
                                        HStack(spacing: 12) {
                                            AsyncImage(url: URL(string: song.albumArtURL)) { phase in
                                                if let image = phase.image {
                                                    image.resizable().aspectRatio(contentMode: .fill)
                                                } else {
                                                    Color.white.opacity(0.1)
                                                }
                                            }
                                            .frame(width: 44, height: 44)
                                            .clipShape(.rect(cornerRadius: 5))

                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(song.title)
                                                    .font(.system(size: 15, weight: .semibold))
                                                    .foregroundStyle(.white)
                                                    .lineLimit(1)
                                                Text(song.artist)
                                                    .font(.system(size: 12))
                                                    .foregroundStyle(.white.opacity(0.5))
                                                    .lineLimit(1)
                                            }

                                            Spacer()

                                            Image(systemName: "plus.circle.fill")
                                                .font(.system(size: 20))
                                                .foregroundStyle(Color(red: 0.76, green: 0.38, blue: 0.35))
                                        }
                                        .padding(.vertical, 8)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .overlay(alignment: .bottom) {
                                        Color.white.opacity(0.05).frame(height: 0.5)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .presentationBackground(.black)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                searchFocused = true
            }
        }
    }

    private func performSearch(_ term: String) {
        searchTask?.cancel()
        let trimmed = term.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            results = []
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            do {
                let songs = try await MusicSearchService.shared.search(term: trimmed, limit: 25)
                if Task.isCancelled { return }
                await MainActor.run {
                    self.results = songs
                    self.isSearching = false
                }
            } catch {
                await MainActor.run {
                    self.results = []
                    self.isSearching = false
                }
            }
        }
    }
}
