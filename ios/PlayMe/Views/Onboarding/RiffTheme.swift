import SwiftUI

/// Theme model for the RIFF onboarding flow. Mirrors `THEMES` in the
/// Claude design's `riff-screens-b.jsx`. Stored as a string id in
/// `AppState.appTheme` so the active theme survives relaunches and
/// drives the global app background outside onboarding.
struct RiffTheme: Equatable, Identifiable, Hashable {
    let id: String
    let displayName: String
    let bg: Color
    let fg: Color
    let bgUIColor: UIColor

    /// True when the foreground is dark (palette is light). Mirrors the
    /// `tones()` helper in `riff-atoms.jsx`.
    var isLight: Bool { id == "offwhite" || id == "cream" }

    /// Slightly translucent foreground. Used for body subhead copy.
    var sub: Color { fg.opacity(isLight ? 0.55 : 0.55) }
    /// Even more faded foreground. Used for placeholder / caption text.
    var faint: Color { fg.opacity(isLight ? 0.35 : 0.35) }
    /// Hairline border tone — works on both dark and light backgrounds
    /// because we always derive from the foreground color.
    var border: Color { fg.opacity(isLight ? 0.15 : 0.15) }
    /// Soft tinted fill (input bg, neutral surface). Pulled from the fg
    /// at very low opacity so it reads as "slightly lighter than bg" on
    /// dark themes and "slightly darker" on light themes.
    var softBg: Color { fg.opacity(isLight ? 0.04 : 0.05) }
}

extension RiffTheme {
    static let black = RiffTheme(
        id: "black",
        displayName: "Black",
        bg: Color(red: 0, green: 0, blue: 0),
        fg: Color(red: 1, green: 1, blue: 1),
        bgUIColor: UIColor(red: 0, green: 0, blue: 0, alpha: 1)
    )

    static let offwhite = RiffTheme(
        id: "offwhite",
        displayName: "Off-white",
        bg: Color(red: 0.957, green: 0.945, blue: 0.918),
        fg: Color(red: 0.04, green: 0.04, blue: 0.04),
        bgUIColor: UIColor(red: 0.957, green: 0.945, blue: 0.918, alpha: 1)
    )

    static let forest = RiffTheme(
        id: "forest",
        displayName: "Forest",
        bg: Color(red: 0.106, green: 0.227, blue: 0.169),
        fg: Color(red: 0.945, green: 0.922, blue: 0.851),
        bgUIColor: UIColor(red: 0.106, green: 0.227, blue: 0.169, alpha: 1)
    )

    static let red = RiffTheme(
        id: "red",
        displayName: "Graphic red",
        bg: Color(red: 0.784, green: 0.125, blue: 0.114),
        fg: Color(red: 1, green: 1, blue: 1),
        bgUIColor: UIColor(red: 0.784, green: 0.125, blue: 0.114, alpha: 1)
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
