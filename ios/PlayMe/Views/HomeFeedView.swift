import SwiftUI
import UIKit

struct HomeFeedView: View {
    let shares: [SongShare]
    let appState: AppState
    let onSendSong: () -> Void
    var onAddFriends: () -> Void = {}

    @State private var visibleShareId: String?
    private let scrollHaptic = UIImpactFeedbackGenerator(style: .soft)

    var body: some View {
        Group {
            if shares.isEmpty {
                emptyState
            } else {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(shares) { share in
                            SongCardView(
                                share: share,
                                isLiked: appState.isLiked(shareId: share.id),
                                appState: appState,
                                onToggleLike: { appState.toggleLike(shareId: share.id) }
                            )
                            .containerRelativeFrame(.vertical)
                            .id(share.id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $visibleShareId)
                .scrollIndicators(.hidden)
                .ignoresSafeArea(.keyboard)
                .onChange(of: visibleShareId) { oldValue, newValue in
                    guard let newValue, let oldValue, newValue != oldValue else { return }
                    scrollHaptic.prepare()
                    scrollHaptic.impactOccurred(intensity: 0.65)
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Spacer(minLength: 0)
                addFriendsPill
                Spacer(minLength: 0)
            }
        }
    }

    private var addFriendsPill: some View {
        Button(action: onAddFriends) {
            HStack(spacing: 6) {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 13, weight: .semibold))
                Text("Add Friends")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial.opacity(0.8))
            .background(Color.white.opacity(0.1))
            .clipShape(.capsule)
        }
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    private var emptyState: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "music.note")
                    .font(.system(size: 48))
                    .foregroundStyle(.white.opacity(0.2))

                Text("No songs yet")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)

                Text("Send a song to a friend\nand wait for one back")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)

                Button(action: onSendSong) {
                    Text("Send a Song")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 12)
                        .background(.white)
                        .clipShape(.capsule)
                }
                .padding(.top, 8)
            }
        }
    }
}
