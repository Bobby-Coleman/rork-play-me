import SwiftUI

/// Screen 2 — Social proof.
///
/// Animated column of drifting album tiles, each with a friend note
/// speech-bubble. Notes alternate left/right on consecutive tiles to
/// produce the "back-and-forth thread" feel of the React mock.
struct SocialProofView: View {
    let stepIdx: Int
    let totalSteps: Int
    let onContinue: () -> Void
    let onBack: (() -> Void)?

    @Environment(\.riffTheme) private var theme

    var body: some View {
        RiffScreenChrome(stepIdx: stepIdx, totalSteps: totalSteps, onBack: onBack) {
            RiffStagger(delay: 0.06) {
                RiffHeadline(text: "Discover what your friends are actually listening to.")
            }

            DriftingTiles()
                .padding(.top, 24)
                .frame(maxHeight: .infinity)
        } footer: {
            RiffStagger(delay: 0.52) {
                RiffPrimaryButton(title: "Continue", action: onContinue)
            }
        }
    }
}

// MARK: - Drifting tiles

private struct FriendNote {
    let name: String
    let body: String
}

private let friendNotes: [FriendNote] = [
    FriendNote(name: "Holli",   body: "this one's for the drive home"),
    FriendNote(name: "Marcus",  body: "you'll love the bridge"),
    FriendNote(name: "Theo",    body: "3am song"),
    FriendNote(name: "June",    body: "reminded me of last summer"),
    FriendNote(name: "Sam",     body: "play it loud"),
    FriendNote(name: "Niko",    body: "b-side, trust me"),
]

private struct DriftingTiles: View {
    @State private var startDate = Date()

    private let tileCount = 8
    private let tileSpacing: CGFloat = 220
    private let tileWidth: CGFloat = 180
    /// pixels per second of upward drift
    private let speed: CGFloat = 33

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation) { ctx in
                let elapsed = CGFloat(max(0, ctx.date.timeIntervalSince(startDate)))
                let totalH = CGFloat(tileCount) * tileSpacing

                ZStack(alignment: .topLeading) {
                    ForEach(0..<tileCount, id: \.self) { i in
                        let onLeft = i % 2 == 0
                        let baseY = CGFloat(i) * tileSpacing
                        let y = ((baseY - elapsed * speed)
                                 .truncatingRemainder(dividingBy: totalH) + totalH)
                                 .truncatingRemainder(dividingBy: totalH) - tileSpacing

                        TileWithNote(
                            seed: 21 + i,
                            note: friendNotes[i % friendNotes.count],
                            onLeft: onLeft
                        )
                        .frame(width: tileWidth)
                        .position(
                            x: onLeft ? proxy.size.width * 0.32 : proxy.size.width * 0.68,
                            y: y + 100
                        )
                    }

                    // Top + bottom fades.
                    LinearGradient(
                        colors: [Color.black, Color.black.opacity(0)],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: 60)

                    LinearGradient(
                        colors: [Color.black.opacity(0), Color.black],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: 60)
                    .offset(y: proxy.size.height - 60)
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                .clipped()
            }
        }
        .onAppear { startDate = Date() }
    }
}

private struct TileWithNote: View {
    let seed: Int
    let note: FriendNote
    let onLeft: Bool

    var body: some View {
        ZStack(alignment: onLeft ? .topTrailing : .topLeading) {
            RiffPlaceholderImage(seed: seed, cornerRadius: 4)
                .frame(width: 180, height: 180)

            NoteBubble(note: note, onLeft: onLeft)
                .offset(x: onLeft ? 50 : -50, y: -8)
        }
    }
}

private struct NoteBubble: View {
    let note: FriendNote
    let onLeft: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(note.name)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.black)
            Text(note.body)
                .font(.system(size: 11))
                .foregroundStyle(Color.black.opacity(0.7))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(width: 130, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.white)
        )
        .clipShape(BubbleClip(onLeft: onLeft))
        .shadow(color: Color.black.opacity(0.4), radius: 9, x: 0, y: 4)
    }
}

private struct BubbleClip: Shape {
    let onLeft: Bool

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: onLeft
                ? [.bottomLeft, .bottomRight, .topRight]
                : [.bottomLeft, .bottomRight, .topLeft],
            cornerRadii: CGSize(width: 12, height: 12)
        )
        return Path(path.cgPath)
    }
}
