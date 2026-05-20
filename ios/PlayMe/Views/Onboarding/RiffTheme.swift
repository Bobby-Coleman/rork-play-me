import SwiftUI

/// Theme model for the entire RIFF app. Originally introduced for the
/// onboarding flow (mirrors `THEMES` in the Claude design's
/// `riff-screens-b.jsx`), now used app-wide via `@Environment(\.riffTheme)`.
/// Stored as a string id in `AppState.appTheme` so the active theme
/// survives relaunches and drives the global background, accent buttons,
/// nav chrome, and tab bar.
///
/// Roles:
///   - `bg`        : full-screen backdrop
///   - `fg`        : primary text / icon color
///   - `accent`    : single CTA color (send, accept, reactions, badges)
///   - `accentOn`  : color of text/icons sitting on top of an `accent` fill
///   - `sub/faint/border/softBg` : derived foreground tones
struct RiffTheme: Equatable, Identifiable, Hashable {
    let id: String
    let displayName: String
    let bg: Color
    let fg: Color
    let accent: Color
    let accentOn: Color
    let bgUIColor: UIColor
    let accentUIColor: UIColor

    /// True when the foreground is dark (palette is light). Mirrors the
    /// `tones()` helper in `riff-atoms.jsx`.
    var isLight: Bool { id == "offwhite" || id == "cream" }

    /// Slightly translucent foreground. Used for body subhead copy.
    var sub: Color { fg.opacity(0.55) }
    /// Even more faded foreground. Used for placeholder / caption text.
    var faint: Color { fg.opacity(0.35) }
    /// Hairline border tone — works on both dark and light backgrounds
    /// because we always derive from the foreground color.
    var border: Color { fg.opacity(0.15) }
    /// Soft tinted fill (input bg, neutral surface). Pulled from the fg
    /// at very low opacity so it reads as "slightly lighter than bg" on
    /// dark themes and "slightly darker" on light themes.
    var softBg: Color { fg.opacity(isLight ? 0.06 : 0.08) }
    /// A slightly deeper surface fill, for nested cards or active states
    /// where `softBg` would be too subtle.
    var elevatedBg: Color { fg.opacity(isLight ? 0.10 : 0.14) }

    /// Toolbar color scheme that matches this theme's contrast.
    var toolbarColorScheme: ColorScheme { isLight ? .light : .dark }
}

extension RiffTheme {
    // The four canonical themes. Per-theme `accent` is the single CTA
    // color (send buttons, accept pills, reaction highlights, unread
    // badges). Terracotta — which was the universal accent before the
    // Phase B theming pass — now lives on `forest` where it's a natural
    // earth-tone pairing. The light and saturated-dark themes use
    // high-contrast monochrome accents.
    //
    // Adding a new theme: copy any block below, change `id`,
    // `displayName`, and four colors, append to `all`.

    static let black = RiffTheme(
        id: "black",
        displayName: "Black",
        bg: Color(red: 0, green: 0, blue: 0),
        fg: Color(red: 1, green: 1, blue: 1),
        // Cream accent on black reads premium and ties to the offwhite
        // theme's backdrop. Replaces the previous terracotta accent.
        accent: Color(red: 0.957, green: 0.945, blue: 0.918),
        accentOn: Color(red: 0.04, green: 0.04, blue: 0.04),
        bgUIColor: UIColor(red: 0, green: 0, blue: 0, alpha: 1),
        accentUIColor: UIColor(red: 0.957, green: 0.945, blue: 0.918, alpha: 1)
    )

    static let offwhite = RiffTheme(
        id: "offwhite",
        displayName: "Off-white",
        bg: Color(red: 0.957, green: 0.945, blue: 0.918),
        fg: Color(red: 0.04, green: 0.04, blue: 0.04),
        // Ink-on-paper monochrome. The accent is the same near-black as
        // the foreground; the visual hierarchy comes from the *fill*
        // (text vs solid pill), not a separate hue.
        accent: Color(red: 0.04, green: 0.04, blue: 0.04),
        accentOn: Color(red: 0.957, green: 0.945, blue: 0.918),
        bgUIColor: UIColor(red: 0.957, green: 0.945, blue: 0.918, alpha: 1),
        accentUIColor: UIColor(red: 0.04, green: 0.04, blue: 0.04, alpha: 1)
    )

    static let forest = RiffTheme(
        id: "forest",
        displayName: "Forest",
        bg: Color(red: 0.106, green: 0.227, blue: 0.169),
        fg: Color(red: 0.945, green: 0.922, blue: 0.851),
        // Terracotta against forest green is a classic vintage poster
        // pairing — the legacy app accent finally has a home.
        accent: Color(red: 0.76, green: 0.38, blue: 0.35),
        accentOn: Color(red: 1, green: 1, blue: 1),
        bgUIColor: UIColor(red: 0.106, green: 0.227, blue: 0.169, alpha: 1),
        accentUIColor: UIColor(red: 0.76, green: 0.38, blue: 0.35, alpha: 1)
    )

    static let red = RiffTheme(
        id: "red",
        displayName: "Graphic red",
        bg: Color(red: 0.784, green: 0.125, blue: 0.114),
        fg: Color(red: 1, green: 1, blue: 1),
        // Magazine-ad cream on saturated red. High contrast without
        // fighting the backdrop with another bright hue.
        accent: Color(red: 0.957, green: 0.945, blue: 0.918),
        accentOn: Color(red: 0.04, green: 0.04, blue: 0.04),
        bgUIColor: UIColor(red: 0.784, green: 0.125, blue: 0.114, alpha: 1),
        accentUIColor: UIColor(red: 0.957, green: 0.945, blue: 0.918, alpha: 1)
    )

    static let all: [RiffTheme] = [.black, .offwhite, .forest, .red]

    static func byId(_ id: String) -> RiffTheme {
        all.first(where: { $0.id == id }) ?? .black
    }
}

// MARK: - Environment

private struct RiffThemeKey: EnvironmentKey {
    static let defaultValue: RiffTheme = .black
}

extension EnvironmentValues {
    var riffTheme: RiffTheme {
        get { self[RiffThemeKey.self] }
        set { self[RiffThemeKey.self] = newValue }
    }
}

extension View {
    /// Inject a `RiffTheme` into the environment for descendant views.
    func riffTheme(_ theme: RiffTheme) -> some View {
        environment(\.riffTheme, theme)
    }
}
