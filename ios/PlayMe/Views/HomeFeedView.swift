import SwiftUI

struct HomeFeedView: View {
    let shares: [SongShare]
    let appState: AppState
    let onSendSong: () -> Void

    @State private var currentIndex: Int = 0

    var body: some View {
        if shares.isEmpty {
            emptyState
        } else {
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(shares.enumerated()), id: \.element.id) { index, share in
                        SongCardView(
                            share: share,
                            isLiked: appState.isLiked(shareId: share.id),
                            appState: appState,
                            onToggleLike: { appState.toggleLike(shareId: share.id) }
                        )
                        .containerRelativeFrame(.vertical)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollIndicators(.hidden)
            .ignoresSafeArea(.keyboard)
        }
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
