import SwiftUI
import MessageUI

/// Onboarding "send your first song" screen (step 6).
///
/// Mirrors the Discovery hero language: an ambient `AlbumArtGridBackgroundView`
/// sits above a big "search a song" CTA. Tapping the CTA presents
/// `OnboardingSongPickerSheet`, which hands back a `Song`. The rest of the
/// screen — note field, friend/contact recipients, Send button, invited-
/// contact queueing — is preserved from the previous iteration because
/// `FriendSelectorView` (used by the main `SendSongSheet`) does not yet
/// support `SimpleContact` recipients, and onboarding is the moment those
/// pending contacts matter most.
///
/// Sends to real friends go through `AppState.sendSong`. Sends to invited
/// contacts are queued via `sendSongToPendingContact` and delivered when
/// that contact finishes their own signup.
struct SendFirstSongView: View {
    let appState: AppState
    let onContinue: () -> Void
    let onSkip: () -> Void
    let onReopenInvites: () -> Void

    // Selection / send state
    @State private var selectedSong: Song?
    @State private var note: String = ""
    @State private var selectedFriendIds: Set<String> = []
    @State private var selectedContactIds: Set<String> = []
    @State private var showSentAnimation = false
    @State private var isSending = false

    // Song-picker modal
    @State private var showSongPicker = false

    // Ambient grid data source — same three-tier loader the Discovery
    // hero uses (bundled seed → disk cache → Firestore curated grid).
    @State private var gridVM = SongGridViewModel()

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

                    songPickerHero
                        .padding(.top, 20)

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
            await gridVM.loadIfNeeded()
        }
        .sheet(isPresented: $showSongPicker) {
            OnboardingSongPickerSheet(appState: appState) { picked in
                selectedSong = picked
            }
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

    // MARK: - Ambient grid + CTA

    /// Taller-than-square rectangle so the onboarding grid reads as
    /// distinct from the Discovery hero square while still using the
    /// exact same component + scroll animation.
    private var songPickerHero: some View {
        let screenW = UIScreen.main.bounds.width
        let gridWidth = screenW - 40
        let gridHeight = gridWidth * 1.35

        return VStack(spacing: 18) {
            AlbumArtGridBackgroundView(
                items: gridVM.dedupedDisplayItems,
                side: gridWidth,
                height: gridHeight
            )
            .frame(width: gridWidth, height: gridHeight)

            Button {
                showSongPicker = true
            } label: {
                VStack(spacing: 12) {
                    Text(selectedSong?.title ?? "search a song")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let song = selectedSong {
                selectedSongChip(song)
                    .padding(.horizontal, 20)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func selectedSongChip(_ song: Song) -> some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: song.albumArtURL)) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    Color.white.opacity(0.1)
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(.rect(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(song.artist)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button {
                showSongPicker = true
            } label: {
                Text("Change")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.14))
                    .clipShape(.capsule)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(Color.white.opacity(0.06))
        .clipShape(.rect(cornerRadius: 12))
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

    // MARK: - Actions

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
