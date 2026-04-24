import SwiftUI

struct FriendSelectorView: View {
    let song: Song
    let appState: AppState
    /// Pending-signup contacts to render alongside real friends. Defaults to
    /// empty so every main-app call site stays friends-only. The onboarding
    /// flow passes `appState.invitedContacts` so freshly registered users
    /// who have only SMS-invited people can still send their first song.
    var invitedContacts: [SimpleContact] = []
    /// Share context when this view is acting as a song action destination
    /// (feed tap / history tap via `SongActionSheet`) rather than a pre-send
    /// surface. When present we thread it down to `openInServiceButton` so
    /// any resolution that fires writes back to `shares/{id}.song.spotifyURI`.
    /// `nil` means "no share yet" (the pre-send case) and writeback is
    /// correctly skipped.
    var shareId: String? = nil
    let onBack: () -> Void
    let onSent: () -> Void

    private var audioPlayer: AudioPlayerService { AudioPlayerService.shared }
    private var isCurrentSong: Bool { audioPlayer.currentSongId == song.id }
    private var isPlayingThis: Bool { isCurrentSong && audioPlayer.isPlaying }

    @State private var selectedFriends: Set<String> = []
    /// Parallel selection set for invited contacts. Lives alongside
    /// `selectedFriends` rather than merging into one set so we can route
    /// sends to the correct backend path (`sendSong` vs
    /// `sendSongToPendingContact`) without any later disambiguation.
    @State private var selectedContacts: Set<String> = []
    @State private var note: String = ""
    @State private var showSentAnimation = false
    @State private var showAddFriends = false
    /// Pre-resolved Spotify URL for the "Open in Spotify" button. When the
    /// user prefers Spotify and the song only carries an Apple-Music URL,
    /// we resolve it once on appear so the tap-through is instant.
    @State private var resolvedSpotifyURL: String?
    @FocusState private var isNoteFocused: Bool

    private var rankedFriends: [AppUser] {
        appState.friendsRankedByActivity
    }

    private var allSelected: Bool {
        let friendsAllOn = rankedFriends.isEmpty
            || rankedFriends.allSatisfy { selectedFriends.contains($0.id) }
        let contactsAllOn = invitedContacts.isEmpty
            || invitedContacts.allSatisfy { selectedContacts.contains($0.id) }
        let anyRecipients = !rankedFriends.isEmpty || !invitedContacts.isEmpty
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
                previewControls
                    .padding(.horizontal, 40)
                Spacer(minLength: 20)
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
            // Resolve once per-appearance so the "Open in Spotify" pill can
            // jump straight into the app. `resolveSpotifyURL` is
            // cache-first (local → Firestore global) and only hits the
            // network on true cache misses, so this is cheap to fire
            // every time the view appears. No-op when the user prefers
            // Apple Music, when the song already ships with a Spotify
            // URI, or when there's no Apple-Music URL to translate from.
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
    }

    // MARK: - Artwork + title

    private var artwork: some View {
        Color(.systemGray5)
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: 280)
            .overlay {
                AsyncImage(url: URL(string: song.albumArtURL)) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    }
                }
                .allowsHitTesting(false)
            }
            .clipShape(.rect(cornerRadius: 20))
            .shadow(color: .black.opacity(0.4), radius: 16, x: 0, y: 8)
            .overlay(alignment: .bottom) {
                notePill
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
            }
            .padding(.horizontal, 40)
    }

    /// Blur-material message bubble overlaid on the album art. The root
    /// ZStack ignores the keyboard safe area, so nothing in the layout shifts
    /// when this field focuses — the keyboard simply slides up over the
    /// chip row and Send button below.
    private var notePill: some View {
        TextField(
            "",
            text: $note,
            prompt: Text("Add a message").foregroundColor(.white.opacity(0.55)),
            axis: .vertical
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
        .onChange(of: note) { _, newValue in
            if newValue.count > 70 { note = String(newValue.prefix(70)) }
        }
    }

    private var titleBlock: some View {
        VStack(spacing: 4) {
            Text(song.title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(song.artist)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Preview controls

    /// Inline scrub bar + play/pause so users can audition the track while
    /// picking recipients. The "Open in Spotify / Apple Music" pill sits
    /// on the same row as the play button — same layout as the feed card
    /// so the share view feels like a continuation rather than a separate
    /// surface. Service honors `appState.preferredMusicService`, set once
    /// during onboarding.
    private var previewControls: some View {
        VStack(spacing: 10) {
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

    // MARK: - Send button

    private var sendButton: some View {
        Button {
            guard canSend else { return }
            showSentAnimation = true
            let friends = resolveSelectedFriends()
            let contacts = resolveSelectedContacts()
            let noteToSend = note
            Task {
                for friend in friends {
                    await appState.sendSong(song, to: friend, note: noteToSend)
                }
                for contact in contacts {
                    _ = await appState.sendSongToPendingContact(song, contact: contact, note: noteToSend)
                }
                try? await Task.sleep(for: .seconds(1.2))
                onSent()
            }
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
    }

    // MARK: - Friend chip row

    private var friendChipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 18) {
                allChip
                ForEach(rankedFriends) { friend in
                    friendChip(friend)
                }
                ForEach(invitedContacts) { contact in
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
                for contact in invitedContacts {
                    selectedContacts.remove(contact.id)
                }
            } else {
                for user in rankedFriends {
                    selectedFriends.insert(user.id)
                }
                for contact in invitedContacts {
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
        .disabled(rankedFriends.isEmpty && invitedContacts.isEmpty)
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
    /// `friendChip` but carries an "INVITED" micro-badge so the user can
    /// tell apart a real account from someone who will only receive the
    /// song once they finish signup.
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

    /// Shared chip layout: 56 pt circular body + first-name caption, with a
    /// selection ring that mirrors the Send button's accent color.
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
        for contact in invitedContacts where selectedContacts.contains(contact.id) && !seen.contains(contact.id) {
            seen.insert(contact.id)
            result.append(contact)
        }
        return result
    }
}
