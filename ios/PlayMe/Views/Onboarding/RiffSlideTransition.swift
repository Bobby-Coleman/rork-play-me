import SwiftUI

/// Slide-and-spring transition between onboarding steps. The new step
/// enters from the right (or left if going back) and the outgoing step
/// drifts 30% in the opposite direction with reduced opacity, matching
/// the React design's `SlideTransition`.
struct RiffSlideContainer<Content: View>: View {
    let stepKey: Int
    let isForward: Bool
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            content()
                .id(stepKey)
                .transition(asymmetricTransition)
        }
    }

    private var asymmetricTransition: AnyTransition {
        let insertion = AnyTransition.modifier(
            active: SlideOpacityModifier(translationFraction: isForward ? 1.0 : -1.0, opacity: 1),
            identity: SlideOpacityModifier(translationFraction: 0, opacity: 1)
        )
        let removal = AnyTransition.modifier(
            active: SlideOpacityModifier(translationFraction: isForward ? -0.3 : 0.3, opacity: 0.4),
            identity: SlideOpacityModifier(translationFraction: 0, opacity: 1)
        )
        return .asymmetric(insertion: insertion, removal: removal)
    }
}

/// Modifier used by both insertion and removal sides of the transition.
/// Translation is expressed as a fraction of the container width so the
/// curve matches the JS reference regardless of device size.
private struct SlideOpacityModifier: ViewModifier {
    let translationFraction: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        GeometryReader { proxy in
            content
                .offset(x: proxy.size.width * translationFraction)
                .opacity(opacity)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

/// Spring curve roughly equivalent to `cubic-bezier(0.34,1.36,0.4,1)` at
/// 460ms used by the React reference. Used as the explicit animation
/// argument when stepping the orchestrator's index.
extension Animation {
    static let riffSlide: Animation = .spring(response: 0.46, dampingFraction: 0.78)
}
