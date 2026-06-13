import SwiftUI
import WidgetKit

/// Horizontal paging selector for the home-screen widget style, modeled on
/// the profile photo picker's carousel (view-aligned paging + scroll
/// position selection + animated page dots). The centered page IS the
/// selection: landing on a page writes `appState.widgetStyle`, which
/// persists to the App Group and reloads widget timelines immediately.
///
/// Used by onboarding (`RiffWidgetView`) and Settings.
struct WidgetStyleCarousel: View {
    @Bindable var appState: AppState
    /// Side length of each widget-face preview tile.
    var tileSize: CGFloat = 180
    /// Caption/dot color — pass the surrounding theme's foreground.
    var foreground: Color = .white

    @State private var scrolledStyle: WidgetStyle?

    var body: some View {
        VStack(spacing: 10) {
            carousel
            Text((scrolledStyle ?? appState.widgetStyle).displayName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(foreground)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.15), value: scrolledStyle)
            pageDots
        }
        .onAppear { scrolledStyle = appState.widgetStyle }
        .onChange(of: scrolledStyle) { _, newValue in
            guard let newValue else { return }
            appState.commitWidgetStyle(newValue)
        }
    }

    private var carousel: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                ForEach(WidgetStyle.allCases, id: \.self) { style in
                    tile(style)
                        .id(style)
                        .containerRelativeFrame(.horizontal)
                        .scrollTransition { content, phase in
                            content
                                .scaleEffect(phase.isIdentity ? 1 : 0.84)
                                .opacity(phase.isIdentity ? 1 : 0.55)
                        }
                }
            }
            .scrollTargetLayout()
        }
        // Show a peek of the neighboring styles on both sides.
        .contentMargins(.horizontal, 88, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $scrolledStyle, anchor: .center)
        .scrollIndicators(.hidden)
        .frame(height: tileSize + 16)
    }

    private func tile(_ style: WidgetStyle) -> some View {
        Button {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                scrolledStyle = style
            }
            appState.commitWidgetStyle(style)
        } label: {
            WidgetFacePreview(style: style)
                .frame(width: tileSize, height: tileSize)
                .shadow(color: .black.opacity(0.35), radius: 14, y: 10)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    private var pageDots: some View {
        let current = scrolledStyle ?? appState.widgetStyle
        return HStack(spacing: 7) {
            ForEach(WidgetStyle.allCases, id: \.self) { style in
                Capsule()
                    .fill(style == current ? foreground.opacity(0.9) : foreground.opacity(0.18))
                    .frame(width: style == current ? 22 : 6, height: 6)
                    .animation(.spring(response: 0.3, dampingFraction: 0.72), value: current)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// Realistic mini render of a widget face. CD styles use the actual case
/// photos (bundled in the app catalog as well as the widget's) with a
/// gradient "album art" disc composited at the production geometry from
/// `PlayMeWidget`; Classic mocks the full-bleed art + sender pill look.
struct WidgetFacePreview: View {
    let style: WidgetStyle

    // Mirror of the widget's disc geometry (PlayMeWidget.swift).
    private static let discCenterX: CGFloat = 0.508
    private static let discCenterY: CGFloat = 0.500
    private static let discDiameterRatio: CGFloat = 0.870
    private static let hubHoleRatio: CGFloat = 0.24

    private static let artGradient = LinearGradient(
        colors: [AppAccentGradient.lilac, AppAccentGradient.pink, AppAccentGradient.peach],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)

            ZStack {
                switch style {
                case .cd:
                    Image("CDCase")
                        .resizable()
                        .scaledToFill()
                        .frame(width: s, height: s)

                    disc(diameter: s * Self.discDiameterRatio)
                        .position(x: s * Self.discCenterX, y: s * Self.discCenterY)

                case .classic:
                    Self.artGradient

                    HStack(spacing: s * 0.03) {
                        Circle()
                            .fill(Color.black.opacity(0.65))
                            .frame(width: s * 0.13, height: s * 0.13)
                        RoundedRectangle(cornerRadius: s * 0.035, style: .continuous)
                            .fill(Color.black.opacity(0.5))
                            .frame(width: s * 0.5, height: s * 0.1)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(s * 0.05)
                }

                if style != .classic {
                    mockPill(s: s)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, s * 0.054)
                }
            }
            .frame(width: s, height: s)
            .clipShape(RoundedRectangle(cornerRadius: s * 0.14, style: .continuous))
        }
        .aspectRatio(1, contentMode: .fit)
    }

    /// Gradient album-art disc with edge ring and see-through hub hole.
    private func disc(diameter: CGFloat) -> some View {
        ZStack {
            Circle().fill(Self.artGradient)
            Circle().strokeBorder(Color.black.opacity(0.35), lineWidth: max(0.8, diameter * 0.008))
        }
        .frame(width: diameter, height: diameter)
        .mask {
            PreviewDonut(holeRatio: Self.hubHoleRatio)
                .fill(style: FillStyle(eoFill: true))
        }
        .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
    }

    /// Miniature of the widget's frosted sender pill, including the grey
    /// heart shown on auto-filled messages.
    private func mockPill(s: CGFloat) -> some View {
        let em = s * 0.05
        return HStack(spacing: em * 0.5) {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 125 / 255, green: 133 / 255, blue: 144 / 255),
                            Color(red: 93 / 255, green: 100 / 255, blue: 110 / 255),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 0.8))
                .frame(width: em * 2.15, height: em * 2.15)
            Text("Molly sent you a song")
                .font(.system(size: max(8, em), weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Image(systemName: "heart.fill")
                .font(.system(size: max(7, em * 0.85), weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(.leading, em * 0.32)
        .padding(.trailing, em * 0.92)
        .padding(.vertical, em * 0.32)
        .background(Capsule().fill(Color(red: 28 / 255, green: 28 / 255, blue: 32 / 255).opacity(0.72)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
        .fixedSize()
    }
}

/// Disc silhouette with a centered hub hole (even-odd fill subtracts the
/// inner circle). Mirrors the widget's `DiscDonut`.
private struct PreviewDonut: Shape {
    var holeRatio: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addEllipse(in: rect)
        let holeD = rect.width * holeRatio
        p.addEllipse(in: CGRect(
            x: rect.midX - holeD / 2,
            y: rect.midY - holeD / 2,
            width: holeD,
            height: holeD
        ))
        return p
    }
}
