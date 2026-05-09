import SwiftUI

/// Screen 9.5 — Theme picker.
///
/// Drag-to-cycle carousel of the 4 themes. Live-updates
/// `appState.appTheme` so the screen itself recolors as the user
/// scrubs — that "the whole thing changes" moment is the point.
struct ThemePickerView: View {
    let appState: AppState
    let stepIdx: Int
    let totalSteps: Int
    let onContinue: () -> Void
    let onBack: (() -> Void)?

    private let itemWidth: CGFloat = 180

    @State private var index: Int
    @State private var dragOffset: CGFloat = 0
    @State private var dragging: Bool = false

    @Environment(\.riffTheme) private var theme

    init(
        appState: AppState,
        stepIdx: Int,
        totalSteps: Int,
        onContinue: @escaping () -> Void,
        onBack: (() -> Void)?
    ) {
        self.appState = appState
        self.stepIdx = stepIdx
        self.totalSteps = totalSteps
        self.onContinue = onContinue
        self.onBack = onBack
        let current = appState.appTheme
        let i = RiffTheme.all.firstIndex(of: current) ?? 0
        _index = State(initialValue: i)
    }

    var body: some View {
        RiffScreenChrome(
            stepIdx: stepIdx,
            totalSteps: totalSteps,
            onBack: onBack,
            horizontalPadding: 0
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Spacer()
                    RiffWordmark(size: 36, color: theme.fg, style: .heavy)
                    Spacer()
                }
                .padding(.bottom, 6)

                RiffStagger(delay: 0.06) {
                    RiffHeadline(text: "Pick your background.")
                        .padding(.horizontal, 24)
                }
                RiffStagger(delay: 0.14) {
                    RiffSubhead(text: "This sets the mood for the whole app.")
                        .padding(.horizontal, 24)
                }
                Text("(don't worry, you can always change this later)")
                    .font(.system(size: 12))
                    .italic()
                    .foregroundStyle(theme.faint)
                    .padding(.horizontal, 24)
                    .padding(.top, 6)

                ZStack {
                    swatchRow
                }
                .frame(maxHeight: .infinity)
                .padding(.top, 32)

                VStack(spacing: 8) {
                    Text(RiffTheme.all[index].displayName)
                        .font(.system(size: 22, weight: .semibold))
                        .tracking(-0.44)
                        .foregroundStyle(theme.fg)
                    Text("swipe to change")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.faint)
                    HStack(spacing: 7) {
                        ForEach(0..<RiffTheme.all.count, id: \.self) { i in
                            let active = i == index
                            Capsule()
                                .fill(active ? theme.fg : theme.border)
                                .frame(width: active ? 18 : 6, height: 6)
                                .animation(.spring(response: 0.32, dampingFraction: 0.65), value: index)
                        }
                    }
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 12)
            }
        } footer: {
            RiffPrimaryButton(title: "Continue", action: onContinue)
        }
    }

    private var swatchRow: some View {
        let dragFrac = -dragOffset / itemWidth
        let virtual = CGFloat(index) + dragFrac

        return GeometryReader { proxy in
            ZStack {
                Circle()
                    .stroke(theme.border, lineWidth: 1.5)
                    .frame(width: 168, height: 168)
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)

                ForEach(0..<RiffTheme.all.count, id: \.self) { i in
                    let other = RiffTheme.all[i]
                    let offset = CGFloat(i) - virtual
                    let abs = Swift.abs(offset)
                    let scale = max(0.55, 1 - abs * 0.22)
                    let opacity = max(0.18, 1 - abs * 0.45)
                    let zIndex = 100 - Int(abs * 10)

                    Circle()
                        .fill(other.bg)
                        .frame(width: 152, height: 152)
                        .overlay(
                            Circle().stroke(i == index ? theme.fg : Color.clear, lineWidth: 2)
                        )
                        .shadow(color: i == index ? Color.black.opacity(0.45) : Color.black.opacity(0.25),
                                radius: i == index ? 18 : 6, x: 0, y: i == index ? 18 : 6)
                        .scaleEffect(scale)
                        .opacity(opacity)
                        .position(
                            x: proxy.size.width / 2 + offset * itemWidth,
                            y: proxy.size.height / 2
                        )
                        .zIndex(Double(zIndex))
                        .animation(dragging ? nil : .spring(response: 0.38, dampingFraction: 0.7), value: index)
                        .onTapGesture {
                            select(i)
                        }
                }
            }
            .gesture(
                DragGesture()
                    .onChanged { val in
                        dragging = true
                        var bounded = val.translation.width
                        if index == 0 && bounded > 0 { bounded *= 0.4 }
                        if index == RiffTheme.all.count - 1 && bounded < 0 { bounded *= 0.4 }
                        dragOffset = bounded
                    }
                    .onEnded { _ in
                        let threshold = itemWidth * 0.28
                        var next = index
                        if dragOffset < -threshold && index < RiffTheme.all.count - 1 { next = index + 1 }
                        else if dragOffset > threshold && index > 0 { next = index - 1 }
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.7)) {
                            dragOffset = 0
                        }
                        dragging = false
                        if next != index { select(next) }
                    }
            )
        }
    }

    private func select(_ i: Int) {
        guard i >= 0 && i < RiffTheme.all.count else { return }
        index = i
        appState.appTheme = RiffTheme.all[i]
    }
}
