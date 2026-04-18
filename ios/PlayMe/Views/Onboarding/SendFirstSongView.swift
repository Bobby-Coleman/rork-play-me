import SwiftUI
import MessageUI

/// Onboarding "send your first song" screen (step 6). A single, collapsed flow:
///   1. Big search bar with a placeholder that auto-rotates between three
///      prompts every 3s (fades, stops the moment the user types).
///   2. Horizontal carousel that either
///        - shows live iTunes search results (debounced 300ms), or
///        - while the field is empty, auto-rotates every 5s through curated
///          "inspiration" vibe buckets (Top charts, Indie, Vintage rock,
///          2000s throwbacks) at 70% opacity so it's clearly aspirational.
///   3. Optional message field.
///   4. Friend/contact carousel (real friends + text-invited contacts).
///   5. Send.
///
/// Sends to real friends go through `AppState.sendSong`.
/// Sends to invited contacts are queued via `sendSongToPendingContact` and
/// delivered when that contact finishes their own signup.
struct SendFirstSongView: View {
    let appState: AppState
    let onContinue: () -> Void
    let onSkip: () -> Void
    let onReopenInvites: () -> Void

    // Search
    @State private var query: String = ""
    @State private var searchResults: [Song] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var searchFocused: Bool

    // Rotating placeholder
    @State private var placeholderIndex: Int = 0
    @State private var placeholderTimer: Timer?

    // Inspiration buckets
    @State private var inspirationBuckets: [InspirationBucket] = []
    @State private var inspirationIndex: Int = 0
    @State private var inspirationTimer: Timer?
    @State private var isLoadingInspiration = true

    // Selection / send state
    @State private var selectedSong: Song?
    @State private var note: String = ""
    @State private var selectedFriendIds: Set<String> = []
    @State private var selectedContactIds: Set<String> = []
    @State private var showSentAnimation = false
    @State private var isSending = false

    private let placeholders = [
        "search a song you've been into lately...",
        "search your favorite artist",
        "search a song that means something to you"
    ]

