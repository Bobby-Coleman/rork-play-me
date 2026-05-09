import SwiftUI

/// Screen 9 — Taste.
///
/// Genre chips + horizontal artist carousel. Selections write back to
/// `appState.tasteGenres` / `appState.tasteArtists`; both arrays are
/// persisted to `users/{uid}` during `register(...)`. The lists are
/// ship-as-hardcoded (per plan); they can be migrated to a server-driven
/// list later without touching the screen.
struct TasteView: View {
    let appState: AppState
    let stepIdx: Int
    let totalSteps: Int
    let onContinue: () -> Void
    let onBack: (() -> Void)?

    @State private var genres: Set<String> = []
    @State private var artists: Set<String> = []

    private static let genreChips: [String] = [
        "Indie", "Hip-Hop", "Jazz", "Electronic", "Ambient", "Punk", "Folk",
        "R&B", "Experimental", "Soul", "Shoegaze", "House", "Country", "Dub",
        "Techno", "Pop", "Rock", "Classical", "Reggae", "Metal", "Disco",
        "Funk", "Bossa Nova", "Trip-Hop"
    ]

    private static let featuredArtists: [String] = [
        "Frank Ocean", "Joni Mitchell", "MF DOOM", "Aphex Twin", "Fiona Apple",
        "Burial", "Stevie Wonder", "Mitski", "Arthur Russell", "Angel Olsen",
        "Caroline Polachek", "Yves Tumor", "King Krule", "Sade", "Nick Drake"
    ]

    private var totalSelected: Int { genres.count + artists.count }

    @Environment(\.riffTheme) private var theme

    var body: some View {
        RiffScreenChrome(
            stepIdx: stepIdx,
            totalSteps: totalSteps,
            onBack: onBack,
            horizontalPadding: 0
        ) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    RiffStagger(delay: 0.06) {
                        RiffHeadline(text: "Tell us your taste.")
                    }
                    RiffStagger(delay: 0.14) {
                        RiffSubhead(text: "Pick a few — we'll take it from there.")
                    }
                }
                .padding(.horizontal, 24)

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        FlowLayout(spacing: 8) {
                            ForEach(Self.genreChips, id: \.self) { chip in
                                let on = genres.contains(chip)
                                RiffChip(title: chip, on: on) {
                                    if on { genres.remove(chip) } else { genres.insert(chip) }
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 22)

                        Text("ARTISTS YOU LOVE")
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(1.1)
                            .foregroundStyle(theme.faint)
                            .padding(.horizontal, 24)
                            .padding(.top, 24)
                            .padding(.bottom, 12)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(Array(Self.featuredArtists.enumerated()), id: \.offset) { idx, artist in
                                    let on = artists.contains(artist)
                                    artistTile(artist: artist, seed: 50 + idx, on: on)
                                        .onTapGesture {
                                            if on { artists.remove(artist) } else { artists.insert(artist) }
                                        }
                                }
                            }
                            .padding(.horizontal, 24)
                            .padding(.bottom, 12)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
        } footer: {
            RiffPrimaryButton(
                title: totalSelected > 0 ? "Continue (\(totalSelected))" : "Continue",
                disabled: totalSelected < 1,
                action: handleContinue
            )
        }
        .onAppear {
            genres = Set(appState.tasteGenres)
            artists = Set(appState.tasteArtists)
        }
    }

    private func handleContinue() {
        appState.tasteGenres = Array(genres)
        appState.tasteArtists = Array(artists)
        onContinue()
    }

    @ViewBuilder
    private func artistTile(artist: String, seed: Int, on: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                RiffPlaceholderImage(seed: seed, cornerRadius: 8)
                    .frame(width: 96, height: 96)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(on ? theme.fg : Color.clear, lineWidth: 2)
                    )
                if on {
                    ZStack {
                        Circle().fill(theme.fg)
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(theme.bg)
                    }
                    .frame(width: 22, height: 22)
                    .padding(6)
                }
            }
            Text(artist)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.fg)
                .lineLimit(1)
        }
        .frame(width: 96)
    }
}

// MARK: - Flow layout

/// Wraps chips onto multiple rows. Native `Layout` is the cleanest way
/// to mirror the React `flexWrap: 'wrap'` behavior without nesting an
/// HStack-of-HStacks and computing rows ourselves.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxRowWidth: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > maxWidth {
                maxRowWidth = max(maxRowWidth, x - spacing)
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        maxRowWidth = max(maxRowWidth, x - spacing)
        y += rowHeight
        return CGSize(width: maxRowWidth, height: y)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.minX + maxWidth {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
