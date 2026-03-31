import SwiftUI

struct SplashView: View {
    let spotifyAuth: SpotifyAuthService
    let onConnected: () -> Void

    @State private var floatingOffsets: [CGSize] = (0..<6).map { _ in
        CGSize(width: CGFloat.random(in: -30...30), height: CGFloat.random(in: -30...30))
    }

    private let albumCovers = Array(MockData.songs.prefix(6))

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ForEach(Array(albumCovers.enumerated()), id: \.element.id) { index, song in
                let positions: [(x: CGFloat, y: CGFloat)] = [
                    (-80, -280), (100, -220), (-60, -100),
                    (120, -40), (-100, 80), (80, 160)
                ]
                let pos = positions[index % positions.count]

                AsyncImage(url: URL(string: song.albumArtURL)) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Color(.systemGray5)
                    }
                }
                .frame(width: 80, height: 80)
                .clipShape(.rect(cornerRadius: 8))
                .rotationEffect(.degrees(Double.random(in: -15...15)))
                .opacity(0.6)
                .offset(x: pos.x + floatingOffsets[index].width, y: pos.y + floatingOffsets[index].height)
            }

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 4) {
                    Text("PLAY ME")
                        .font(.system(size: 48, weight: .black))
                        .foregroundStyle(.white)
                        .tracking(2)

                    Text("©")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                }

                Spacer()

                VStack(spacing: 14) {
                    Button {
                        SpotifyPlaybackService.shared.authorizeAndPlay()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "music.note")
                                .font(.system(size: 18, weight: .bold))
                            Text("CONNECT WITH SPOTIFY")
                                .font(.system(size: 15, weight: .bold))
                                .tracking(1)
                        }
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color(red: 0.11, green: 0.73, blue: 0.33))
                        .clipShape(.rect(cornerRadius: 26))
                    }
                    .disabled(spotifyAuth.isLoggingIn)
                    .opacity(spotifyAuth.isLoggingIn ? 0.6 : 1)

                    if spotifyAuth.isLoggingIn {
                        HStack(spacing: 8) {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.8)
                            Text("Waiting for Spotify...")
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }

                    if let error = spotifyAuth.authError {
                        Text(error)
                            .font(.system(size: 13))
                            .foregroundStyle(.red.opacity(0.8))
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 60)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                for i in floatingOffsets.indices {
                    floatingOffsets[i] = CGSize(
                        width: CGFloat.random(in: -40...40),
                        height: CGFloat.random(in: -40...40)
                    )
                }
            }
        }
        .onChange(of: spotifyAuth.isAuthenticated) { _, authenticated in
            if authenticated {
                onConnected()
            }
        }
    }
}
