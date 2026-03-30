import SwiftUI

enum ProfileTab: String, CaseIterable {
    case received = "Received"
    case sent = "Sent"
    case liked = "Liked"
}

struct ProfileView: View {
    let appState: AppState

    @State private var selectedTab: ProfileTab = .received

    private var user: AppUser? { appState.currentUser }

    private var currentShares: [SongShare] {
        switch selectedTab {
        case .received: appState.receivedShares
        case .sent: appState.sentShares
        case .liked: appState.likedShares
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 10) {
                    Text(user?.initials ?? "?")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 80, height: 80)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())

                    Text(user?.firstName ?? "")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)

                    Text("@\(user?.username ?? "")")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.4))

                    if SpotifyAuthService.shared.isAuthenticated,
                       let displayName = SpotifyAuthService.shared.userDisplayName {
                        HStack(spacing: 6) {
                            Image(systemName: "music.note.circle.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(.green)
                            Text("Logged in with Spotify as: \(displayName)")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        .padding(.top, 4)
                    } else if !appState.isBackendAvailable {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(.orange)
                                .frame(width: 6, height: 6)
                            Text("Offline mode")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.3))
                        }
                        .padding(.top, 2)
                    }
                }
                .padding(.top, 32)

                tabPicker
                    .padding(.horizontal, 20)

                VStack(spacing: 0) {
                    if currentShares.isEmpty {
                        emptyState
                    } else {
                        ForEach(currentShares) { share in
                            songRow(share: share)

                            if share.id != currentShares.last?.id {
                                Divider()
                                    .background(Color.white.opacity(0.06))
                                    .padding(.horizontal, 20)
                            }
                        }
                    }
                }

                Button(role: .destructive) {
                    appState.logout()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                        Text("Sign Out")
                    }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.red.opacity(0.8))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.white.opacity(0.05))
                    .clipShape(.rect(cornerRadius: 12))
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 40)
            }
        }
        .scrollIndicators(.hidden)
        .background(Color.black)
        .refreshable {
            await appState.refreshShares()
        }
    }

    private var tabPicker: some View {
        HStack(spacing: 0) {
            ForEach(ProfileTab.allCases, id: \.self) { tab in
                let count: Int = {
                    switch tab {
                    case .received: appState.receivedShares.count
                    case .sent: appState.sentShares.count
                    case .liked: appState.likedShares.count
                    }
                }()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 6) {
                        HStack(spacing: 4) {
                            if tab == .liked {
                                Image(systemName: "heart.fill")
                                    .font(.system(size: 11))
                            }
                            Text(tab.rawValue)
                                .font(.system(size: 14, weight: .semibold))
                            Text("\(count)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(selectedTab == tab ? .white.opacity(0.5) : .white.opacity(0.2))
                        }

                        Rectangle()
                            .fill(selectedTab == tab ? Color.white : Color.clear)
                            .frame(height: 2)
                    }
                    .foregroundStyle(selectedTab == tab ? .white : .white.opacity(0.35))
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            let (icon, text): (String, String) = {
                switch selectedTab {
                case .received: ("music.note", "No songs received yet")
                case .sent: ("paperplane", "No songs sent yet")
                case .liked: ("heart", "No liked songs yet")
                }
            }()

            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundStyle(.white.opacity(0.15))
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.3))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    private func songRow(share: SongShare) -> some View {
        let person: String = {
            switch selectedTab {
            case .received: share.sender.firstName
            case .sent: share.recipient.firstName
            case .liked:
                if share.sender.id == appState.currentUser?.id {
                    "To \(share.recipient.firstName)"
                } else {
                    "From \(share.sender.firstName)"
                }
            }
        }()

        return HStack(spacing: 12) {
            Color(.systemGray5)
                .frame(width: 48, height: 48)
                .overlay {
                    AsyncImage(url: URL(string: share.song.albumArtURL)) { phase in
                        if let image = phase.image {
                            image.resizable().aspectRatio(contentMode: .fill)
                        }
                    }
                    .allowsHitTesting(false)
                }
                .clipShape(.rect(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 3) {
                Text(share.song.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(person)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.4))
            }

            Spacer()

            Button {
                appState.toggleLike(shareId: share.id)
            } label: {
                Image(systemName: appState.isLiked(shareId: share.id) ? "heart.fill" : "heart")
                    .font(.system(size: 16))
                    .foregroundStyle(appState.isLiked(shareId: share.id) ? .pink : .white.opacity(0.25))
            }
            .sensoryFeedback(.impact(weight: .light), trigger: appState.isLiked(shareId: share.id))

            Text(share.timestamp.formatted(.relative(presentation: .named)))
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.25))
                .frame(width: 70, alignment: .trailing)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }
}