    private let seedBuckets: [InspirationBucket] = [
        InspirationBucket(id: "top", label: "Top charts", searchTerm: "top hits"),
        InspirationBucket(id: "indie", label: "Indie favorites", searchTerm: "indie rock"),
        InspirationBucket(id: "vintage", label: "Vintage rock", searchTerm: "classic rock"),
        InspirationBucket(id: "y2k", label: "2000s throwbacks", searchTerm: "2000s hits")
    ]

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespaces)
    }

    private var hasAnyRecipient: Bool {
        !appState.friends.isEmpty || !appState.invitedContacts.isEmpty
    }

    private var totalSelected: Int {
        selectedFriendIds.count + selectedContactIds.count
    }

    private var canSend: Bool {
        selectedSong != nil && totalSelected > 0 && hasAnyRecipient && !isSending
    }

    private var currentInspirationBucket: InspirationBucket? {
        guard !inspirationBuckets.isEmpty else { return nil }
        return inspirationBuckets[inspirationIndex % inspirationBuckets.count]
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                        .padding(.horizontal, 20)
                        .padding(.top, 16)

                    searchField
                        .padding(.horizontal, 20)
                        .padding(.top, 16)

                    carousel
                        .padding(.top, 16)

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
        .task {
            await loadInspiration()
        }
        .onAppear {
            startPlaceholderTimer()
            startInspirationTimer()
        }
        .onDisappear {
            placeholderTimer?.invalidate()
            placeholderTimer = nil
            inspirationTimer?.invalidate()
            inspirationTimer = nil
            searchTask?.cancel()
        }
        .onChange(of: query) { _, newValue in
            handleQueryChange(newValue)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Send your first song")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                Text("Pick a song, pick a friend, hit send. They'll get it on their home screen — even if they just got your invite and haven't joined yet.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineSpacing(2)
            }
            Spacer(minLength: 12)
            Button("Skip", action: onSkip)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    // MARK: - Search field (rotating placeholder overlay)

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))

            ZStack(alignment: .leading) {
                if query.isEmpty {
                    Text(placeholders[placeholderIndex])
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.35))
                        .lineLimit(1)
                        .id(placeholderIndex)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }

                TextField("", text: $query)
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                    .tint(.white)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                    .focused($searchFocused)
            }

            if !query.isEmpty {
                Button {
                    query = ""
                    searchResults = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.08))
        .clipShape(.rect(cornerRadius: 14))
        .animation(.easeInOut(duration: 0.35), value: placeholderIndex)
    }

    // MARK: - Carousel (live search OR inspiration)

    @ViewBuilder
    private var carousel: some View {
        if !trimmedQuery.isEmpty {
            searchResultsCarousel
        } else if isLoadingInspiration {
            HStack {
                Spacer()
                ProgressView().tint(.white.opacity(0.6))
                Spacer()
            }
            .frame(height: 200)
        } else if let bucket = currentInspirationBucket, !bucket.songs.isEmpty {
            inspirationCarousel(bucket)
        } else {
            emptyCarouselHint
        }
    }

    private var searchResultsCarousel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Results")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.5))
                if isSearching {
                    ProgressView().scaleEffect(0.6).tint(.white.opacity(0.5))
                }
                Spacer()
            }
            .padding(.horizontal, 20)

            if searchResults.isEmpty && !isSearching {
                Text("No results for \"\(trimmedQuery)\"")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.35))
                    .padding(.horizontal, 20)
                    .frame(height: 160, alignment: .leading)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(searchResults) { song in
                            songCard(song, inspiration: false)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
    }

    private func inspirationCarousel(_ bucket: InspirationBucket) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                Text(bucket.label.uppercased())
                    .font(.system(size: 12, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
            }
            .padding(.horizontal, 20)
            .id("inspiration-label-\(bucket.id)")
            .transition(.opacity)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(bucket.songs) { song in
                        songCard(song, inspiration: true)
                    }
                }
                .padding(.horizontal, 20)
            }
            .id("inspiration-scroll-\(bucket.id)")
            .transition(.opacity)
        }
        .animation(.easeInOut(duration: 0.45), value: bucket.id)
    }

    private var emptyCarouselHint: some View {
        HStack {
            Spacer()
            VStack(spacing: 10) {
                Image(systemName: "music.note")
                    .font(.system(size: 28))
                    .foregroundStyle(.white.opacity(0.18))
                Text("Start typing to find a song")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.35))
            }
            Spacer()
        }
        .frame(height: 180)
    }

    private func songCard(_ song: Song, inspiration: Bool) -> some View {
        let isSelected = selectedSong?.id == song.id
        let tileOpacity: Double = isSelected ? 1.0 : (inspiration ? 0.7 : 1.0)
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
            .opacity(tileOpacity)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }

    // MARK: - Note + friends

    private var noteField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Message")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
                .textCase(.uppercase)

            TextField("Send a note with the song?", text: $note)
                .font(.system(size: 14))
                .foregroundStyle(.white)
                .tint(.white)
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

    // MARK: - Bottom bar

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

    // MARK: - Rotation timers

    private func startPlaceholderTimer() {
        placeholderTimer?.invalidate()
        guard query.isEmpty else { return }
        placeholderTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            Task { @MainActor in
                guard query.isEmpty else { return }
                withAnimation(.easeInOut(duration: 0.35)) {
                    placeholderIndex = (placeholderIndex + 1) % placeholders.count
                }
            }
        }
    }

    private func startInspirationTimer() {
        inspirationTimer?.invalidate()
        // Don't auto-rotate once the user has selected a song — let the screen
        // settle while they pick recipients.
        guard selectedSong == nil else { return }
        inspirationTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            Task { @MainActor in
                guard selectedSong == nil,
                      query.isEmpty,
                      !inspirationBuckets.isEmpty else { return }
                withAnimation(.easeInOut(duration: 0.45)) {
                    inspirationIndex = (inspirationIndex + 1) % inspirationBuckets.count
                }
            }
        }
    }

    private func pauseInspirationRotation() {
        inspirationTimer?.invalidate()
        inspirationTimer = nil
    }

    // MARK: - Query + search

    private func handleQueryChange(_ newValue: String) {
        let trimmed = newValue.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            searchTask?.cancel()
            searchResults = []
            isSearching = false
            // Resume placeholder rotation on clear. Inspiration only resumes
            // if no song is selected yet — we don't want to jitter the screen
            // under the user's feet once they've picked.
            startPlaceholderTimer()
        } else {
            // Stop placeholder rotation; the user is driving.
            placeholderTimer?.invalidate()
            placeholderTimer = nil
            performSearch(trimmed)
        }
    }

    private func performSearch(_ term: String) {
        searchTask?.cancel()
        isSearching = true
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            if Task.isCancelled { return }
            do {
                let songs = try await MusicSearchService.shared.search(term: term, limit: 20)
                if Task.isCancelled { return }
                await MainActor.run {
                    self.searchResults = songs
                    self.isSearching = false
                }
            } catch {
                await MainActor.run {
                    self.searchResults = []
                    self.isSearching = false
                }
            }
        }
    }

    // MARK: - Inspiration load

    private func loadInspiration() async {
        let loaded = await withTaskGroup(of: (String, [Song]).self) { group in
            for bucket in seedBuckets {
                group.addTask {
                    let songs = (try? await MusicSearchService.shared.search(
                        term: bucket.searchTerm,
                        limit: 10
                    )) ?? []
                    return (bucket.id, songs)
                }
            }
            var out: [String: [Song]] = [:]
            for await (id, songs) in group {
                out[id] = songs
            }
            return out
        }

        let filled = seedBuckets.compactMap { bucket -> InspirationBucket? in
            let songs = loaded[bucket.id] ?? []
            guard !songs.isEmpty else { return nil }
            return InspirationBucket(
                id: bucket.id,
                label: bucket.label,
                searchTerm: bucket.searchTerm,
                songs: songs
            )
        }

        await MainActor.run {
            self.inspirationBuckets = filled
            self.isLoadingInspiration = false
            // If the timer was already running, it will just pick up the new
            // buckets; if not (e.g. first load finished after onAppear), kick
            // it off now.
            if self.inspirationTimer == nil {
                self.startInspirationTimer()
            }
        }
    }

    // MARK: - Actions

    private func selectSong(_ song: Song) {
        selectedSong = song
        // Once they pick, stop rotating the inspiration carousel so the
        // selected tile doesn't slide out from under them.
        pauseInspirationRotation()
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

// MARK: - Inspiration bucket

/// Curated "vibe" bucket shown in the pre-search carousel. We intentionally
/// use iTunes search terms instead of the Apple RSS charts feed — the feed
/// lacks preview URLs, which would force a second per-song lookup to make
/// tiles playable/sendable. Search-term buckets deliver the same feel with
/// the network surface we already have.
private struct InspirationBucket: Identifiable {
    let id: String
    let label: String
    let searchTerm: String
    var songs: [Song] = []
}
