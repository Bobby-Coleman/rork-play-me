import SwiftUI

struct SplashView: View {
    let onServiceSelected: (MusicService) -> Void

    @State private var floatingOffsets: [CGSize] = (0..<6).map { _ in
        CGSize(width: CGFloat.random(in: -30...30), height: CGFloat.random(in: -30...30))
    }

    private let albumCoverURLs: [String] = [
        "https://i.scdn.co/image/ab67616d0000b2738863bc11d2aa12b54f5aeb36",
        "https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=600&h=600&fit=crop",
        "https://images.unsplash.com/photo-1493225457124-a3eb161ffa5f?w=600&h=600&fit=crop",
        "https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?w=600&h=600&fit=crop",
        "https://images.unsplash.com/photo-1459749411175-04bf5292ceea?w=600&h=600&fit=crop",
        "https://images.unsplash.com/photo-1571330735066-03aaa9429d89?w=600&h=600&fit=crop",
    ]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ForEach(Array(albumCoverURLs.enumerated()), id: \.offset) { index, urlString in
                let positions: [(x: CGFloat, y: CGFloat)] = [
                    (-80, -280), (100, -220), (-60, -100),
                    (120, -40), (-100, 80), (80, 160)
                ]
                let pos = positions[index % positions.count]

                AsyncImage(url: URL(string: urlString)) { phase in
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
                    Text("RIFF")
                        .font(.system(size: 48, weight: .black))
                        .foregroundStyle(.white)
                        .tracking(2)

                    Text("Share songs with friends")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.5))
                }

                Spacer()

                VStack(spacing: 14) {
                    Text("I listen on...")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                        .tracking(0.5)

                    Button {
                        onServiceSelected(.spotify)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "music.note")
                                .font(.system(size: 18, weight: .bold))
                            Text("SPOTIFY")
                                .font(.system(size: 15, weight: .bold))
                                .tracking(1)
                        }
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color(red: 0.11, green: 0.73, blue: 0.33))
                        .clipShape(.rect(cornerRadius: 26))
                    }

                    Button {
                        onServiceSelected(.appleMusic)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "music.note")
                                .font(.system(size: 18, weight: .bold))
                            Text("APPLE MUSIC")
                                .font(.system(size: 15, weight: .bold))
                                .tracking(1)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            LinearGradient(colors: [Color(red: 0.98, green: 0.24, blue: 0.47), Color(red: 0.65, green: 0.18, blue: 0.82)], startPoint: .leading, endPoint: .trailing)
                        )
                        .clipShape(.rect(cornerRadius: 26))
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
    }
}
