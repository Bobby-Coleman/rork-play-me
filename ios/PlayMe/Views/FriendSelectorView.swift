import SwiftUI

struct FriendSelectorView: View {
    let song: Song
    let appState: AppState
    let onBack: () -> Void
    let onSent: () -> Void

    @State private var searchText: String = ""
    @State private var selectedFriends: Set<String> = []
    @State private var note: String = ""
    @State private var showSentAnimation = false
    @State private var searchResults: [AppUser] = []
    @State private var isSearching = false

    private var displayedUsers: [AppUser] {
        if searchText.isEmpty {
            return appState.friends
        }
        return searchResults
    }

    private var allSelected: Bool {
        !displayedUsers.isEmpty && displayedUsers.allSatisfy { selectedFriends.contains($0.id) }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                Color(.systemGray5)
                    .frame(width: 120, height: 120)
                    .overlay {
                        AsyncImage(url: URL(string: song.albumArtURL)) { phase in
                            if let image = phase.image {
                                image.resizable().aspectRatio(contentMode: .fill)
                            }
                        }
                        .allowsHitTesting(false)
                    }
                    .clipShape(.rect(cornerRadius: 12))
                    .padding(.top, 8)
                    .padding(.bottom, 8)

                Text(song.title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                Text(song.artist)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.bottom, 20)

                Text("Share the song to their homescreen")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.bottom, 12)

                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.white.opacity(0.4))
                    TextField("Search friends or users", text: $searchText)
                        .foregroundStyle(.white)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onChange(of: searchText) { _, newValue in
                            performSearch(newValue)
                        }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.08))
                .clipShape(.rect(cornerRadius: 10))
                .padding(.horizontal, 20)
                .padding(.bottom, 12)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        if isSearching {
                            ProgressView()
                                .tint(.white)
                                .padding(.top, 20)
                        } else {
                            if !displayedUsers.isEmpty {
                                sendToAllRow
                                Divider()
                                    .background(Color.white.opacity(0.06))
                            }

                            ForEach(displayedUsers) { friend in
                                friendRow(friend)
                            }
                            if displayedUsers.isEmpty && !searchText.isEmpty {
                                Text("No users found")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.white.opacity(0.3))
                                    .padding(.top, 20)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .scrollDismissesKeyboard(.interactively)

                VStack(spacing: 12) {
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

                    Button {
                        guard !selectedFriends.isEmpty else { return }
                        showSentAnimation = true
                        let friends = resolveSelectedFriends()
                        Task {
                            for friend in friends {
                                await appState.sendSong(song, to: friend, note: note)
                            }
                            try? await Task.sleep(for: .seconds(1.2))
                            onSent()
                        }
                    } label: {
                        Text(shareButtonLabel)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(
                                !selectedFriends.isEmpty
                                    ? Color(red: 0.76, green: 0.38, blue: 0.35)
                                    : Color.white.opacity(0.1)
                            )
                            .clipShape(.rect(cornerRadius: 25))
                    }
                    .disabled(selectedFriends.isEmpty)
                    .sensoryFeedback(.success, trigger: showSentAnimation)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
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
    }

    private var shareButtonLabel: String {
        let count = selectedFriends.count
        if count == 0 { return "Share" }
        if count == 1 { return "Share" }
        return "Share to \(count) friends"
    }

    private func resolveSelectedFriends() -> [AppUser] {
        let all = appState.friends + searchResults
        var seen = Set<String>()
        var result: [AppUser] = []
        for user in all where selectedFriends.contains(user.id) && !seen.contains(user.id) {
            seen.insert(user.id)
            result.append(user)
        }
        return result
    }

    // MARK: - Send to All

    private var sendToAllRow: some View {
        Button {
            if allSelected {
                for user in displayedUsers {
                    selectedFriends.remove(user.id)
                }
            } else {
                for user in displayedUsers {
                    selectedFriends.insert(user.id)
                }
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Color(red: 0.76, green: 0.38, blue: 0.35).opacity(0.3))
                    .clipShape(Circle())

                Text("Send to All")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)

                Spacer()

                Circle()
                    .stroke(allSelected ? Color.clear : Color.white.opacity(0.2), lineWidth: 1.5)
                    .fill(allSelected ? Color(red: 0.76, green: 0.38, blue: 0.35) : Color.clear)
                    .frame(width: 24, height: 24)
                    .overlay {
                        if allSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

    // MARK: - Friend Row

    private func friendRow(_ friend: AppUser) -> some View {
        let isSelected = selectedFriends.contains(friend.id)
        return Button {
            if isSelected {
                selectedFriends.remove(friend.id)
            } else {
                selectedFriends.insert(friend.id)
            }
        } label: {
            HStack(spacing: 14) {
                Text(friend.initials)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Color.white.opacity(0.12))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(friend.firstName)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                    Text("@\(friend.username)")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.4))
                }

                Spacer()

                Circle()
                    .stroke(isSelected ? Color.clear : Color.white.opacity(0.2), lineWidth: 1.5)
                    .fill(isSelected ? Color(red: 0.76, green: 0.38, blue: 0.35) : Color.clear)
                    .frame(width: 24, height: 24)
                    .overlay {
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
