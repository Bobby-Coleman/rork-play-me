import SwiftUI
import UIKit

// MARK: - Wordmark

/// "RIFF" wordmark in the heavy/condensed/serif variants from the design.
/// Defaults to `.heavy`, which is the one mounted in the cold-open
/// animation and on every brand surface.
struct RiffWordmark: View {
    enum Style { case heavy, condensed, serif }

    var text: String = "RIFF"
    var size: CGFloat = 84
    var color: Color? = nil
    var style: Style = .heavy

    var body: some View {
        switch style {
        case .heavy:
            Text(text)
                .font(.system(size: size, weight: .black, design: .default))
                .tracking(-size * 0.04)
                .lineSpacing(0)
                .foregroundStyle(color ?? .white)
        case .condensed:
            Text(text)
                .font(.system(size: size, weight: .black, design: .default))
                .tracking(-size * 0.02)
                .foregroundStyle(color ?? .white)
        case .serif:
            Text(text)
                .font(.system(size: size, weight: .black, design: .serif))
                .italic()
                .tracking(-size * 0.03)
                .foregroundStyle(color ?? .white)
        }
    }
}

// MARK: - Headline / Subhead / Label

struct RiffHeadline: View {
    let text: String
    var size: CGFloat = 30

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .semibold))
            .tracking(-size * 0.022)
            .lineSpacing(size * 0.08 - size * 0.85)
            .multilineTextAlignment(.leading)
    }
}

struct RiffSubhead: View {
    let text: String
    @Environment(\.riffTheme) private var theme

    var body: some View {
        Text(text)
            .font(.system(size: 15))
            .lineSpacing(15 * 0.4 - 15)
            .foregroundStyle(theme.sub)
    }
}

struct RiffLabel: View {
    let text: String
    @Environment(\.riffTheme) private var theme

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(11 * 0.1)
            .foregroundStyle(theme.faint)
    }
}

// MARK: - Primary button (pill)

struct RiffPrimaryButton: View {
    let title: String
    var disabled: Bool = false
    let action: () -> Void

    @Environment(\.riffTheme) private var theme
    @State private var pressed = false

    var body: some View {
        Button(action: { if !disabled { action() } }) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .tracking(-0.16)
                .foregroundStyle(disabled ? theme.fg.opacity(theme.isLight ? 0.45 : 0.45) : theme.bg)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    Capsule()
                        .fill(disabled ? theme.fg.opacity(theme.isLight ? 0.15 : 0.18) : theme.fg)
                )
                .scaleEffect(pressed && !disabled ? 0.97 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !pressed {
                        withAnimation(.spring(response: 0.12, dampingFraction: 0.7)) { pressed = true }
                    }
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.12, dampingFraction: 0.7)) { pressed = false }
                }
        )
    }
}

struct RiffTextLink: View {
    let title: String
    let action: () -> Void

    @Environment(\.riffTheme) private var theme

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14))
                .foregroundStyle(theme.sub)
                .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Underlined input field

/// Replicates the design's `FieldInput` — large text, animated underline
/// that thickens + lifts on focus, optional monospace style for codes.
/// All view-level styling stays internal so call sites can stay one-line.
struct RiffFieldInput: View {
    @Binding var text: String
    var placeholder: String = ""
    var prefix: String? = nil
    var monospace: Bool = false
    var keyboard: UIKeyboardType = .default
    var contentType: UITextContentType? = nil
    var capitalization: TextInputAutocapitalization = .sentences
    var autocorrection: Bool = true
    var maxLength: Int? = nil
    var autoFocus: Bool = false
    var onChange: ((String) -> Void)? = nil
    var onSubmit: (() -> Void)? = nil
    var onFocusChange: ((Bool) -> Void)? = nil

