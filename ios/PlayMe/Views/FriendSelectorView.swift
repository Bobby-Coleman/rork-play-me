import SwiftUI

/// Unified share view. The single destination for any "send this to a
/// friend" entry point in the app — songs from the feed/search/history,
/// whole albums from search results / album detail, and whole mixtapes
/// from the mixtape detail screen all flow through here. Variation
/// between the kinds is contained to the artwork strip, the
/// preview-controls row (songs only — albums and mixtapes can't be
/// auditioned as a single track), and the final dispatch in
/// `commitSend()`. Recipient selection, the note pill, and the Send
/// button work the same regardless of payload.
///
/// Pending-signup contacts (the `invitedContacts` parameter) only
/// receive songs today. Sending an album or mixtape to a still-invited
/// contact would require expanding the invite-redeem flow to fan-out
/// every song in the payload, which is out of scope for v1, so the
/// chip row hides invited contacts when the payload isn't a song.
struct FriendSelectorView: View {
    let item: Shareable
    let appState: AppState
    /// Pending-signup contacts to render alongside real friends. Only
    /// rendered when `item == .song`. See type doc for rationale.
    var invitedContacts: [SimpleContact] = []
    /// Share context when this view is acting as a song action
    /// destination (feed tap / history tap via `SongActionSheet`)
    /// rather than a pre-send surface. Threaded down to
    /// `openInServiceButton` so any resolution that fires writes back
    /// to `shares/{id}.song.spotifyURI`. `nil` means "no share yet"
    /// (the pre-send case) and writeback is correctly skipped.
    /// Only meaningful for `.song` payloads — albums and mixtapes use
    /// their own share collections.
    var shareId: String? = nil
    let onBack: () -> Void
    let onSent: () -> Void

    private var audioPlayer: AudioPlayerService { AudioPlayerService.shared }
    private var song: Song? { item.song }
    private var isCurrentSong: Bool {
        guard let song else { return false }
        return audioPlayer.currentSongId == song.id
    }
    private var isPlayingThis: Bool { isCurrentSong && audioPlayer.isPlaying }

    @State private var selectedFriends: Set<String> = []
    /// Parallel selection set for invited contacts. Lives alongside
    /// `selectedFriends` rather than merging into one set so we can
    /// route sends to the correct backend path (`sendSong` vs
    /// `sendSongToPendingContact`) without later disambiguation.
    @State private var selectedContacts: Set<String> = []
    @State private var note: String = ""
    @State private var showSentAnimation = false
    @State private var showAddFriends = false
    /// Drives the save-to-mixtape sheet. The kind of sheet rendered
    /// branches off `item.kind` — songs use `SaveToMixtapeSheet`,
    /// albums use `SaveAlbumToMixtapeSheet`. Mixtapes hide the save
    /// affordance entirely (saving a mixtape would mean duplicating
    /// every song into another mixtape, which we haven't designed).
    @State private var showSaveSheet: Bool = false
    /// Pre-resolved Spotify URL for the "Open in Spotify" button. Only
    /// resolved for `.song` payloads.
    @State private var resolvedSpotifyURL: String?
    @FocusState private var isNoteFocused: Bool

    private var rankedFriends: [AppUser] {
        appState.friendsRankedByActivity
    }

    /// Invited contacts are only meaningful when sharing a song. For
    /// other payloads the chip row hides them — see type doc for why.
    private var renderableInvitedContacts: [SimpleContact] {
        item.kind == .song ? invitedContacts : []
    }

    private var allSelected: Bool {
        let friendsAllOn = rankedFriends.isEmpty
            || rankedFriends.allSatisfy { selectedFriends.contains($0.id) }
        let contactsAllOn = renderableInvitedContacts.isEmpty
            || renderableInvitedContacts.allSatisfy { selectedContacts.contains($0.id) }
        let anyRecipients = !rankedFriends.isEmpty || !renderableInvitedContacts.isEmpty
        return anyRecipients && friendsAllOn && contactsAllOn
    }

    private var canSend: Bool {
        !selectedFriends.isEmpty || !selectedContacts.isEmpty
    }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { isNoteFocused = false }

