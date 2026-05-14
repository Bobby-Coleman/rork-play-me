import SwiftUI

/// Fullscreen-style listening UI shown while Shazam is matching or the
/// Apple Music lookup is in flight.
struct ShazamListeningOverlay: View {
    let isResolving: Bool
    let onCancel: () -> Void

    @State private var pulse = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.78).ignoresSafeArea()

            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                        .frame(width: 140, height: 140)
                        .scaleEffect(pulse ? 1.18 : 0.92)
                        .opacity(pulse ? 0.0 : 0.9)
                    Circle()
                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                        .frame(width: 110, height: 110)
                        .scaleEffect(pulse ? 1.10 : 0.96)
                        .opacity(pulse ? 0.1 : 0.85)
                    Circle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 92, height: 92)
                    Image(systemName: "shazam.logo")
                        .symbolRenderingMode(.monochrome)
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .animation(
                    .easeInOut(duration: 1.4).repeatForever(autoreverses: false),
                    value: pulse
                )

                VStack(spacing: 6) {
                    Text(isResolving ? "Found it. Loading in Apple Music..." : "Listening for a song...")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(isResolving ? "" : "Hold your phone near the speaker")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.55))
                }

                if !isResolving {
                    Button(action: onCancel) {
                        Text("Cancel")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.75))
                            .padding(.horizontal, 22)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(Color.white.opacity(0.1)))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 32)
        }
        .onAppear { pulse = true }
        .onDisappear { pulse = false }
    }
}
