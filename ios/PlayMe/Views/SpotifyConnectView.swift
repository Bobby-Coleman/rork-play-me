import SwiftUI

struct SpotifyConnectView: View {
    let spotifyAuth: SpotifyAuthService
    let onComplete: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(Color(red: 0.11, green: 0.73, blue: 0.33))
                    .padding(.bottom, 24)

                Text("Connect to Spotify")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.bottom, 8)

                Text("Search millions of songs and\nplay previews right in the app")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 40)

                VStack(spacing: 12) {
                    featureRow(icon: "magnifyingglass", text: "Search Spotify's full catalog")
                    featureRow(icon: "play.circle.fill", text: "Play 30-second song previews")
                    featureRow(icon: "arrow.up.right", text: "Open full songs in Spotify")
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 48)

                Spacer()

                Button {
                    Task { await spotifyAuth.authenticate() }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "music.note")
                            .font(.system(size: 16, weight: .bold))
                        Text("Connect Spotify")
                            .font(.system(size: 17, weight: .bold))
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Color(red: 0.11, green: 0.73, blue: 0.33))
                    .clipShape(.rect(cornerRadius: 27))
                }
                .padding(.horizontal, 40)
                .disabled(spotifyAuth.isAuthenticating)
                .opacity(spotifyAuth.isAuthenticating ? 0.6 : 1)

                if spotifyAuth.isAuthenticating {
                    HStack(spacing: 8) {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.8)
                        Text("Connecting...")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .padding(.top, 12)
                }

                Button("Skip for now", action: onComplete)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.top, 16)
                    .padding(.bottom, 40)
            }
        }
        .onChange(of: spotifyAuth.isAuthenticated) { _, isAuth in
            if isAuth { onComplete() }
        }
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(Color(red: 0.11, green: 0.73, blue: 0.33))
                .frame(width: 24)

            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.7))

            Spacer()
        }
        .padding(.vertical, 4)
    }
}