    @Environment(\.riffTheme) private var theme
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            if let prefix {
                Text(prefix)
                    .foregroundStyle(theme.faint)
                    .font(.system(size: 22, design: monospace ? .monospaced : .default))
            }
            TextField("", text: $text, prompt: placeholderText)
                .font(.system(size: 22, weight: .medium, design: monospace ? .monospaced : .default))
                .tracking(monospace ? 22 * 0.2 : -0.22)
                .foregroundStyle(theme.fg)
                .keyboardType(keyboard)
                .textContentType(contentType)
                .textInputAutocapitalization(capitalization)
                .autocorrectionDisabled(!autocorrection)
                .focused($focused)
                .submitLabel(.go)
                .onSubmit { onSubmit?() }
                .onChange(of: text) { _, newValue in
                    var trimmed = newValue
                    if let maxLength, trimmed.count > maxLength {
                        trimmed = String(trimmed.prefix(maxLength))
                        text = trimmed
                        return
                    }
                    onChange?(trimmed)
                }
                .onChange(of: focused) { _, newValue in
                    onFocusChange?(newValue)
                }
        }
        .padding(.bottom, 10)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(focused ? theme.fg : theme.border)
                .frame(height: focused ? 2 : 1)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: focused)
        }
        .offset(y: focused ? -1 : 0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: focused)
        .onAppear {
            if autoFocus {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                    focused = true
                }
            }
        }
    }

    private var placeholderText: Text? {
        guard !placeholder.isEmpty else { return nil }
        return Text(placeholder).foregroundColor(theme.faint)
    }
}

// MARK: - Stagger (delayed appearance)

/// Mirrors the design's `Stagger` helper. Defers child appearance by
/// `delay` seconds, then fades + slides into place with the same spring
/// curve as the JS reference.
struct RiffStagger<Content: View>: View {
    var delay: Double = 0
    var fromOffsetY: CGFloat = 12
    var duration: Double = 0.48
    @ViewBuilder var content: () -> Content

    @State private var visible = false

    var body: some View {
        content()
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : fromOffsetY)
            .animation(
                .spring(response: duration, dampingFraction: 0.72)
                    .delay(delay),
                value: visible
            )
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.001) {
                    visible = true
                }
            }
    }
}

// MARK: - Typewriter

/// Char-by-char reveal with an optional blinking caret. Used on the
/// reveal screen tagline ("Discover new music from your best friends.")
struct RiffTypewriter: View {
    let text: String
    var startDelay: Double = 0
    var charDelay: Double = 0.032
    var caret: Bool = true
    var font: Font = .system(size: 15)
    var alignment: TextAlignment = .center
    var color: Color? = nil

    @State private var typed: String = ""
    @State private var done: Bool = false
    @State private var caretOpaque: Bool = true
    @Environment(\.riffTheme) private var theme

    var body: some View {
        Group {
            if alignment == .center {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Spacer(minLength: 0)
                    typedView
                    Spacer(minLength: 0)
                }
            } else {
                typedView
            }
        }
        .task(id: text) {
            await runTyping()
        }
    }

    private var typedView: some View {
        HStack(alignment: .lastTextBaseline, spacing: 1) {
            Text(typed)
                .font(font)
                .multilineTextAlignment(alignment)
                .foregroundStyle(color ?? theme.fg.opacity(0.78))
            if caret {
                Rectangle()
                    .frame(width: 2, height: 17)
                    .foregroundStyle(color ?? theme.fg.opacity(0.78))
                    .opacity(caretOpaque ? 1 : 0)
            }
        }
    }

    private func runTyping() async {
        typed = ""
        done = false
        caretOpaque = true
        try? await Task.sleep(nanoseconds: UInt64(startDelay * 1_000_000_000))
        for char in text {
            typed.append(char)
            let extra: Double
            switch char {
            case ",": extra = 0.18
            case ".": extra = 0.22
            default:  extra = 0
            }
            try? await Task.sleep(nanoseconds: UInt64((charDelay + extra) * 1_000_000_000))
        }
        done = true
        // Blinking caret loop.
        while !Task.isCancelled, done {
            try? await Task.sleep(nanoseconds: 450_000_000)
            caretOpaque.toggle()
        }
    }
}

// MARK: - Chip (selectable pill)

struct RiffChip: View {
    let title: String
    var on: Bool
    let action: () -> Void

    @Environment(\.riffTheme) private var theme
    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .padding(.horizontal, 16)
                .frame(height: 38)
                .foregroundStyle(on ? theme.bg : theme.fg)
                .background(
                    Capsule()
                        .fill(on ? theme.fg : Color.clear)
                )
                .overlay(
                    Capsule()
                        .stroke(on ? theme.fg : theme.border, lineWidth: 1.5)
                )
                .scaleEffect(pressed ? 0.94 : 1)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !pressed { withAnimation(.spring(response: 0.16, dampingFraction: 0.65)) { pressed = true } }
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.16, dampingFraction: 0.65)) { pressed = false }
                }
        )
    }
}

// MARK: - Placeholder image (striped grayscale)

