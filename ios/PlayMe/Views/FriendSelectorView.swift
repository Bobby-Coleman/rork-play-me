import SwiftUI

struct FriendSelectorView: View {
    let song: Song
    let appState: AppState
    let onBack: () -> Void
    let onSent: () -> Void

    @State private var selectedFriends: Set<String> = []
    @State private var note: String = ""
    @State private var showSentAnimation = false
    @State private var showAddFriends = false

    private var rankedFriends: [AppUser] {
        appState.friendsRankedByActivity
    }

    private var allSelected: Bool {
        !rankedFriends.isEmpty && rankedFriends.allSatisfy { selectedFriends.contains($0.id) }
    }

    private var canSend: Bool {
        !selectedFriends.isEmpty
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 16)
                artwork
                Spacer(minLength: 20)
                titleBlock
                Spacer(minLength: 28)
                sendButton
                noteField
                    .padding(.top, 18)
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
            .padding(.horizontal, 40)
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

    // MARK: - Send button

    private var sendButton: some View {
        Button {
            guard canSend else { return }
            showSentAnimation = true
            let friends = resolveSelectedFriends()
            let noteToSend = note
            Task {
                for friend in friends {
                    await appState.sendSong(song, to: friend, note: noteToSend)
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

    // MARK: - Note field

    private var noteField: some View {
        TextField("", text: $note, prompt: Text("Add a message").foregroundColor(.white.opacity(0.35)))
            .font(.system(size: 14))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.08))
            .clipShape(.capsule)
            .padding(.horizontal, 40)
            .onChange(of: note) { _, newValue in
                if newValue.count > 150 { note = String(newValue.prefix(150)) }
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
            } else {
                for user in rankedFriends {
                    selectedFriends.insert(user.id)
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
        .disabled(rankedFriends.isEmpty)
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
}