            VStack(spacing: 0) {
                Spacer(minLength: 16)
                artwork
                Spacer(minLength: 16)
                titleBlock
                Spacer(minLength: 16)
                if item.kind == .song {
                    previewControls
                        .padding(.horizontal, 40)
                    Spacer(minLength: 20)
                }
                sendButton
                Spacer()
                friendChipRow
                    .padding(.bottom, 16)
            }

            if showSentAnimation {
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
        }
        .animation(.spring(duration: 0.3), value: showSentAnimation)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .task {
            // Resolve once per-appearance so the "Open in Spotify"
            // pill can jump straight into the app. Skipped for
            // non-song payloads — there's no single track to resolve.
            guard let song else { return }
            if appState.preferredMusicService == .spotify,
               SpotifyDeepLinkResolver.spotifyTrackID(for: song, resolvedSpotifyURL: nil) == nil,
               let amURL = song.appleMusicURL {
                resolvedSpotifyURL = await MusicSearchService.shared.resolveSpotifyURL(
                    appleMusicURL: amURL,
                    title: song.title,
                    artist: song.artist
                )
            }
        }
        .sheet(isPresented: $showAddFriends) {
            AddFriendsView(appState: appState)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showSaveSheet) {
            // Branch the save sheet by payload. Mixtapes never reach
            // here (the bookmark button is hidden) so we only need
            // song / album cases.
            switch item {
            case .song(let s):
                SaveToMixtapeSheet(song: s, appState: appState)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            case .album(let a):
                SaveAlbumToMixtapeSheet(album: a, appState: appState)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            case .mixtape:
                EmptyView()
            }
        }
    }

    /// Whether the bookmark/save-to-mixtape affordance should render.
    /// Hidden for mixtapes (see `showSaveSheet` doc).
    private var canSaveItem: Bool {
        switch item.kind {
        case .song, .album: return true
        case .mixtape:      return false
        }
    }

    // MARK: - Artwork + title

    /// Square artwork tile. Songs and albums render their server-side
    /// artwork URL; mixtapes composite from their songs via
    /// `MixtapeCoverView`. The note pill overlay is the same in all
    /// three cases — it's part of the share affordance, not the
    /// payload's identity.
    private var artwork: some View {
        ZStack {
            switch item {
            case .song(let s):
                artworkURL(s.albumArtURL)
            case .album(let a):
                artworkURL(a.artworkURL)
            case .mixtape(let m):
                MixtapeCoverView(mixtape: m, cornerRadius: 20, showsShadow: false)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: 280)
        .clipShape(.rect(cornerRadius: 20))
        .shadow(color: .black.opacity(0.4), radius: 16, x: 0, y: 8)
        .overlay(alignment: .bottom) {
            notePill
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
        }
        .padding(.horizontal, 40)
    }

    /// Renders a server-side artwork URL with the same placeholder fill
    /// the original song-only view used. Pulled into a helper so
    /// song/album branches in `artwork` stay short.
    private func artworkURL(_ url: String) -> some View {
        Color(.systemGray5)
            .overlay {
                AsyncImage(url: URL(string: url)) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    }
                }
                .allowsHitTesting(false)
            }
    }

    /// Blur-material message bubble overlaid on the artwork. The root
    /// ZStack ignores the keyboard safe area, so nothing in the layout
    /// shifts when this field focuses — the keyboard simply slides up
    /// over the chip row and Send button below.
    private var notePill: some View {
        AppTextField(
            "",
            text: $note,
            prompt: Text("Add a message").foregroundColor(.white.opacity(0.78)),
            axis: .vertical,
            submitLabel: .done,
            onSubmit: { isNoteFocused = false }
        )
        .lineLimit(1...3)
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(.white)
        .tint(.white)
        .multilineTextAlignment(.center)
        .focused($isNoteFocused)
        .submitLabel(.done)
        .onSubmit { isNoteFocused = false }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial, in: Capsule())
        .background(Color.white.opacity(0.06), in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.22), lineWidth: 0.5))
        .shadow(color: .white.opacity(0.18), radius: 10, x: 0, y: 0)
        .onChange(of: note) { _, newValue in
            // `axis: .vertical` TextFields swallow `onSubmit` on Return
            // and insert a newline instead. Strip newlines as they
            // arrive and treat them as a dismiss request, matching
            // the spec (Enter = finish, never multiline-by-Enter).
            if newValue.contains("\n") {
                note = newValue.replacingOccurrences(of: "\n", with: "")
                isNoteFocused = false
                return
            }
            if newValue.count > 70 { note = String(newValue.prefix(70)) }
        }
    }

    private var titleBlock: some View {
        VStack(spacing: 4) {
            Text(item.title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
            if !item.subtitle.isEmpty {
                Text(item.subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Preview controls

    /// Inline scrub bar + play/pause for the song-only case. Albums
    /// and mixtapes don't have a single audition target, so the parent
    /// `body` skips this row when `item.kind != .song`.
    private var previewControls: some View {
        VStack(spacing: 10) {
            if let song {
                ScrubBarView(songId: song.id, fallbackDuration: song.duration)

                HStack(spacing: 10) {
                    Button {
                        audioPlayer.play(song: song)
                    } label: {
                        ZStack {
                            if isCurrentSong && audioPlayer.isLoading {
                                ProgressView()
                                    .tint(.black)
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: isPlayingThis ? "pause.fill" : "play.fill")
                                    .font(.system(size: 15, weight: .semibold))
                                    .contentTransition(.symbolEffect(.replace))
                            }
                        }
                        .foregroundStyle(.black)
                        .frame(width: 52, height: 40)
                        .background(.white)
                        .clipShape(.capsule)
                    }
                    .sensoryFeedback(.impact(weight: .light), trigger: isPlayingThis)

                    openInServiceButton(
                        song: song,
                        service: appState.preferredMusicService,
                        resolvedSpotifyURL: resolvedSpotifyURL,
                        shareId: shareId
                    )
                }
            }
        }
    }

    // MARK: - Send button

    /// Send + (optional) save row. The Send button stays the primary
    /// affordance — same 72pt accent circle as before. The bookmark
    /// floats off to the side as a secondary 44pt circle so it is
    /// clearly demoted in visual weight (Send is the action the user
    /// is here to take; save is a "while I'm at it" detour). Hidden
    /// entirely for mixtape payloads — see `canSaveItem`.
    private var sendButton: some View {
        ZStack {
            Button {
                commitSend()
            } label: {
                ZStack {
                    Circle()
                        .fill(canSend ? Color(red: 0.76, green: 0.38, blue: 0.35) : Color.white.opacity(0.1))
                        .frame(width: 72, height: 72)

                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(canSend ? .white : .white.opacity(0.3))
                        .offset(x: -2)
                }
            }
            .disabled(!canSend)
            .sensoryFeedback(.success, trigger: showSentAnimation)
            .animation(.easeInOut(duration: 0.15), value: canSend)

            if canSaveItem {
                // Anchored 44pt to the trailing side of the Send
                // circle. Using a ZStack + offset (rather than an
                // HStack) keeps Send centered horizontally; otherwise
                // adding a sibling button would visually shift Send
                // off-axis. 56pt of horizontal space between centers
                // (36 + 20) keeps the two affordances clearly
                // separate without crowding.
                saveButton
                    .offset(x: 72)
            }
        }
    }

    /// Secondary save-to-mixtape affordance. Bookmark icon, neutral
    /// fill, no badge — the share view is for outbound action; saving
    /// is a sidecar. Hidden for mixtape payloads.
    private var saveButton: some View {
        Button {
            showSaveSheet = true
        } label: {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 44, height: 44)

                Image(systemName: "bookmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .accessibilityLabel(item.kind == .album ? "Save album to mixtape" : "Save to mixtape")
    }

    /// Dispatches the send based on the payload kind. Songs fan out
    /// per-recipient (so each `SongShare` gets its own Firestore doc
    /// and each invited contact gets its own pending invite write);
    /// albums and mixtapes hit `appState` once with the whole
    /// recipient list, since those backends batch the fan-out
    /// server-side.
    private func commitSend() {
        guard canSend else { return }
        showSentAnimation = true
        let friends = resolveSelectedFriends()
        let contacts = resolveSelectedContacts()
        let noteToSend = note.isEmpty ? nil : note
        let payload = item

        Task {
            switch payload {
            case .song(let s):
                for friend in friends {
                    await appState.sendSong(s, to: friend, note: noteToSend)
                }
                for contact in contacts {
                    _ = await appState.sendSongToPendingContact(s, contact: contact, note: noteToSend)
                }
            case .album(let a):
                await appState.sendAlbum(a, to: friends, note: noteToSend)
            case .mixtape(let m):
                await appState.sendMixtape(m, to: friends, note: noteToSend)
            }
            try? await Task.sleep(for: .seconds(1.2))
            onSent()
        }
    }

    // MARK: - Friend chip row

    private var friendChipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 18) {
                allChip
                ForEach(rankedFriends) { friend in
                    friendChip(friend)
                }
                ForEach(renderableInvitedContacts) { contact in
                    contactChip(contact)
                }
                addFriendsChip
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 4)
        }
    }

    private var allChip: some View {
        Button {
            if allSelected {
                for user in rankedFriends {
                    selectedFriends.remove(user.id)
                }
                for contact in renderableInvitedContacts {
                    selectedContacts.remove(contact.id)
                }
            } else {
                for user in rankedFriends {
                    selectedFriends.insert(user.id)
                }
                for contact in renderableInvitedContacts {
                    selectedContacts.insert(contact.id)
                }
            }
        } label: {
            chipLayout(label: "All", selected: allSelected) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .disabled(rankedFriends.isEmpty && renderableInvitedContacts.isEmpty)
    }

    private func friendChip(_ friend: AppUser) -> some View {
        let isSelected = selectedFriends.contains(friend.id)
        return Button {
            if isSelected {
                selectedFriends.remove(friend.id)
            } else {
                selectedFriends.insert(friend.id)
            }
        } label: {
            chipLayout(label: friend.firstName, selected: isSelected) {
                Text(friend.initials)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
    }

    /// Chip for a pending-signup contact. Visually consistent with
    /// `friendChip` but carries an "INVITED" micro-badge so the user
    /// can tell apart a real account from someone who will only
    /// receive the song once they finish signup.
    private func contactChip(_ contact: SimpleContact) -> some View {
        let isSelected = selectedContacts.contains(contact.id)
        let label = contact.firstName.isEmpty ? contact.phoneNumber : contact.firstName
        return Button {
            if isSelected {
                selectedContacts.remove(contact.id)
            } else {
                selectedContacts.insert(contact.id)
            }
        } label: {
            chipLayout(label: label, selected: isSelected) {
                ZStack(alignment: .topTrailing) {
                    Text(contact.initials.isEmpty ? "?" : contact.initials)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)

                    Text("INVITED")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.25))
                        .clipShape(.capsule)
                        .offset(x: 14, y: -18)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var addFriendsChip: some View {
        Button {
            showAddFriends = true
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                        .foregroundStyle(.white.opacity(0.35))
                        .frame(width: 56, height: 56)

                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }
                Text("Add friends")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
            .frame(width: 64)
        }
        .buttonStyle(.plain)
    }

    /// Shared chip layout: 56 pt circular body + first-name caption,
    /// with a selection ring that mirrors the Send button's accent.
    @ViewBuilder
    private func chipLayout<Content: View>(
        label: String,
        selected: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.14))
                    .frame(width: 56, height: 56)

                content()

                if selected {
                    Circle()
                        .stroke(Color(red: 0.76, green: 0.38, blue: 0.35), lineWidth: 2.5)
                        .frame(width: 56, height: 56)

                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.white, Color(red: 0.76, green: 0.38, blue: 0.35))
                        .background(Circle().fill(Color.black).frame(width: 18, height: 18))
                        .offset(x: 20, y: 20)
                }
            }
            Text(label)
                .font(.system(size: 12, weight: selected ? .semibold : .medium))
                .foregroundStyle(selected ? .white : .white.opacity(0.65))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(width: 64)
        .animation(.easeInOut(duration: 0.15), value: selected)
    }

    // MARK: - Helpers

    private func resolveSelectedFriends() -> [AppUser] {
        var seen = Set<String>()
        var result: [AppUser] = []
        for user in rankedFriends where selectedFriends.contains(user.id) && !seen.contains(user.id) {
            seen.insert(user.id)
            result.append(user)
        }
        return result
    }

    private func resolveSelectedContacts() -> [SimpleContact] {
        var seen = Set<String>()
        var result: [SimpleContact] = []
        for contact in renderableInvitedContacts where selectedContacts.contains(contact.id) && !seen.contains(contact.id) {
            seen.insert(contact.id)
            result.append(contact)
        }
        return result
    }
}