/// Fallback artwork for the cold-open animation, social-proof tiles, and
/// any thumb that doesn't yet have a real image. Mirrors the design's
/// `PlaceholderImage` (varied stripe angles + tones + soft vignette) so
/// the screens read as "actual covers" before real photos drop in.
struct RiffPlaceholderImage: View {
    let seed: Int
    var cornerRadius: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            let palette = Self.palettes[seed % Self.palettes.count]
            let (angle, stripeW) = Self.derivedRandoms(for: seed)
            let variant = seed % 4

            ZStack {
                palette[0]

                StripePattern(stripeW: stripeW, palette: palette)
                    .rotationEffect(.degrees(angle))
                    .scaleEffect(2)
                    .clipped()

                switch variant {
                case 0:
                    Circle()
                        .fill(palette[2].opacity(0.55))
                        .frame(width: proxy.size.width * 0.44, height: proxy.size.height * 0.44)
                case 1:
                    Rectangle()
                        .fill(palette[2].opacity(0.4))
                        .frame(width: proxy.size.width * 0.6, height: proxy.size.height * 0.6)
                case 2:
                    Group {
                        Circle().stroke(palette[2].opacity(0.6), lineWidth: 1)
                            .frame(width: proxy.size.width * 0.36, height: proxy.size.height * 0.36)
                        Circle().stroke(palette[2].opacity(0.6), lineWidth: 1)
                            .frame(width: proxy.size.width * 0.56, height: proxy.size.height * 0.56)
                        Circle().stroke(palette[2].opacity(0.6), lineWidth: 1)
                            .frame(width: proxy.size.width * 0.76, height: proxy.size.height * 0.76)
                    }
                default:
                    Triangle()
                        .fill(palette[2].opacity(0.45))
                        .frame(width: proxy.size.width * 0.6, height: proxy.size.height * 0.6)
                }

                RadialGradient(
                    colors: [Color.black.opacity(0), Color.black.opacity(0.55)],
                    center: .center,
                    startRadius: proxy.size.width * 0.3,
                    endRadius: proxy.size.width * 0.55
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        }
    }

    private static func derivedRandoms(for seed: Int) -> (Double, CGFloat) {
        let rng = SeededRandom(seed: seed + 1)
        var gen = rng.makeGenerator()
        let angle = Double.random(in: 0...180, using: &gen)
        let stripeW = CGFloat.random(in: 4...12, using: &gen)
        return (angle, stripeW)
    }

    private static let palettes: [[Color]] = [
        [Color(white: 0.04), Color(white: 0.12), Color(white: 0.18)],
        [Color(white: 0.07), Color(white: 0.15), Color(white: 0.23)],
        [Color(white: 0.05), Color(white: 0.10), Color(white: 0.25)],
        [Color(white: 0.03), Color(white: 0.11), Color(white: 0.20)],
        [Color(white: 0.06), Color(white: 0.13), Color(white: 0.22)],
        [Color(white: 0.04), Color(white: 0.10), Color(white: 0.18)],
        [Color(white: 0.06), Color(white: 0.13), Color(white: 0.21)],
        [Color(white: 0.05), Color(white: 0.11), Color(white: 0.16)]
    ]
}

private struct StripePattern: View {
    let stripeW: CGFloat
    let palette: [Color]

    var body: some View {
        GeometryReader { proxy in
            let count = Int(ceil(proxy.size.width / stripeW)) + 4
            HStack(spacing: 0) {
                ForEach(0..<count, id: \.self) { i in
                    if i % 2 == 0 {
                        Rectangle().fill(palette[1]).frame(width: stripeW)
                    } else {
                        Rectangle().fill(palette[0]).frame(width: stripeW * 0.6)
                        Rectangle().fill(palette[2]).frame(width: stripeW * 0.4)
                    }
                }
            }
        }
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.15))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.1, y: rect.maxY - rect.height * 0.15))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.1, y: rect.maxY - rect.height * 0.15))
        path.closeSubpath()
        return path
    }
}

// Lightweight deterministic RNG so seeded placeholders look the same
// every render. SystemRandomNumberGenerator can't be seeded, so we wrap
// a linear-congruential generator behind the standard protocol.
private final class SeededRandom {
    private var state: UInt64

    init(seed: Int) {
        self.state = UInt64(bitPattern: Int64(seed)) &* 9301 &+ 49297
    }

    func makeGenerator() -> Generator {
        Generator(parent: self)
    }

    fileprivate func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }

    struct Generator: RandomNumberGenerator {
        let parent: SeededRandom
        mutating func next() -> UInt64 {
            return parent.next()
        }
    }
}
