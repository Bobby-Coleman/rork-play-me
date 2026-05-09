import SwiftUI

/// Bottom-anchored CTA region with progress dots — the universal frame
/// for every step of the new RIFF onboarding. The status bar mock from
/// the React design is intentionally omitted here: the iOS system
/// status bar already paints in the right tone via `.preferredColorScheme`
/// driven by the theme.
struct RiffScreenChrome<Content: View, Footer: View>: View {
    var stepIdx: Int? = nil
    var totalSteps: Int? = nil
    var onBack: (() -> Void)? = nil
    var contentTopPadding: CGFloat = 8
    var horizontalPadding: CGFloat = 24
    var showProgressDots: Bool = true
    @ViewBuilder var content: () -> Content
    @ViewBuilder var footer: () -> Footer

    @Environment(\.riffTheme) private var theme

    var body: some View {
        ZStack(alignment: .top) {
            theme.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Content fills the available space above the footer.
                VStack(alignment: .leading, spacing: 0) {
                    content()
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.top, contentTopPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                VStack(spacing: 0) {
                    footer()
                        .padding(.horizontal, horizontalPadding)

                    if showProgressDots, let stepIdx, let totalSteps, totalSteps > 0 {
                        progressDots(idx: stepIdx, total: totalSteps)
                            .padding(.top, 18)
                    }
                }
                .padding(.bottom, 8)
            }

            if let onBack {
                HStack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(theme.fg.opacity(0.7))
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 6)
                    .padding(.top, 6)
                    Spacer()
                }
            }
        }
        .foregroundStyle(theme.fg)
        .preferredColorScheme(theme.isLight ? .light : .dark)
    }

    private func progressDots(idx: Int, total: Int) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { i in
                let active = i == idx
                Capsule()
                    .fill(active ? theme.fg : theme.border)
                    .frame(width: active ? 18 : 5, height: 5)
                    .animation(.spring(response: 0.32, dampingFraction: 0.65), value: idx)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// Convenience: footer-less variant for content-only screens (cold open).
extension RiffScreenChrome where Footer == EmptyView {
    init(
        stepIdx: Int? = nil,
        totalSteps: Int? = nil,
        onBack: (() -> Void)? = nil,
        contentTopPadding: CGFloat = 8,
        horizontalPadding: CGFloat = 24,
        showProgressDots: Bool = true,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.stepIdx = stepIdx
        self.totalSteps = totalSteps
        self.onBack = onBack
        self.contentTopPadding = contentTopPadding
        self.horizontalPadding = horizontalPadding
        self.showProgressDots = showProgressDots
        self.content = content
        self.footer = { EmptyView() }
    }
}
